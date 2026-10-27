import type { Deps } from './deps.ts';
import { all, one, run, tx } from './db.ts';
import { iso } from './clock.ts';
import { AppError, conflict, notFound } from './errors.ts';
import { randomToken, sha256Hex } from './crypto.ts';
import { sniffAudio, wavDurationMs } from './audio.ts';
import { audit } from './audit.ts';
import { consentStatement } from './consent.ts';
import type { Ownership } from './consent.ts';
import { withTimeout } from './timeout.ts';

const MAX_ACTIVE_VOICES = 3;
export const MAX_ENROLL_ATTEMPTS = 3;
const MIN_VOICE_BYTES = 2048;

export interface VoiceDto {
  id: string;
  displayName: string;
  ownership: Ownership;
  status: string;
  supportsSinging: boolean;
  failureCode: string | null;
  failureMessage: string | null;
  createdAt: string;
}

export function toVoiceDto(r: Record<string, unknown>): VoiceDto {
  return {
    id: String(r['id']),
    displayName: String(r['display_name']),
    ownership: r['ownership'] as Ownership,
    status: String(r['status']),
    supportsSinging: Number(r['supports_singing']) === 1,
    failureCode: (r['failure_code'] as string | null) ?? null,
    failureMessage: (r['failure_message'] as string | null) ?? null,
    createdAt: String(r['created_at']),
  };
}

function ownedVoice(deps: Deps, userId: string, voiceId: string) {
  const row = one(deps.db, `SELECT * FROM voices WHERE id = ? AND user_id = ? AND status != 'deleted'`, voiceId, userId);
  if (!row) throw notFound('Voice');
  return row;
}

export function listVoices(deps: Deps, userId: string): VoiceDto[] {
  return all(deps.db, `SELECT * FROM voices WHERE user_id = ? AND status != 'deleted' ORDER BY created_at`, userId)
    .map(toVoiceDto);
}

export function getVoice(deps: Deps, userId: string, voiceId: string): VoiceDto {
  return toVoiceDto(ownedVoice(deps, userId, voiceId));
}

export interface CreateVoiceInput {
  displayName: string;
  ownership: Ownership;
  authorizedBy: string | null;
  consent: { accepted: boolean; version: string };
}

