import type { Deps } from './deps.ts';
import { all, one, run, tx } from './db.ts';
import { iso } from './clock.ts';
import { AppError, conflict } from './errors.ts';
import { verifyPassword } from './crypto.ts';
import { audit } from './audit.ts';
import { deleteVoice } from './voices.ts';
import type { DeleteVoiceResult } from './voices.ts';
import { deleteSong } from './songs.ts';

type ProviderDeletion = DeleteVoiceResult['providerDeletion'];

export interface DeleteAccountResult {
  deleted: true;
  voicesDeleted: number;
  songsDeleted: number;
  /** The worst outcome across the person's voices at the music provider. */
  providerDeletion: ProviderDeletion;
  /** Plain-language statement of what was removed, and what the provider may still hold. */
  disclosure: string;
  /** What the service keeps after deletion, and why. */
  kept: string[];
}

// Worst first: if any voice's copy could not be removed at the provider, that is what is reported.
const SEVERITY: ProviderDeletion[] = ['failed', 'unsupported', 'requested', 'deleted', 'not_applicable'];

const KEPT = [
  'A record that credits were granted and used. It has no name, email or recording, only an anonymous id.',
  'A record that consent was given for each voice (the wording version, its hash and the time). It no longer has your IP address, device details or the speaker’s name.',
  'A log of account events under the same anonymous id. It contains no personal details.',
];

/**
 * Deletes a person's account: their recordings (here and, where the provider allows, there), their songs
 * and lyrics, their sessions, their email and their password. The user row is kept as an anonymous
 * tombstone because the credit ledger and audit log refer to its id.
 *
 * Re-authenticates with the password, so a stolen session token alone cannot do this. It refuses while a
 * song is being made, because a job cannot be cut off from the provider once it has started. Every step is
 * safe to repeat, so an interrupted deletion can be run again.
 */
export async function deleteAccount(deps: Deps, userId: string, password: string): Promise<DeleteAccountResult> {
  const user = one(deps.db, 'SELECT id, password_hash, deleted_at FROM users WHERE id = ?', userId);
  if (!user || user['deleted_at']) throw new AppError(404, 'not_found', 'Account not found.');
  // 403, not 401: the app treats 401 as "your session ended" and signs the person out.
  if (!(await verifyPassword(password, String(user['password_hash'])))) {
    audit(deps.db, deps.clock, { userId, kind: 'account.delete_denied', subjectType: 'user', subjectId: userId });
    throw new AppError(403, 'password_incorrect', 'That password isn’t right.');
  }

  const active = one(deps.db,
    `SELECT COUNT(*) AS n FROM jobs WHERE user_id = ? AND status IN ('queued','submitting','processing','downloading')`, userId);
  if (Number(active?.['n'] ?? 0) > 0) {
    throw conflict('account_busy', 'A song is still being made. Wait for it to finish, or cancel it, then delete your account.');
  }

  const voiceIds = all(deps.db, `SELECT id FROM voices WHERE user_id = ? AND status != 'deleted'`, userId).map((r) => String(r['id']));
  let worst: ProviderDeletion = 'not_applicable';
  for (const voiceId of voiceIds) {
    const r = await deleteVoice(deps, userId, voiceId, { deleteSongs: false });
    if (SEVERITY.indexOf(r.providerDeletion) < SEVERITY.indexOf(worst)) worst = r.providerDeletion;
  }

  const songIds = all(deps.db, `SELECT id FROM songs WHERE user_id = ? AND deleted_at IS NULL`, userId).map((r) => String(r['id']));
  for (const songId of songIds) await deleteSong(deps, userId, songId);

  const now = iso(deps.clock.now());
  tx(deps.db, () => {
    // Words the person wrote, and what the provider returned for them.
    run(deps.db, `UPDATE jobs SET title = '', lyrics = '', settings_json = '{}', result_json = NULL WHERE user_id = ?`, userId);
    run(deps.db, `UPDATE songs SET title = '', lyrics = '', settings_json = '{}', voice_name = NULL WHERE user_id = ?`, userId);
    // The speaker's name, and where and on what the consent was given.
    run(deps.db, `UPDATE voices SET authorized_by = NULL, display_name = 'Deleted voice' WHERE user_id = ?`, userId);
    run(deps.db, `UPDATE consents SET authorized_by = NULL, ip = NULL, user_agent = NULL WHERE user_id = ?`, userId);
    run(deps.db, `DELETE FROM sessions WHERE user_id = ?`, userId);
    run(deps.db,
      `UPDATE users SET email = ?, password_hash = '!', disabled_at = ?, deleted_at = ? WHERE id = ?`,
      `deleted-${userId}@deleted.invalid`, now, now, userId);
    audit(deps.db, deps.clock, { userId, kind: 'account.deleted', subjectType: 'user', subjectId: userId,
      detail: { voices: voiceIds.length, songs: songIds.length, providerDeletion: worst } });
  });

  const provider =
    worst === 'not_applicable' ? ''
    : worst === 'deleted' ? ' Your voice recordings were also deleted at the music provider.'
    : worst === 'requested' ? ' Deletion of your voice recordings at the music provider has been requested but is not confirmed.'
    : ' The music provider could not delete its copy of your voice recordings automatically. It holds them under its own terms until removal is requested from the provider.';
  return {
    deleted: true,
    voicesDeleted: voiceIds.length,
    songsDeleted: songIds.length,
    providerDeletion: worst,
    disclosure: `Your account, recordings, songs and lyrics were deleted from DeenVoice.${provider}`,
    kept: KEPT,
  };
}
