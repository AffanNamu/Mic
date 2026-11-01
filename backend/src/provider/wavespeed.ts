import type { MusicProvider, ProviderCapabilities, SongPoll, SongRequest } from './types.ts';
import { ProviderError } from './types.ts';
import {
  MAX_AUDIO_BYTES, MAX_JSON_BYTES, badShape, checkAudioUrl, networkError, pickString, readErrorJson, readLimited, retryAfterMs,
} from './http-util.ts';
import type { Json } from './http-util.ts';

/**
 * HeartMuLa (open-source music model, Apache 2.0) through WaveSpeedAI's hosted API.
 *
 * CONTRACT STATUS: WRITTEN FROM THE DOCUMENTATION (2026-10-31), THEN EXERCISED LIVE (2026-11-01): `GET /balance`, and the
 * submit, poll and download of three real songs matched everything assumed below (docs/PROVIDER_EVALUATION.md, "Live results").
 * Still unobserved: every failure path (402/1407/1200/5xx/failed/timeout), which are covered only by tests against a mock.
 * From the documentation (docs/PROVIDER_EVALUATION.md, "HeartMuLa via WaveSpeedAI"):
 *   - `POST {base}/api/v3/wavespeed-ai/heartmula/generate-music`, bearer auth, JSON `{lyrics, tags?, seed?}`;
 *     answers a prediction (`id`, `status`, ...), optionally wrapped as `{code, message, data}`.
 *   - `GET {base}/api/v3/predictions/{id}/result` until `status` is final: `completed` (read `outputs`) or
 *     `failed` / `cancelled` / `timeout` / `deleted`. `created`, `processing` and anything else: keep polling.
 *   - $0.10 per song. Documented lyric languages: English, Chinese, Japanese, Korean, Spanish. Hausa and Arabic
 *     are NOT documented, so they are offered only when the operator lists them as experimental.
 *   - Generated files are kept for about 7 days, so the worker downloads them straight away.
 *   - 1407 `insufficient_credits` is an out-of-credit error; the submit request must never be retried blindly,
 *     because a lost response may still have created (and billed) a task.
 * HeartMuLa 3B has NO reference-audio / voice conditioning, so this adapter cannot sing in a person's voice: it
 * reports `voiceConditioning: false` and refuses a request that names an enrolled voice rather than ignoring it.
 */
export interface WaveSpeedOptions {
  apiKey: string;
  baseUrl: string;
  songCostMicros: number;
  /** Extra hosts audio may be downloaded from (besides the API host). Empty = any public https host. */
  audioHosts: string[];
  /** Languages declared supported though not documented. For evaluation runs only. */
  experimentalLanguages: string[];
  fetchImpl?: typeof fetch;
}

const SUBMIT_PATH = '/api/v3/wavespeed-ai/heartmula/generate-music';
const FAILED = new Set(['failed', 'cancelled', 'canceled', 'timeout', 'deleted']);
const FUNDS_CODE = 1407; // "insufficient_credits"
const CONTENT_CODE = 1200; // "Content Moderation"
const SECTION_LINE = /^\s*\[[^\]\n]+\]\s*$/m;

export class WaveSpeedHeartMulaProvider implements MusicProvider {
  readonly name = 'heartmula';
  readonly configured = true;
  private readonly o: WaveSpeedOptions;
  private readonly fetchFn: typeof fetch;

  constructor(options: Partial<WaveSpeedOptions> & { apiKey: string; baseUrl: string }) {
    this.o = { songCostMicros: 100_000, audioHosts: [], experimentalLanguages: [], ...options };
    this.fetchFn = options.fetchImpl ?? fetch;
  }

