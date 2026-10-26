/**
 * The Phase 2 journey over a REAL TCP socket (not inject): register → consent → upload voice → enroll →
 * submit lyrics → persistent job → result → library → signed link → fetch bytes → restart → reopen.
 *
 * The music provider here is the labelled TEST DOUBLE, so this proves the product plumbing and the
 * HTTP stack. It is NOT evidence that any real provider can sing in a cloned voice.
 */
import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import type { AddressInfo } from 'node:net';
import { makeEnv, ADMIN_TOKEN, jobPayload } from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { wav } from './support/wav.ts';
import { sha256Hex } from '../src/crypto.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

async function listen(e: Env): Promise<string> {
  await e.app.listen({ host: '127.0.0.1', port: 0 });
  return `http://127.0.0.1:${(e.app.server.address() as AddressInfo).port}`;
}

describe('end to end over HTTP (test double provider)', () => {
  it('runs the whole journey and the song survives a restart', async () => {
    env = makeEnv();
    const root = await listen(env);
    const call = async (method: string, path: string, init: { token?: string; json?: unknown; body?: Buffer; type?: string; headers?: Record<string, string> } = {}) => {
      const headers: Record<string, string> = { ...(init.headers ?? {}) };
      if (init.token) headers['authorization'] = `Bearer ${init.token}`;
      let body: string | Buffer | undefined;
      if (init.json !== undefined) { headers['content-type'] = 'application/json'; body = JSON.stringify(init.json); }
      if (init.body) { headers['content-type'] = init.type ?? 'audio/wav'; body = init.body; }
      const payload = typeof body === 'string' ? body : body ? new Uint8Array(body) : undefined;
      return fetch(`${root}${path}`, { method, headers, ...(payload !== undefined ? { body: payload } : {}) });
    };

    // 1. account + credits (operator grant, as in a pilot)
    const reg = await (await call('POST', '/v1/auth/register', { json: { email: 'participant@example.com', password: 'a sound password 123' } })).json() as { token: string };
    const token = reg.token;
    await call('POST', '/v1/admin/credits/grant', { token: ADMIN_TOKEN, json: { email: 'participant@example.com', amount: 3, note: 'pilot' } });
    assert.deepEqual(await (await call('GET', '/v1/credits', { token })).json(), { available: 3, held: 0 });

    // 2. consent text from the server, then the voice record, then the recording
    const statements = await (await call('GET', '/v1/consent-statements')).json() as { version: string };
    const created = await (await call('POST', '/v1/voices', { token, json: {
      displayName: 'Participant', ownership: 'own', consent: { accepted: true, version: statements.version } } })).json() as { voice: { id: string; status: string } };
    assert.equal(created.voice.status, 'awaiting_audio');
    const up = await call('PUT', `/v1/voices/${created.voice.id}/audio`, { token, body: wav(10) });
    assert.equal(up.status, 200);
    assert.equal(((await up.json()) as { voice: { status: string } }).voice.status, 'enrolling');

    // 3. the worker (normally a timer) enrolls
    await env.drain();
    const voices = await (await call('GET', '/v1/voices', { token })).json() as { voices: Array<{ status: string; supportsSinging: boolean }> };
    assert.equal(voices.voices[0]!.status, 'ready');

    // 4. lyrics + settings + idempotency key → persistent job
    const payload = jobPayload({ voiceId: created.voice.id, title: 'First test song', lyrics: 'Original lyrics written by the participant' });
    const sent = await call('POST', '/v1/generation/jobs', { token, json: payload });
    assert.equal(sent.status, 202);
    const job = (await sent.json() as { job: { id: string; status: string } }).job;
    assert.equal(job.status, 'queued');
    assert.deepEqual(await (await call('GET', '/v1/credits', { token })).json(), { available: 2, held: 1 });

    const audio = wav(6, { hz: 440 });
    env.provider.onDownload = async () => audio;
    await env.drain();
    const done = (await (await call('GET', `/v1/generation/jobs/${job.id}`, { token })).json() as { job: { status: string; songId: string } }).job;
    assert.equal(done.status, 'completed');
    assert.deepEqual(await (await call('GET', '/v1/credits', { token })).json(), { available: 2, held: 0 });

    // 5. library → signed link → bytes (as a browser audio element would fetch, without auth headers)
    const lib = await (await call('GET', '/v1/songs', { token })).json() as { songs: Array<{ id: string; title: string; audioBytes: number }> };
    assert.equal(lib.songs.length, 1);
    assert.equal(lib.songs[0]!.title, 'First test song');
    const link = await (await call('POST', `/v1/songs/${lib.songs[0]!.id}/audio-url`, { token })).json() as { path: string };
    const media = await fetch(`${root}${link.path}`);
    assert.equal(media.status, 200);
    assert.equal(media.headers.get('content-type'), 'audio/wav');
    const got = Buffer.from(await media.arrayBuffer());
    assert.equal(sha256Hex(got), sha256Hex(audio));
    const part = await fetch(`${root}${link.path}`, { headers: { range: 'bytes=0-43' } });
    assert.equal(part.status, 206);
    assert.equal(Buffer.from(await part.arrayBuffer()).subarray(0, 4).toString(), 'RIFF');

    // 6. restart the whole server on the same storage; sign in again; the song is still there and plays
    await env.app.close();
    const second = env.restart();
    const root2 = await listen(second);
    env = second;
    const login = await (await fetch(`${root2}/v1/auth/login`, { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'participant@example.com', password: 'a sound password 123' }) })).json() as { token: string };
    const lib2 = await (await fetch(`${root2}/v1/songs`, { headers: { authorization: `Bearer ${login.token}` } })).json() as { songs: Array<{ id: string }> };
    assert.equal(lib2.songs.length, 1);
    const link2 = await (await fetch(`${root2}/v1/songs/${lib2.songs[0]!.id}/audio-url`, { method: 'POST', headers: { authorization: `Bearer ${login.token}` } })).json() as { path: string };
    const again = Buffer.from(await (await fetch(`${root2}${link2.path}`)).arrayBuffer());
    assert.equal(sha256Hex(again), sha256Hex(audio));
  });
});
