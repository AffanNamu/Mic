import type { Deps } from './deps.ts';
import { one, run, tx } from './db.ts';
import { addMs, iso } from './clock.ts';
import { randomToken, sha256Hex } from './crypto.ts';
import { audit } from './audit.ts';
import * as ledger from './ledger.ts';
import { sniffAudio, wavDurationMs } from './audio.ts';
import { stylePrompt } from './style.ts';
import { withTimeout } from './timeout.ts';
import { ProviderError } from './provider/types.ts';
import type { SongRequest } from './provider/types.ts';
import { MAX_ENROLL_ATTEMPTS } from './voices.ts';

type Row = Record<string, unknown>;

export interface WorkerTimeouts {
  submitMs: number;
  pollMs: number;
  downloadMs: number;
  enrollMs: number;
}
export const DEFAULT_TIMEOUTS: WorkerTimeouts = { submitMs: 30_000, pollMs: 20_000, downloadMs: 60_000, enrollMs: 60_000 };
const MAX_SUBMIT_ATTEMPTS = 4;
const MAX_POLL_FAILURES = 5;
const MAX_DOWNLOAD_ATTEMPTS = 3;
/** Anything smaller than this cannot be a real song; it is an error body or an empty file. */
export const MIN_SONG_BYTES = 4096;
const CREDENTIAL_BLOCK_MS = 5 * 60_000;

/** User-facing wording for failure codes. Provider text is never shown to users. */
const MESSAGES: Record<string, string> = {
  provider_unavailable: 'The music service is not responding right now. Your credits were returned. Please try again later.',
  provider_credentials: 'Song generation is temporarily unavailable. Your credits were returned.',
  provider_rejected: 'The music service could not make this song from your request. Your credits were returned.',
  submit_outcome_unknown: 'We could not confirm that the music service received your request, so it was stopped and your credits were returned.',
  timeout: 'This song took too long and was stopped. Your credits were returned.',
  poll_failed: 'We lost contact with the music service while your song was being made. Your credits were returned.',
  empty_result: 'The music service finished but returned no audio. Your credits were returned.',
  invalid_audio: 'The music service returned a file that is not playable audio. Your credits were returned.',
  download_failed: 'Your song was made but could not be retrieved. Your credits were returned.',
  provider_failed: 'The music service could not finish this song. Your credits were returned.',
  voice_unavailable: 'The voice for this song is no longer available. Your credits were returned.',
  internal_error: 'Something went wrong on our side. Your credits were returned.',
};

function asProviderError(err: unknown): ProviderError {
  if (err instanceof ProviderError) return err;
  const name = (err as { name?: string })?.name;
  if (name === 'AbortError') return new ProviderError('timeout', 'aborted', { outcome: 'unknown' });
  return new ProviderError('provider_error', String(err), { outcome: 'unknown' });
}

const backoffMs = (attempt: number, retryAfterMs?: number) =>
  Math.max(retryAfterMs ?? 0, Math.min(30_000, 1000 * 2 ** attempt));

export class JobWorker {
  private readonly deps: Deps;
  private readonly timeouts: WorkerTimeouts;
  private timer: NodeJS.Timeout | null = null;
  private running = false;

  constructor(deps: Deps, timeouts: Partial<WorkerTimeouts> = {}) {
    this.deps = deps;
    this.timeouts = { ...DEFAULT_TIMEOUTS, ...timeouts };
  }

