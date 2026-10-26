import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeEnv, register, auth, grantCredits, submitJob, readyVoice, ADMIN_TOKEN, MEDIA_KEY,
} from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { wav } from './support/wav.ts';
import { all, one } from '../src/db.ts';
import { sha256Hex } from '../src/crypto.ts';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { metrics } from '../src/metrics.ts';
import { providerError } from './support/scripted-provider.ts';
import { UnconfiguredProvider } from '../src/provider/unconfigured.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

async function withSong(title = 'My song') {
  env = makeEnv();
  const u = await register(env);
  await grantCredits(env, u.email, 5);
  const voiceId = await readyVoice(env, u.token);
  const audio = wav(5, { hz: 330 });
  env.provider.onDownload = async () => audio;
  await submitJob(env, u.token, { voiceId, title });
  await env.drain();
  const songs = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs as Array<{ id: string }>;
  return { u, voiceId, audio, songId: songs[0]!.id };
}
const signed = async (token: string, songId: string) =>
  (await env.app.inject({ method: 'POST', url: `/v1/songs/${songId}/audio-url`, headers: auth(token) })).json() as { path: string; expiresAt: string };

describe('song library', () => {
  it('lists, opens, renames and deletes songs; deleting removes the audio', async () => {
    const { u, songId } = await withSong('First title');
    const list = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs;
    assert.equal(list.length, 1);
    assert.equal(list[0].title, 'First title');
    assert.equal(list[0].voiceName, 'Test participant');
    assert.equal(list[0].provider, 'test-double');
    assert.ok(!('audioBlobKey' in list[0]) && !JSON.stringify(list[0]).includes('songs/'), 'storage keys never leave the server');

    const renamed = await env.app.inject({ method: 'PATCH', url: `/v1/songs/${songId}`, headers: auth(u.token), payload: { title: 'Renamed' } });
    assert.equal(renamed.json().song.title, 'Renamed');
    assert.equal((await env.app.inject({ method: 'PATCH', url: `/v1/songs/${songId}`, headers: auth(u.token), payload: { title: ' ' } })).statusCode, 400);

    const key = String(one(env.db, 'SELECT audio_blob_key FROM songs WHERE id = ?', songId)!['audio_blob_key']);
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/songs/${songId}`, headers: auth(u.token) })).statusCode, 204);
    await assert.rejects(env.deps.blobs.get(key));
    assert.deepEqual((await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs, []);
    assert.equal((await env.app.inject({ method: 'GET', url: `/v1/songs/${songId}`, headers: auth(u.token) })).statusCode, 404);
  });
});

describe('secure audio retrieval', () => {
  it('serves the exact bytes through a signed link, with no-store caching and the right type', async () => {
    const { u, audio, songId } = await withSong();
    const { path } = await signed(u.token, songId);
    const res = await env.app.inject({ method: 'GET', url: path });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.rawPayload, audio);
    assert.equal(res.headers['content-type'], 'audio/wav');
    assert.equal(res.headers['cache-control'], 'private, no-store');
    assert.equal(res.headers['accept-ranges'], 'bytes');
    assert.equal(res.headers['x-content-type-options'], 'nosniff');
  });

  it('supports byte ranges (needed by browser and mobile players)', async () => {
    const { u, audio, songId } = await withSong();
    const { path } = await signed(u.token, songId);
    const get = (range: string) => env.app.inject({ method: 'GET', url: path, headers: { range } });
    const first = await get('bytes=0-99');
    assert.equal(first.statusCode, 206);
    assert.equal(first.headers['content-range'], `bytes 0-99/${audio.length}`);
    assert.deepEqual(first.rawPayload, audio.subarray(0, 100));
    const open = await get('bytes=1000-');
    assert.deepEqual(open.rawPayload, audio.subarray(1000));
    const suffix = await get('bytes=-50');
    assert.deepEqual(suffix.rawPayload, audio.subarray(audio.length - 50));
    assert.equal((await get(`bytes=${audio.length + 10}-`)).statusCode, 416);
    assert.equal((await get('bytes=abc')).statusCode, 416);
    assert.equal((await get('bytes=-')).statusCode, 416);
  });

  it('rejects tampered signatures, tampered expiry, expired links and made-up songs identically', async () => {
    const { u, songId } = await withSong();
    const { path } = await signed(u.token, songId);
    const url = new URL(path, 'http://x');
    const bad: string[] = [];
    const sig = url.searchParams.get('sig')!;
    const exp = Number(url.searchParams.get('exp'));
    bad.push(`/media/songs/${songId}?exp=${exp}&sig=${sig.replace(/.$/, sig.endsWith('0') ? '1' : '0')}`);
    bad.push(`/media/songs/${songId}?exp=${exp + 3600}&sig=${sig}`);
    bad.push(`/media/songs/${songId}?exp=${exp}`);
    bad.push(`/media/songs/${songId}`);
    bad.push(`/media/songs/not-a-song?exp=${exp}&sig=${sig}`);
    for (const p of bad) {
      const res = await env.app.inject({ method: 'GET', url: p });
      assert.equal(res.statusCode, 403, p);
      assert.equal(res.json().error.code, 'invalid_link');
    }
    env.clock.advance(5 * 60_000 + 2000);
    const expired = await env.app.inject({ method: 'GET', url: path });
    assert.equal(expired.statusCode, 403);
  });

  it('a link for one song does not open another, and a deleted song\'s link stops working', async () => {
    const { u, voiceId, songId } = await withSong();
    await submitJob(env, u.token, { voiceId, title: 'Second' });
    await env.drain();
    const songs = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs as Array<{ id: string }>;
    const other = songs.find((s) => s.id !== songId)!.id;
    const { path } = await signed(u.token, songId);
    const swapped = path.replace(songId, other);
    assert.equal((await env.app.inject({ method: 'GET', url: swapped })).statusCode, 403);

    assert.equal((await env.app.inject({ method: 'GET', url: path })).statusCode, 200);
    await env.app.inject({ method: 'DELETE', url: `/v1/songs/${songId}`, headers: auth(u.token) });
    assert.equal((await env.app.inject({ method: 'GET', url: path })).statusCode, 403);
  });

  it('refuses to sign a link for someone else\'s song', async () => {
    const { songId } = await withSong();
    const other = await register(env, 'other@example.com');
    const res = await env.app.inject({ method: 'POST', url: `/v1/songs/${songId}/audio-url`, headers: auth(other.token) });
    assert.equal(res.statusCode, 404);
  });

  it('a corrupted stored file is an error, never garbage audio', async () => {
    const { u, songId } = await withSong();
    const { path } = await signed(u.token, songId);
    const key = String(one(env.db, 'SELECT audio_blob_key FROM songs WHERE id = ?', songId)!['audio_blob_key']);
    const h = sha256Hex(key);
    const file = join(env.blobDir, h.slice(0, 2), h);
    const bytes = readFileSync(file);
    bytes[bytes.length - 1] = bytes[bytes.length - 1]! ^ 0xff; // flip one bit-pattern in the ciphertext
    writeFileSync(file, bytes);
    const res = await env.app.inject({ method: 'GET', url: path });
    assert.equal(res.statusCode, 500);
    assert.equal(res.json().error.code, 'internal_error');
  });
});

describe('HTTP surface', () => {
  it('health reports the provider honestly and needs no auth', async () => {
    env = makeEnv({ provider: new UnconfiguredProvider() });
    const res = await env.app.inject({ method: 'GET', url: '/healthz' });
    assert.deepEqual(res.json(), { ok: true, provider: { name: 'none', configured: false, available: true } });
  });

  it('with no provider the capabilities say so, and nothing can be generated', async () => {
    env = makeEnv({ provider: new UnconfiguredProvider() });
    const u = await register(env);
    await grantCredits(env, u.email, 3);
    const caps = (await env.app.inject({ method: 'GET', url: '/v1/generation/capabilities', headers: auth(u.token) })).json();
    assert.equal(caps.engineName, null);
    assert.equal(caps.available, false);
    assert.deepEqual(caps.songTypes, []);
    assert.equal(caps.voiceConditioning, false);
    const res = await submitJob(env, u.token, { voiceId: 'x' });
    assert.equal(res.statusCode, 503);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/credits', headers: auth(u.token) })).json().available, 3);
  });

  it('error responses use one safe shape and never leak internals', async () => {
    env = makeEnv();
    const u = await register(env);
    env.deps.db.exec('DROP TABLE songs'); // sabotage to force an unexpected 500
    const res = await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) });
    assert.equal(res.statusCode, 500);
    assert.deepEqual(res.json(), { error: { code: 'internal_error', message: 'Something went wrong on our side.' } });
    assert.ok(!res.body.includes('songs') && !res.body.includes('SQLITE'));
    const nf = await env.app.inject({ method: 'GET', url: '/nope' });
    assert.equal(nf.statusCode, 404);
    assert.equal(nf.json().error.code, 'not_found');
  });

  it('rejects wrongly typed fields rather than coercing them', async () => {
    env = makeEnv();
    const u = await register(env);
    const res = await env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(u.token),
      payload: { idempotencyKey: 'abcdefgh12', title: 123, lyrics: 'x', language: 'english', songType: 'instrumental' } });
    assert.equal(res.statusCode, 400);
  });

  it('does not enable cross-origin access unless origins are configured', async () => {
    env = makeEnv();
    const res = await env.app.inject({ method: 'OPTIONS', url: '/v1/me', headers: { origin: 'https://evil.example', 'access-control-request-method': 'GET' } });
    assert.ok(!res.headers['access-control-allow-origin']);
    const allowed = makeEnv({ config: { corsOrigins: ['https://app.deenvoice.example'] } });
    const ok = await allowed.app.inject({ method: 'OPTIONS', url: '/v1/me', headers: { origin: 'https://app.deenvoice.example', 'access-control-request-method': 'GET' } });
    assert.equal(ok.headers['access-control-allow-origin'], 'https://app.deenvoice.example');
    await allowed.close();
  });

  it('operator credit grants are audited and validated', async () => {
    env = makeEnv();
    const u = await register(env);
    const post = (payload: object) => env.app.inject({ method: 'POST', url: '/v1/admin/credits/grant', headers: { authorization: `Bearer ${ADMIN_TOKEN}` }, payload });
    assert.equal((await post({ email: u.email, amount: 0, note: 'x' })).statusCode, 400);
    assert.equal((await post({ email: u.email, amount: 1.5, note: 'x' })).statusCode, 400);
    assert.equal((await post({ email: 'nobody@example.com', amount: 1, note: 'x' })).statusCode, 404);
    assert.equal((await post({ email: u.email, amount: 7, note: 'pilot' })).json().available, 7);
    assert.ok(one(env.db, `SELECT 1 AS x FROM audit_events WHERE kind = 'credits.granted'`));
  });
});

describe('secrets and private data do not leak', () => {
  it('passwords, tokens, signing keys, lyrics and audio appear in no log line, audit row or error response', async () => {
    env = makeEnv();
    const u = await register(env);
    await grantCredits(env, u.email, 5);
    const voiceId = await readyVoice(env, u.token);
    const lyrics = 'UNIQUE-LYRICS-MARKER-7f3a only for the singer';
    env.provider.onSubmit = async () => { throw providerError('provider_credentials', 'terminal', { credentialsInvalid: true }); };
    await submitJob(env, u.token, { voiceId, lyrics });
    await env.drain();
    await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: 'wrong wrong wrong' } });

    const haystack = [
      ...env.logs,
      JSON.stringify(all(env.db, 'SELECT * FROM audit_events')),
    ].join('\n');
    for (const secret of [u.password, u.token, MEDIA_KEY, ADMIN_TOKEN, 'UNIQUE-LYRICS-MARKER']) {
      assert.ok(!haystack.includes(secret), `leaked: ${secret}`);
    }
  });
});

describe('operator metrics: completion, latency and cost per successful song', () => {
  it('counts failed-but-billable attempts in the cost of successful songs', async () => {
    env = makeEnv();
    const u = await register(env);
    await grantCredits(env, u.email, 10);
    const voiceId = await readyVoice(env, u.token);

    await submitJob(env, u.token, { voiceId, title: 'ok 1' });
    await env.drain();
    // A job the provider accepted (and so billed) but then failed to deliver.
    env.provider.onPoll = async () => ({ state: 'failed', code: 'failed', message: 'x' });
    await submitJob(env, u.token, { voiceId, title: 'billed then failed' });
    await env.drain();
    // A job refused before the provider accepted it costs nothing.
    env.provider.onSubmit = async () => { throw providerError('provider_rejected', 'terminal'); };
    await submitJob(env, u.token, { voiceId, title: 'refused' });
    await env.drain();
    env.provider.onSubmit = async (_r, n) => ({ providerTaskId: `task-${n}` });
    env.provider.onPoll = async () => ({ state: 'succeeded', audioUrl: 'https://test-double.invalid/a.wav', durationMs: 3000, costMicros: null });
    await submitJob(env, u.token, { voiceId, title: 'ok 2' });
    await env.drain();

    const m = metrics(env.deps, '1970-01-01T00:00:00.000Z');
    assert.deepEqual(m.jobs, { completed: 2, failed: 2 });
    assert.equal(m.completionRate, 0.5);
    assert.equal(m.cost.songsAttemptedMicros, 3 * 45_000, 'three jobs reached the provider; the refused one did not');
    assert.equal(m.cost.perSuccessfulSongMicros, Math.round((3 * 45_000) / 2));
    assert.equal(m.cost.voiceEnrollmentMicros, 5_000_000);
    assert.ok(m.latencyMs.p50 !== null);
    assert.match(m.cost.basis, /estimate/);
    assert.deepEqual(m.failures.map((f) => f.code).sort(), ['provider_failed', 'provider_rejected']);
  });

  it('reports null, not zero, when nothing has completed', () => {
    env = makeEnv();
    const m = metrics(env.deps, '1970-01-01T00:00:00.000Z');
    assert.equal(m.completionRate, null);
    assert.equal(m.cost.perSuccessfulSongMicros, null);
    assert.equal(m.latencyMs.p50, null);
  });
});
