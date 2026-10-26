import type { Deps } from './deps.ts';
import { all, one, run, tx } from './db.ts';
import { addMs, iso } from './clock.ts';
import { AppError, notFound } from './errors.ts';
import { sha256Hex } from './crypto.ts';
import { audit } from './audit.ts';
import * as ledger from './ledger.ts';
import { STYLE_KEYS } from './style.ts';

const USES_VOICE = new Set(['full_song', 'vocal_only', 'nasheed_style']);
const IDEMPOTENCY_KEY = /^[A-Za-z0-9_-]{8,128}$/;

export interface CreateJobInput {
  idempotencyKey: string;
  title: string;
  lyrics: string;
  language: string;
  songType: string;
  voiceId: string | null;
  style: Record<string, string>;
  advanced: Record<string, string>;
}

export interface JobDto {
  id: string;
  status: string;
  /** Short label for progress UI. */
  stage: string;
  title: string;
  credits: number;
  failureCode: string | null;
  failureMessage: string | null;
  songId: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}

const STAGE: Record<string, string> = {
  queued: 'Queued', submitting: 'Starting', processing: 'Generating your song',
  downloading: 'Finishing up', completed: 'Ready', failed: 'Failed', cancelled: 'Cancelled',
};

export function toJobDto(r: Record<string, unknown>): JobDto {
  const status = String(r['status']);
  return {
    id: String(r['id']), status, stage: STAGE[status] ?? status,
    title: String(r['title']), credits: Number(r['credits']),
    failureCode: (r['failure_code'] as string | null) ?? null,
    failureMessage: (r['failure_message'] as string | null) ?? null,
    songId: (r['song_id'] as string | null) ?? null,
    createdAt: String(r['created_at']), updatedAt: String(r['updated_at']),
    completedAt: (r['completed_at'] as string | null) ?? null,
  };
}

/** What a song costs the user, and what the provider is expected to charge us. */
export function quote(deps: Deps) {
  const caps = deps.provider.capabilities();
  return {
    credits: deps.config.credits.perSong,
    estimatedProviderCostMicros: caps.estimatedSongCostMicros,
  };
}

function normalize(deps: Deps, raw: CreateJobInput) {
  const caps = deps.provider.capabilities();
  if (!IDEMPOTENCY_KEY.test(raw.idempotencyKey)) {
    throw new AppError(400, 'invalid_idempotency_key', 'idempotencyKey must be 8-128 letters, digits, "-" or "_".');
  }
  const title = raw.title.trim();
  if (title.length < 1 || title.length > 80) throw new AppError(400, 'invalid_title', 'Give your song a title up to 80 characters.');
  const lyrics = raw.lyrics.trim();
  if (lyrics.length < 1) throw new AppError(400, 'lyrics_required', 'Add lyrics.');
  if (lyrics.length > deps.config.maxLyricsChars) {
    throw new AppError(400, 'lyrics_too_long', `Lyrics are limited to ${deps.config.maxLyricsChars} characters.`);
  }
  if (!caps.songTypes.includes(raw.songType)) {
    throw new AppError(422, 'unsupported_song_type', `${caps.engineName ?? 'The music service'} can't generate "${raw.songType}" songs.`);
  }
  if (!caps.languages.includes(raw.language)) {
    throw new AppError(422, 'unsupported_language',
      `${caps.engineName ?? 'The music service'} does not support ${raw.language} lyrics.`, { supported: caps.languages });
  }
  for (const key of Object.keys(raw.advanced)) {
    if (!caps.advancedOptionIds.includes(key)) {
      throw new AppError(422, 'unsupported_option', `The setting "${key}" is not supported by ${caps.engineName ?? 'the music service'}.`);
    }
  }
  const style: Record<string, string> = {};
  for (const k of STYLE_KEYS) style[k] = String(raw.style[k] ?? '');
  return {
    key: raw.idempotencyKey, title, lyrics, language: raw.language, songType: raw.songType,
    voiceId: raw.voiceId, style, advanced: raw.advanced,
  };
}