  start(intervalMs = 1000): void {
    if (this.timer) return;
    this.timer = setInterval(() => {
      if (this.running) return;
      this.running = true;
      this.tick().catch((err) => this.deps.log.error({ err: String(err) }, 'worker tick failed'))
        .finally(() => { this.running = false; });
    }, intervalMs);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  /** Processes everything that is due, once. Returns how many steps ran. */
  async tick(max = 20): Promise<number> {
    let steps = 0;
    for (; steps < max; steps++) {
      const voice = this.claimVoice();
      if (voice) { await this.stepVoice(voice); continue; }
      const job = this.claimJob();
      if (job) { await this.stepJob(job); continue; }
      break;
    }
    return steps;
  }

  // ---------------------------------------------------------------- claiming

  private claimJob(): Row | undefined {
    const { db, clock, config } = this.deps;
    return tx(db, () => {
      const now = iso(clock.now());
      const row = one(db,
        `SELECT * FROM jobs WHERE status IN ('queued','submitting','processing','downloading')
            AND next_run_at <= ? AND (lease_until IS NULL OR lease_until < ?) ORDER BY next_run_at LIMIT 1`, now, now);
      if (!row) return undefined;
      run(db, `UPDATE jobs SET lease_until = ? WHERE id = ?`, iso(addMs(clock.now(), config.leaseMs)), String(row['id']));
      return row;
    });
  }

  private claimVoice(): Row | undefined {
    const { db, clock, config } = this.deps;
    return tx(db, () => {
      const now = iso(clock.now());
      const row = one(db,
        `SELECT * FROM voices WHERE status = 'enrolling' AND audio_blob_key IS NOT NULL
            AND (lease_until IS NULL OR lease_until < ?) ORDER BY created_at LIMIT 1`, now);
      if (!row) return undefined;
      run(db, `UPDATE voices SET lease_until = ? WHERE id = ?`, iso(addMs(clock.now(), config.leaseMs)), String(row['id']));
      return row;
    });
  }

  // ------------------------------------------------------------------ voices

  private async stepVoice(voice: Row): Promise<void> {
    const { db, clock, blobs, provider, log } = this.deps;
    const id = String(voice['id']);
    const attempts = Number(voice['enroll_attempts']);
    const fail = (code: string, message: string) => {
      run(db, `UPDATE voices SET status = 'failed', failure_code = ?, failure_message = ?, lease_until = NULL, updated_at = ? WHERE id = ?`,
        code, message, iso(clock.now()), id);
      audit(db, clock, { userId: String(voice['user_id']), kind: 'voice.enrollment_failed', subjectType: 'voice', subjectId: id, detail: { code } });
    };

    // A crash mid-call leaves a lease with attempts already counted; never silently re-bill beyond the cap.
    if (attempts >= MAX_ENROLL_ATTEMPTS) { fail('enroll_attempts_exhausted', 'Enrollment failed too many times. Upload a new recording.'); return; }
    run(db, `UPDATE voices SET enroll_attempts = enroll_attempts + 1 WHERE id = ?`, id);

    try {
      const audio = await blobs.get(String(voice['audio_blob_key']));
      const result = await withTimeout(this.timeouts.enrollMs, (signal) =>
        provider.enrollVoice({ audio, mime: String(voice['audio_mime']), fileName: `voice-${id}` }, signal));
      const caps = provider.capabilities();
      run(db,
        `UPDATE voices SET status = 'ready', provider = ?, provider_voice_id = ?, supports_singing = ?, provider_cost_micros = ?,
                lease_until = NULL, failure_code = NULL, failure_message = NULL, updated_at = ? WHERE id = ?`,
        provider.name, result.providerVoiceId, caps.voiceConditioning ? 1 : 0,
        result.costMicros ?? caps.estimatedEnrollCostMicros, iso(clock.now()), id);
      audit(db, clock, { userId: String(voice['user_id']), kind: 'voice.enrolled', subjectType: 'voice', subjectId: id });
    } catch (err) {
      const e = asProviderError(err);
      this.noteProviderHealth(e);
      log.warn({ voiceId: id, code: e.code, outcome: e.outcome }, 'voice enrollment failed');
      if (e.outcome === 'not_started' && attempts + 1 < MAX_ENROLL_ATTEMPTS) {
        // Safe to try again later without risk of a second charge.
        run(db, `UPDATE voices SET lease_until = ? WHERE id = ?`, iso(addMs(clock.now(), backoffMs(attempts, e.retryAfterMs))), id);
        return;
      }
      fail(e.code, e.outcome === 'unknown'
        ? 'We could not confirm the music service accepted this recording. Try again, or upload a new one.'
        : 'The music service could not use this recording. Try a clearer solo recording.');
    }
  }

  // -------------------------------------------------------------------- jobs

  private noteProviderHealth(e: ProviderError): void {
    if (e.credentialsInvalid) this.deps.health.block(this.deps.clock, CREDENTIAL_BLOCK_MS, 'provider credentials rejected');
    else if (e.providerFunds) this.deps.health.block(this.deps.clock, CREDENTIAL_BLOCK_MS, 'provider balance exhausted');
  }

  private failJob(job: Row, code: string, detail?: Record<string, unknown>): void {
    const { db, clock } = this.deps;
    const id = String(job['id']);
    tx(db, () => {
      const now = iso(clock.now());
      run(db, `UPDATE jobs SET status = 'failed', failure_code = ?, failure_message = ?, lease_until = NULL, completed_at = ?, updated_at = ? WHERE id = ?
                 AND status NOT IN ('completed','failed','cancelled')`,
        code, MESSAGES[code] ?? MESSAGES['internal_error']!, now, now, id);
      ledger.release(db, clock, id, `Failed: ${code}`);
      audit(db, clock, { userId: String(job['user_id']), kind: 'job.failed', subjectType: 'job', subjectId: id, detail: { code, ...detail } });
    });
  }

  private reschedule(job: Row, fields: { status?: string; attempts: number; delayMs: number; resultJson?: string }): void {
    const { db, clock } = this.deps;
    run(db,
      `UPDATE jobs SET status = COALESCE(?, status), attempts = ?, next_run_at = ?, lease_until = NULL,
              result_json = COALESCE(?, result_json), updated_at = ? WHERE id = ?`,
      fields.status ?? null, fields.attempts, iso(addMs(clock.now(), fields.delayMs)),
      fields.resultJson ?? null, iso(clock.now()), String(job['id']));
  }

  private async stepJob(job: Row): Promise<void> {
    const { clock } = this.deps;
    const status = String(job['status']);

    if (status === 'submitting') {
      // We marked the job as submitting and then lost the process before learning the outcome.
      // The provider may or may not have started it; resubmitting could bill twice.
      this.failJob(job, 'submit_outcome_unknown', { recovered: true });
      return;
    }
    if (iso(clock.now()) > String(job['deadline_at'])) {
      this.failJob(job, 'timeout', { step: status });
      return;
    }
    try {
      if (status === 'queued') await this.submit(job);
      else if (status === 'processing') await this.poll(job);
      else if (status === 'downloading') await this.download(job);
    } catch (err) {
      this.deps.log.error({ jobId: job['id'], err: String(err) }, 'unexpected job error');
      this.failJob(job, 'internal_error');
    }
  }

  private async submit(job: Row): Promise<void> {
    const { db, clock, provider, log } = this.deps;
    const id = String(job['id']);
    const attempts = Number(job['attempts']);

    const settings = JSON.parse(String(job['settings_json'])) as { style: Record<string, string>; advanced: Record<string, string> };
    let providerVoiceId: string | null = null;
    if (job['voice_id']) {
      const voice = one(db, `SELECT status, provider_voice_id FROM voices WHERE id = ?`, String(job['voice_id']));
      const consent = one(db, `SELECT 1 AS x FROM consents WHERE voice_id = ? AND revoked_at IS NULL`, String(job['voice_id']));
      if (!voice || voice['status'] !== 'ready' || !voice['provider_voice_id'] || !consent) {
        this.failJob(job, 'voice_unavailable');
        return;
      }
      providerVoiceId = String(voice['provider_voice_id']);
    }
    const request: SongRequest = {
      lyrics: String(job['lyrics']), language: String(job['language']),
      stylePrompt: stylePrompt(settings.style), providerVoiceId, settings: settings.advanced,
    };

    // Persist the intent BEFORE calling out. If the process dies during the call, recovery sees
    // `submitting` and knows the outcome is unknown, instead of guessing.
    run(db, `UPDATE jobs SET status = 'submitting', submit_started_at = ?, updated_at = ? WHERE id = ?`,
      iso(clock.now()), iso(clock.now()), id);

    try {
      const { providerTaskId } = await withTimeout(this.timeouts.submitMs, (signal) => provider.submitSong(request, signal));
      const estimate = provider.capabilities().estimatedSongCostMicros;
      run(db,
        `UPDATE jobs SET status = 'processing', provider_task_id = ?, provider_cost_micros = ?, attempts = 0,
                next_run_at = ?, lease_until = NULL, updated_at = ? WHERE id = ?`,
        providerTaskId, estimate, iso(addMs(clock.now(), 3000)), iso(clock.now()), id);
      audit(db, clock, { userId: String(job['user_id']), kind: 'job.submitted', subjectType: 'job', subjectId: id });
    } catch (err) {
      const e = asProviderError(err);
      this.noteProviderHealth(e);
      log.warn({ jobId: id, code: e.code, outcome: e.outcome, status: e.httpStatus }, 'submit failed');
      if (e.credentialsInvalid) { this.failJob(job, 'provider_credentials', { code: e.code }); return; }
      if (e.outcome === 'not_started') {
        if (attempts + 1 >= MAX_SUBMIT_ATTEMPTS) { this.failJob(job, 'provider_unavailable', { code: e.code }); return; }
        run(db, `UPDATE jobs SET submit_started_at = NULL WHERE id = ?`, id);
        this.reschedule(job, { status: 'queued', attempts: attempts + 1, delayMs: backoffMs(attempts, e.retryAfterMs) });
        return;
      }
      if (e.outcome === 'unknown') { this.failJob(job, 'submit_outcome_unknown', { code: e.code }); return; }
      this.failJob(job, e.providerFunds ? 'provider_unavailable' : 'provider_rejected', { code: e.code });
    }
  }

  private async poll(job: Row): Promise<void> {
    const { provider, log } = this.deps;
    const attempts = Number(job['attempts']);
    try {
      const r = await withTimeout(this.timeouts.pollMs, (signal) => provider.pollSong(String(job['provider_task_id']), signal));
      if (r.state === 'running') {
        this.reschedule(job, { attempts: 0, delayMs: 5000 });
      } else if (r.state === 'failed') {
        log.warn({ jobId: job['id'], code: r.code }, 'provider reported failure');
        this.failJob(job, 'provider_failed', { code: r.code });
      } else if (!r.audioUrl) {
        this.failJob(job, 'empty_result');
      } else {
        const result = JSON.stringify({ audioUrl: r.audioUrl, durationMs: r.durationMs, costMicros: r.costMicros });
        if (r.costMicros !== null) run(this.deps.db, `UPDATE jobs SET provider_cost_micros = ? WHERE id = ?`, r.costMicros, String(job['id']));
        this.reschedule(job, { status: 'downloading', attempts: 0, delayMs: 0, resultJson: result });
      }
    } catch (err) {
      const e = asProviderError(err);
      this.noteProviderHealth(e);
      if (e.credentialsInvalid) { this.failJob(job, 'provider_credentials', { code: e.code }); return; }
      if (e.outcome === 'terminal' || attempts + 1 >= MAX_POLL_FAILURES) {
        this.failJob(job, 'poll_failed', { code: e.code });
        return;
      }
      this.reschedule(job, { attempts: attempts + 1, delayMs: backoffMs(attempts, e.retryAfterMs) });
    }
  }

  private async download(job: Row): Promise<void> {
    const { db, clock, blobs, provider } = this.deps;
    const id = String(job['id']);
    const attempts = Number(job['attempts']);
    const result = JSON.parse(String(job['result_json'])) as { audioUrl: string; durationMs: number | null };

    let audio: Buffer;
    try {
      audio = await withTimeout(this.timeouts.downloadMs, (signal) => provider.downloadAudio(result.audioUrl, signal));
    } catch (err) {
      const e = asProviderError(err);
      if (e.outcome === 'terminal' || attempts + 1 >= MAX_DOWNLOAD_ATTEMPTS) { this.failJob(job, 'download_failed', { code: e.code }); return; }
      this.reschedule(job, { attempts: attempts + 1, delayMs: backoffMs(attempts, e.retryAfterMs) });
      return;
    }

    // Never trust a 200: an empty body, an HTML error page or JSON is not a song.
    const info = audio.length >= MIN_SONG_BYTES ? sniffAudio(audio) : null;
    if (!info) { this.failJob(job, audio.length === 0 ? 'empty_result' : 'invalid_audio', { bytes: audio.length }); return; }

    const songId = crypto.randomUUID();
    const blobKey = `songs/${songId}/${randomToken(8)}`;
    await blobs.put(blobKey, audio);
    try {
      tx(db, () => {
        const now = iso(clock.now());
        const voice = job['voice_id'] ? one(db, `SELECT display_name FROM voices WHERE id = ?`, String(job['voice_id'])) : undefined;
        const durationMs = result.durationMs ?? (info.kind === 'wav' ? wavDurationMs(audio) : null);
        run(db,
          `INSERT INTO songs (id, user_id, job_id, title, lyrics, language, settings_json, voice_id, voice_name, provider,
                              duration_ms, audio_blob_key, audio_mime, audio_bytes, audio_sha256, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          songId, String(job['user_id']), id, String(job['title']), String(job['lyrics']), String(job['language']),
          String(job['settings_json']), (job['voice_id'] as string | null) ?? null, voice ? String(voice['display_name']) : null,
          String(job['provider']), durationMs, blobKey, info.mime, audio.length, sha256Hex(audio), now);
        run(db, `UPDATE jobs SET status = 'completed', song_id = ?, completed_at = ?, lease_until = NULL, updated_at = ? WHERE id = ?`,
          songId, now, now, id);
        ledger.capture(db, clock, id);
        audit(db, clock, { userId: String(job['user_id']), kind: 'job.completed', subjectType: 'job', subjectId: id,
          detail: { songId, bytes: audio.length, mime: info.mime } });
      });
    } catch (err) {
      await blobs.delete(blobKey); // do not leave an orphan if the database write failed
      throw err;
    }
  }
}