  capabilities(): ProviderCapabilities {
    const documented = ['english']; // WaveSpeedAI documents English, Chinese, Japanese, Korean and Spanish; only English maps to DeenVoice.
    return {
      engineName: 'HeartMuLa',
      songTypes: ['full_song'],
      documentedLanguages: documented,
      languages: [...new Set([...documented, ...this.o.experimentalLanguages])],
      voiceConditioning: false,
      advancedOptionIds: [],
      voiceSampleSeconds: null,
      estimatedSongCostMicros: this.o.songCostMicros,
      estimatedEnrollCostMicros: null,
    };
  }

  // ------------------------------------------------------------------ voice

  async enrollVoice(): Promise<never> {
    throw new ProviderError('voice_not_supported',
      'HeartMuLa cannot sing in a recorded voice (it has no reference-audio support), so there is nothing to enrol.',
      { outcome: 'terminal' });
  }

  /** Nothing is ever stored at the provider for a voice, so there is nothing it could delete. */
  async deleteVoice(): Promise<'unsupported'> {
    return 'unsupported';
  }

  // ------------------------------------------------------------------- song

  async submitSong(req: SongRequest, signal: AbortSignal) {
    if (req.providerVoiceId) {
      // Silently singing in a stock voice when the person asked for their own would be a lie.
      throw new ProviderError('voice_not_supported',
        'HeartMuLa cannot sing in a recorded voice, so this song was not started.', { outcome: 'terminal' });
    }
    const payload: Json = { lyrics: withSectionTag(req.lyrics) };
    if (req.stylePrompt) payload['tags'] = req.stylePrompt;
    const task = await this.request('POST', SUBMIT_PATH, { json: payload }, signal, 'write');
    const id = pickString(task, ['id']);
    if (!id) throw badShape('submit response had no prediction id', 'unknown');
    return { providerTaskId: id };
  }

  async pollSong(taskId: string, signal: AbortSignal): Promise<SongPoll> {
    const task = await this.request('GET', `/api/v3/predictions/${encodeURIComponent(taskId)}/result`, {}, signal, 'read');
    const status = pickString(task, ['status'])?.toLowerCase();
    if (!status) throw badShape('result response had no status', 'not_started');
    if (FAILED.has(status)) {
      return { state: 'failed', code: pickString(task, ['code']) ?? status, message: pickString(task, ['error', 'message']) ?? status };
    }
    if (status !== 'completed') return { state: 'running' }; // created, processing, or anything new: ask again until the deadline
    const outputs = Array.isArray(task['outputs']) ? (task['outputs'] as unknown[]) : [];
    const first = outputs[0];
    const url = typeof first === 'string' && first ? first
      : first && typeof first === 'object' ? pickString(first as Json, ['url', 'audio_url']) : null;
    // The reply gives inference time, not the length of the song, so the duration stays unknown.
    return { state: 'succeeded', audioUrl: url, durationMs: null, costMicros: null };
  }

  async downloadAudio(audioUrl: string, signal: AbortSignal): Promise<Buffer> {
    const url = checkAudioUrl(audioUrl, this.o.baseUrl, this.o.audioHosts);
    let res: Response;
    try {
      res = await this.fetchFn(url, { signal, redirect: 'follow' });
    } catch (err) {
      throw networkError(err, 'read');
    }
    if (!res.ok) throw this.httpError(res.status, res.headers, 'read', null);
    const declared = Number(res.headers.get('content-length') ?? 0);
    if (declared > MAX_AUDIO_BYTES) throw new ProviderError('audio_too_large', 'Result is too large.', { outcome: 'terminal' });
    return readLimited(res, MAX_AUDIO_BYTES, 'terminal');
  }

  // ---------------------------------------------------------------- internals