/** Records consent and creates the voice. No audio is accepted until this has happened. */
export function createVoice(
  deps: Deps, userId: string, input: CreateVoiceInput, meta: { ip: string | null; userAgent: string | null },
): VoiceDto {
  if (!deps.provider.configured) {
    throw new AppError(503, 'provider_not_configured', 'Voice enrollment is not available: no music provider is configured.');
  }
  if (!input.consent.accepted) {
    throw new AppError(400, 'consent_required', 'You must accept the consent statement to add a voice.');
  }
  const statement = consentStatement(input.consent.version, input.ownership);
  if (!statement) throw new AppError(400, 'unknown_consent_version', 'That consent statement is out of date. Reload and try again.');
  const name = input.displayName.trim();
  if (name.length < 1 || name.length > 60) throw new AppError(400, 'invalid_name', 'Give the voice a name up to 60 characters.');
  const authorizedBy = input.authorizedBy?.trim() || null;
  if (input.ownership === 'authorized' && !authorizedBy) {
    throw new AppError(400, 'authorized_by_required', 'Say whose voice this is and that they gave permission.');
  }

  return tx(deps.db, () => {
    const active = one(deps.db,
      `SELECT COUNT(*) AS n FROM voices WHERE user_id = ? AND status NOT IN ('deleted', 'revoked')`, userId);
    if (Number(active?.['n'] ?? 0) >= MAX_ACTIVE_VOICES) {
      throw conflict('voice_limit', `You can have up to ${MAX_ACTIVE_VOICES} voices. Delete one first.`);
    }
    const now = iso(deps.clock.now());
    const id = crypto.randomUUID();
    run(deps.db,
      `INSERT INTO voices (id, user_id, display_name, ownership, authorized_by, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, 'awaiting_audio', ?, ?)`,
      id, userId, name, input.ownership, authorizedBy, now, now);
    run(deps.db,
      `INSERT INTO consents (id, voice_id, user_id, ownership, authorized_by, statement_version, statement_sha256, accepted_at, ip, user_agent)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      crypto.randomUUID(), id, userId, input.ownership, authorizedBy, input.consent.version, statement.sha256, now,
      meta.ip, meta.userAgent);
    audit(deps.db, deps.clock, { userId, kind: 'voice.consent_recorded', subjectType: 'voice', subjectId: id,
      detail: { ownership: input.ownership, version: input.consent.version, statementSha256: statement.sha256 } });
    return toVoiceDto(ownedVoice(deps, userId, id));
  });
}

export async function uploadVoiceAudio(deps: Deps, userId: string, voiceId: string, body: Buffer): Promise<VoiceDto> {
  const voice = ownedVoice(deps, userId, voiceId);
  if (!deps.provider.configured) {
    throw new AppError(503, 'provider_not_configured', 'Voice enrollment is not available: no music provider is configured.');
  }
  const status = String(voice['status']);
  if (status !== 'awaiting_audio' && status !== 'failed') {
    throw conflict('voice_not_accepting_audio', 'This voice already has a recording.');
  }
  const consent = one(deps.db, `SELECT 1 AS x FROM consents WHERE voice_id = ? AND revoked_at IS NULL`, voiceId);
  if (!consent) throw new AppError(403, 'consent_required', 'There is no consent on record for this voice.');

  if (body.length < MIN_VOICE_BYTES) throw new AppError(400, 'audio_too_small', 'That recording is empty or too short.');
  if (body.length > deps.config.maxVoiceBytes) {
    throw new AppError(413, 'audio_too_large', `Recordings can be up to ${Math.floor(deps.config.maxVoiceBytes / 1048576)} MB.`);
  }
  const info = sniffAudio(body);
  if (!info) throw new AppError(415, 'not_audio', 'That file is not a supported audio recording.');
  const range = deps.provider.capabilities().voiceSampleSeconds;
  const wavMs = info.kind === 'wav' ? wavDurationMs(body) : null;
  if (range && wavMs !== null && (wavMs < range.min * 1000 || wavMs > range.max * 1000)) {
    throw new AppError(422, 'sample_length',
      `Provide a clear, solo recording between ${range.min} and ${range.max} seconds (yours is ${(wavMs / 1000).toFixed(1)} s).`);
  }

  const key = `voices/${voiceId}/${randomToken(12)}`;
  await deps.blobs.put(key, body);
  const previous = voice['audio_blob_key'] as string | null;
  tx(deps.db, () => {
    run(deps.db,
      `UPDATE voices SET status = 'enrolling', audio_blob_key = ?, audio_sha256 = ?, audio_mime = ?, audio_bytes = ?,
              enroll_attempts = 0, lease_until = NULL, failure_code = NULL, failure_message = NULL, updated_at = ?
        WHERE id = ?`,
      key, sha256Hex(body), info.mime, body.length, iso(deps.clock.now()), voiceId);
    audit(deps.db, deps.clock, { userId, kind: 'voice.audio_uploaded', subjectType: 'voice', subjectId: voiceId,
      detail: { bytes: body.length, mime: info.mime } });
  });
  if (previous) await deps.blobs.delete(previous);
  return getVoice(deps, userId, voiceId);
}

export function retryEnrollment(deps: Deps, userId: string, voiceId: string): VoiceDto {
  const voice = ownedVoice(deps, userId, voiceId);
  if (voice['status'] !== 'failed' || !voice['audio_blob_key']) {
    throw conflict('voice_not_retryable', 'Only a failed enrollment with a recording can be retried.');
  }
  // Each attempt can be billed by the provider, so the number is capped.
  if (Number(voice['enroll_attempts']) >= MAX_ENROLL_ATTEMPTS) {
    throw conflict('enroll_attempts_exhausted', 'Enrollment failed too many times. Upload a new recording.');
  }
  run(deps.db, `UPDATE voices SET status = 'enrolling', lease_until = NULL, failure_code = NULL, failure_message = NULL, updated_at = ? WHERE id = ?`,
    iso(deps.clock.now()), voiceId);
  return getVoice(deps, userId, voiceId);
}

/** Stops new songs from using the voice. Does not delete anything. */
export function revokeVoice(deps: Deps, userId: string, voiceId: string): VoiceDto {
  ownedVoice(deps, userId, voiceId);
  tx(deps.db, () => {
    const now = iso(deps.clock.now());
    run(deps.db, `UPDATE voices SET status = 'revoked', updated_at = ? WHERE id = ?`, now, voiceId);
    run(deps.db, `UPDATE consents SET revoked_at = ? WHERE voice_id = ? AND revoked_at IS NULL`, now, voiceId);
    audit(deps.db, deps.clock, { userId, kind: 'voice.revoked', subjectType: 'voice', subjectId: voiceId });
  });
  return getVoice(deps, userId, voiceId);
}

export interface DeleteVoiceResult {
  voiceId: string;
  localAudioDeleted: boolean;
  providerDeletion: 'not_applicable' | 'requested' | 'deleted' | 'unsupported' | 'failed';
  songsDeleted: number;
  /** Plain-language statement of what was and was not removed. */
  disclosure: string;
}

/**
 * Deletes the voice. Local data is always removed. Provider-side deletion is
 * attempted where the provider supports it and reported truthfully when it does
 * not. A tombstone row and the consent record are kept for accountability.
 */
export async function deleteVoice(
  deps: Deps, userId: string, voiceId: string, opts: { deleteSongs: boolean },
): Promise<DeleteVoiceResult> {
  const voice = ownedVoice(deps, userId, voiceId);
  const active = one(deps.db,
    `SELECT COUNT(*) AS n FROM jobs WHERE voice_id = ? AND status IN ('queued','submitting','processing','downloading')`, voiceId);
  if (Number(active?.['n'] ?? 0) > 0) {
    throw conflict('voice_in_use', 'A song is still being made with this voice. Wait for it to finish or cancel it.');
  }
  if (voice['status'] === 'enrolling' && voice['lease_until'] && String(voice['lease_until']) > iso(deps.clock.now())) {
    throw conflict('voice_in_use', 'This voice is being enrolled right now. Try again in a minute.');
  }

  const blobKey = voice['audio_blob_key'] as string | null;
  const localAudioDeleted = blobKey ? await deps.blobs.delete(blobKey) : false;

  let providerDeletion: DeleteVoiceResult['providerDeletion'] = 'not_applicable';
  const providerVoiceId = voice['provider_voice_id'] as string | null;
  if (providerVoiceId) {
    try {
      providerDeletion = await withTimeout(30_000, (signal) => deps.provider.deleteVoice(providerVoiceId, signal));
    } catch (err) {
      providerDeletion = 'failed';
      deps.log.warn({ voiceId, err: String(err) }, 'provider voice deletion failed');
    }
  }

  const songRows = opts.deleteSongs
    ? all(deps.db, `SELECT id, audio_blob_key FROM songs WHERE voice_id = ? AND deleted_at IS NULL`, voiceId)
    : [];
  for (const s of songRows) await deps.blobs.delete(String(s['audio_blob_key']));

  tx(deps.db, () => {
    const now = iso(deps.clock.now());
    for (const s of songRows) {
      run(deps.db, `UPDATE songs SET deleted_at = ?, title = '', lyrics = '', voice_name = NULL WHERE id = ?`, now, String(s['id']));
    }
    // Jobs that never started are cancelled; their holds are released.
    run(deps.db,
      `UPDATE voices SET status = 'deleted', display_name = 'Deleted voice', audio_blob_key = NULL, audio_sha256 = NULL,
              audio_bytes = NULL, supports_singing = 0, provider_deletion = ?, deleted_at = ?, updated_at = ? WHERE id = ?`,
      providerDeletion, now, now, voiceId);
    run(deps.db, `UPDATE consents SET revoked_at = COALESCE(revoked_at, ?) WHERE voice_id = ?`, now, voiceId);
    audit(deps.db, deps.clock, { userId, kind: 'voice.deleted', subjectType: 'voice', subjectId: voiceId,
      detail: { localAudioDeleted, providerDeletion, songsDeleted: songRows.length } });
  });

  const disclosure =
    providerDeletion === 'deleted' ? 'The voice and its recording were deleted here and at the music provider.'
    : providerDeletion === 'requested' ? 'The voice and recording were deleted here. Deletion at the music provider has been requested but is not confirmed.'
    : providerDeletion === 'not_applicable' ? 'The voice and recording were deleted. It had not been sent to the music provider.'
    : 'The voice and recording were deleted here. The music provider could not delete its copy automatically; it holds it under its own terms until removal is requested from the provider.';
  return { voiceId, localAudioDeleted, providerDeletion, songsDeleted: songRows.length, disclosure };
}