export function createJob(deps: Deps, userId: string, raw: CreateJobInput): { job: JobDto; deduplicated: boolean } {
  if (!deps.provider.configured) {
    throw new AppError(503, 'provider_not_configured', 'Song generation is not available: no music provider is configured.');
  }
  if (deps.health.isBlocked(deps.clock)) {
    throw new AppError(503, 'provider_unavailable', 'Song generation is temporarily unavailable. Please try again later.');
  }
  const n = normalize(deps, raw);
  const hash = sha256Hex(JSON.stringify([n.title, n.lyrics, n.language, n.songType, n.voiceId, n.style, n.advanced]));

  return tx(deps.db, () => {
    const existing = one(deps.db, `SELECT * FROM jobs WHERE user_id = ? AND idempotency_key = ?`, userId, n.key);
    if (existing) {
      if (String(existing['request_hash']) !== hash) {
        throw new AppError(422, 'idempotency_key_reuse', 'That idempotency key was already used for a different request.');
      }
      return { job: toJobDto(existing), deduplicated: true };
    }

    const caps = deps.provider.capabilities();
    if (USES_VOICE.has(n.songType)) {
      if (!caps.voiceConditioning) {
        throw new AppError(422, 'voice_conditioning_unsupported', `${caps.engineName} can't sing in a saved voice.`);
      }
      if (!n.voiceId) throw new AppError(400, 'voice_required', 'Choose a voice.');
      const voice = one(deps.db, `SELECT * FROM voices WHERE id = ? AND user_id = ?`, n.voiceId, userId);
      if (!voice || voice['status'] === 'deleted') throw notFound('Voice');
      if (voice['status'] !== 'ready' || Number(voice['supports_singing']) !== 1) {
        throw new AppError(409, 'voice_not_ready', 'That voice is not ready to sing yet.');
      }
      const consent = one(deps.db, `SELECT 1 AS x FROM consents WHERE voice_id = ? AND revoked_at IS NULL`, n.voiceId);
      if (!consent) throw new AppError(409, 'voice_consent_revoked', 'Permission for that voice was revoked.');
    }

    const id = crypto.randomUUID();
    const now = deps.clock.now();
    const credits = deps.config.credits.perSong;
    run(deps.db,
      `INSERT INTO jobs (id, user_id, idempotency_key, request_hash, status, voice_id, title, lyrics, language,
                         settings_json, credits, provider, next_run_at, deadline_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'queued', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      id, userId, n.key, hash, n.voiceId, n.title, n.lyrics, n.language,
      JSON.stringify({ songType: n.songType, style: n.style, advanced: n.advanced }), credits,
      deps.provider.name, iso(now), iso(addMs(now, deps.config.jobDeadlineMs)), iso(now), iso(now));
    ledger.reserve(deps.db, deps.clock, userId, id, credits); // throws 402; rolls the job back with it
    audit(deps.db, deps.clock, { userId, kind: 'job.created', subjectType: 'job', subjectId: id,
      detail: { credits, language: n.language, songType: n.songType, hasVoice: Boolean(n.voiceId) } });
    return { job: toJobDto(one(deps.db, `SELECT * FROM jobs WHERE id = ?`, id)!), deduplicated: false };
  });
}

export function getJob(deps: Deps, userId: string, jobId: string): JobDto {
  const row = one(deps.db, `SELECT * FROM jobs WHERE id = ? AND user_id = ?`, jobId, userId);
  if (!row) throw notFound('Job');
  return toJobDto(row);
}

export function listJobs(deps: Deps, userId: string, limit = 30): JobDto[] {
  return all(deps.db, `SELECT * FROM jobs WHERE user_id = ? ORDER BY created_at DESC LIMIT ?`, userId, limit).map(toJobDto);
}

/** Only a job the provider has not been given can be cancelled. */
export function cancelJob(deps: Deps, userId: string, jobId: string): JobDto {
  return tx(deps.db, () => {
    const row = one(deps.db, `SELECT * FROM jobs WHERE id = ? AND user_id = ?`, jobId, userId);
    if (!row) throw notFound('Job');
    if (row['status'] !== 'queued') {
      throw new AppError(409, 'job_not_cancellable', 'This song has already started and can no longer be cancelled.');
    }
    const now = iso(deps.clock.now());
    run(deps.db, `UPDATE jobs SET status = 'cancelled', completed_at = ?, updated_at = ?, lease_until = NULL WHERE id = ?`, now, now, jobId);
    ledger.release(deps.db, deps.clock, jobId, 'Cancelled by user');
    audit(deps.db, deps.clock, { userId, kind: 'job.cancelled', subjectType: 'job', subjectId: jobId });
    return toJobDto(one(deps.db, `SELECT * FROM jobs WHERE id = ?`, jobId)!);
  });
}