  private async request(
    method: 'GET' | 'POST', path: string, init: { json?: Json }, signal: AbortSignal, kind: 'read' | 'write',
  ): Promise<Json> {
    const headers: Record<string, string> = { Authorization: `Bearer ${this.o.apiKey}`, Accept: 'application/json' };
    let body: string | undefined;
    if (init.json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(init.json); }

    let res: Response;
    try {
      res = await this.fetchFn(new URL(path, this.o.baseUrl), { method, headers, ...(body !== undefined ? { body } : {}), signal });
    } catch (err) {
      throw networkError(err, kind);
    }
    if (!res.ok) throw this.httpError(res.status, res.headers, kind, await readErrorJson(res));

    const raw = await readLimited(res, MAX_JSON_BYTES, kind === 'write' ? 'unknown' : 'terminal');
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw.toString('utf8'));
    } catch {
      // A 2xx with a body we cannot read: for a write, the task may already exist (and be billed).
      throw badShape('response was not valid JSON', kind === 'write' ? 'unknown' : 'not_started');
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw badShape('response was not a JSON object', kind === 'write' ? 'unknown' : 'not_started');
    }
    const outer = parsed as Json;
    const data = outer['data'];
    const task = data && typeof data === 'object' && !Array.isArray(data) ? (data as Json) : outer;
    // A reply can carry an error in its envelope while the HTTP status is 2xx: `{code: 1407, message: ...}`.
    const code = outer['code'];
    if (typeof code === 'number' && code !== 0 && code !== 200 && task === outer && typeof outer['status'] !== 'string') {
      throw this.codeError(code, 200, kind);
    }
    return task;
  }

  private codeError(code: number, httpStatus: number, kind: 'read' | 'write'): ProviderError {
    if (code === FUNDS_CODE) {
      return new ProviderError('provider_funds', 'The provider account has no balance.', { httpStatus, outcome: 'terminal', providerFunds: true });
    }
    if (code === CONTENT_CODE) {
      return new ProviderError('provider_content_rejected', 'The provider refused this lyrics text.', { httpStatus, outcome: 'terminal' });
    }
    if (code >= 5000) {
      return new ProviderError('provider_server_error', `The provider failed (${code}).`, { httpStatus, outcome: kind === 'write' ? 'unknown' : 'not_started' });
    }
    return new ProviderError('provider_rejected', `The provider rejected the request (${code}).`, { httpStatus, outcome: 'terminal' });
  }

  private httpError(status: number, headers: Headers, kind: 'read' | 'write', body: Json | null): ProviderError {
    const wait = retryAfterMs(headers);
    const base = { httpStatus: status, ...(wait !== undefined ? { retryAfterMs: wait } : {}) };
    const code = typeof body?.['code'] === 'number' ? (body['code'] as number) : null;
    if (code === FUNDS_CODE || status === 402) {
      return new ProviderError('provider_funds', 'The provider account has no balance.', { ...base, outcome: 'terminal', providerFunds: true });
    }
    if (status === 401 || status === 403) {
      return new ProviderError('provider_credentials', 'The provider rejected our credentials.', { ...base, outcome: 'terminal', credentialsInvalid: true });
    }
    if (status === 429) {
      // Rate limit: refused before any work started. (Unlike Mureka, running out of credit has its own code.)
      return new ProviderError('provider_rate_limited', 'The provider is rate limiting us.', { ...base, outcome: 'not_started' });
    }
    if (code === CONTENT_CODE) {
      return new ProviderError('provider_content_rejected', 'The provider refused this lyrics text.', { ...base, outcome: 'terminal' });
    }
    if (status >= 400 && status < 500) {
      return new ProviderError('provider_rejected', `The provider rejected the request (${status}).`, { ...base, outcome: 'terminal' });
    }
    // 5xx / 502 / 504: for a write we cannot know whether a task was created; for a read, asking again is harmless.
    return new ProviderError('provider_server_error', `The provider failed (${status}).`, { ...base, outcome: kind === 'write' ? 'unknown' : 'not_started' });
  }
}

/**
 * The model expects each paragraph to start with a section tag such as `[verse]`. Lyrics without any tag are
 * put under `[verse]`; lyrics that already carry tags are sent exactly as written.
 */
export function withSectionTag(lyrics: string): string {
  const text = lyrics.replace(/\r\n?/g, '\n').trim();
  return SECTION_LINE.test(text) ? text : `[verse]\n${text}`;
}
