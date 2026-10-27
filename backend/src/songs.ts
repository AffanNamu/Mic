import type { Deps } from './deps.ts';
import { all, one, run } from './db.ts';
import { addMs, iso } from './clock.ts';
import { AppError, notFound } from './errors.ts';
import { hmacHex, safeEqual } from './crypto.ts';
import { audit } from './audit.ts';

export interface SongDto {
  id: string;
  title: string;
  lyrics: string;
  language: string;
  voiceName: string | null;
  provider: string;
  durationMs: number | null;
  audioMime: string;
  audioBytes: number;
  createdAt: string;
}

const toSongDto = (r: Record<string, unknown>): SongDto => ({
  id: String(r['id']), title: String(r['title']), lyrics: String(r['lyrics']), language: String(r['language']),
  voiceName: (r['voice_name'] as string | null) ?? null, provider: String(r['provider']),
  durationMs: r['duration_ms'] === null ? null : Number(r['duration_ms']),
  audioMime: String(r['audio_mime']), audioBytes: Number(r['audio_bytes']), createdAt: String(r['created_at']),
});

function ownedSong(deps: Deps, userId: string, songId: string) {
  const row = one(deps.db, `SELECT * FROM songs WHERE id = ? AND user_id = ? AND deleted_at IS NULL`, songId, userId);
  if (!row) throw notFound('Song');
  return row;
}

export const listSongs = (deps: Deps, userId: string): SongDto[] =>
  all(deps.db, `SELECT * FROM songs WHERE user_id = ? AND deleted_at IS NULL ORDER BY created_at DESC`, userId).map(toSongDto);

export const getSong = (deps: Deps, userId: string, songId: string): SongDto => toSongDto(ownedSong(deps, userId, songId));

export function renameSong(deps: Deps, userId: string, songId: string, titleRaw: string): SongDto {
  const title = titleRaw.trim();
  if (title.length < 1 || title.length > 80) throw new AppError(400, 'invalid_title', 'Give your song a title up to 80 characters.');
  ownedSong(deps, userId, songId);
  run(deps.db, `UPDATE songs SET title = ? WHERE id = ?`, title, songId);
  return getSong(deps, userId, songId);
}

export async function deleteSong(deps: Deps, userId: string, songId: string): Promise<void> {
  const song = ownedSong(deps, userId, songId);
  await deps.blobs.delete(String(song['audio_blob_key']));
  run(deps.db, `UPDATE songs SET deleted_at = ?, title = '', lyrics = '', voice_name = NULL WHERE id = ?`, iso(deps.clock.now()), songId);
  audit(deps.db, deps.clock, { userId, kind: 'song.deleted', subjectType: 'song', subjectId: songId });
}

const sign = (deps: Deps, songId: string, userId: string, exp: number) =>
  hmacHex(deps.config.mediaKey, `song:${songId}:${userId}:${exp}`);

/** A short-lived capability URL for playing a song in an audio element, which cannot send auth headers. */
export function signAudioUrl(deps: Deps, userId: string, songId: string, ttlMs = 5 * 60_000) {
  ownedSong(deps, userId, songId);
  const expiresAt = addMs(deps.clock.now(), ttlMs);
  const exp = Math.floor(expiresAt.getTime() / 1000);
  return { path: `/media/songs/${songId}?exp=${exp}&sig=${sign(deps, songId, userId, exp)}`, expiresAt: iso(expiresAt) };
}

export async function readSongAudio(deps: Deps, songId: string, exp: number, sig: string) {
  const row = one(deps.db, `SELECT * FROM songs WHERE id = ? AND deleted_at IS NULL`, songId);
  // Same answer for "no such song" and "bad signature": do not reveal which songs exist.
  const bad = new AppError(403, 'invalid_link', 'This link is invalid or has expired.');
  if (!row || !Number.isFinite(exp) || exp * 1000 < deps.clock.now().getTime()) throw bad;
  if (!safeEqual(sig, sign(deps, songId, String(row['user_id']), exp))) throw bad;
  return { data: await deps.blobs.get(String(row['audio_blob_key'])), mime: String(row['audio_mime']) };
}
