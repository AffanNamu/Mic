import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeEnv, register, auth, grantCredits, submitJob, createVoiceRecord, uploadVoice, readyVoice,
} from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { failFirst, hang, providerError } from './support/scripted-provider.ts';
import { wav } from './support/wav.ts';
import { all, one } from '../src/db.ts';
import { consentStatement } from '../src/consent.ts';
import { MurekaProvider } from '../src/provider/mureka.ts';
import { UnconfiguredProvider } from '../src/provider/unconfigured.ts';
import { readdirSync } from 'node:fs';

let env: Env;
afterEach(async () => { await env?.close(); });

async function setup(opts: Parameters<typeof makeEnv>[0] = {}) {
  env = makeEnv(opts);
  const u = await register(env);
  return u;
}
const voiceOf = async (token: string, id: string) =>
  (await env.app.inject({ method: 'GET', url: '/v1/voices', headers: auth(token) })).json().voices.find((v: { id: string }) => v.id === id);
const blobFiles = () => readdirSync(env.blobDir, { recursive: true, withFileTypes: true }).filter((d) => d.isFile()).length;

describe('consent', () => {
  it('serves the exact statements the server will record', async () => {
    env = makeEnv();
    const res = await env.app.inject({ method: 'GET', url: '/v1/consent-statements' });
    assert.equal(res.statusCode, 200);
    const body = res.json() as { version: string; statements: Array<{ ownership: 'own' | 'authorized'; text: string }> };
    assert.equal(body.version, 'v1');
    assert.deepEqual(body.statements.map((s) => s.ownership).sort(), ['authorized', 'own']);
    for (const s of body.statements) assert.equal(s.text, consentStatement('v1', s.ownership)!.text);
    assert.match(body.statements[0]!.text, /delet/i);
  });

  it('refuses to create a voice without explicit consent, leaving no trace', async () => {
    const u = await setup();
    const res = await createVoiceRecord(env, u.token, { consent: { accepted: false, version: 'v1' } });
    assert.equal(res.statusCode, 400);
    assert.equal(res.json().error.code, 'consent_required');
    assert.equal(all(env.db, 'SELECT * FROM voices').length, 0);
    assert.equal(all(env.db, 'SELECT * FROM consents').length, 0);
  });

  it('refuses an unknown or outdated statement version', async () => {
    const u = await setup();
    const res = await createVoiceRecord(env, u.token, { consent: { accepted: true, version: 'v0-old' } });
    assert.equal(res.json().error.code, 'unknown_consent_version');
  });

  it('records who, when, what text (by hash) and from where; the audit log has no voice data', async () => {
    const u = await setup();
    const res = await env.app.inject({
      method: 'POST', url: '/v1/voices', headers: { ...auth(u.token), 'user-agent': 'DeenVoiceTest/1' },
      payload: { displayName: 'Imam Musa', ownership: 'authorized', authorizedBy: 'Imam Musa (spoken permission, 2026-10-20)', consent: { accepted: true, version: 'v1' } },
    });
    assert.equal(res.statusCode, 201);
    const id = res.json().voice.id as string;
    const c = one(env.db, 'SELECT * FROM consents WHERE voice_id = ?', id)!;
    assert.equal(c['user_id'], u.userId);
    assert.equal(c['ownership'], 'authorized');
    assert.equal(c['statement_sha256'], consentStatement('v1', 'authorized')!.sha256);
    assert.equal(c['accepted_at'], env.clock.now().toISOString());
    assert.equal(c['user_agent'], 'DeenVoiceTest/1');
    assert.equal(c['authorized_by'], 'Imam Musa (spoken permission, 2026-10-20)');
    assert.equal(c['revoked_at'], null);
    assert.ok(one(env.db, `SELECT 1 AS x FROM audit_events WHERE kind = 'voice.consent_recorded' AND subject_id = ?`, id));
  });

  it('"authorized" voices must say whose voice it is', async () => {
    const u = await setup();
    const res = await createVoiceRecord(env, u.token, { ownership: 'authorized', authorizedBy: '  ' });
    assert.equal(res.json().error.code, 'authorized_by_required');
  });

  it('limits how many voices a user can hold', async () => {
    const u = await setup();
    for (let i = 0; i < 3; i++) assert.equal((await createVoiceRecord(env, u.token, { displayName: `v${i}` })).statusCode, 201);
    assert.equal((await createVoiceRecord(env, u.token)).statusCode, 409);
  });

  it('is unavailable when no provider is configured (no pretend enrollment)', async () => {
    const u = await setup({ provider: new UnconfiguredProvider() });
    const res = await createVoiceRecord(env, u.token);
    assert.equal(res.statusCode, 503);
    assert.equal(all(env.db, 'SELECT * FROM voices').length, 0);
  });
});

describe('audio upload validation', () => {
  it('rejects empty, tiny, non-audio, too-long, too-short and oversized samples', async () => {
    const u = await setup();
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    const expectErr = async (audio: Buffer, status: number, code: string, mime = 'audio/wav') => {
      const res = await uploadVoice(env, u.token, id, audio, mime);
      assert.equal(res.statusCode, status, res.body);
      assert.equal(res.json().error.code, code);
    };
    await expectErr(Buffer.alloc(10), 400, 'audio_too_small');
    await expectErr(Buffer.from('this is plainly text, not an audio recording'.padEnd(5000, '.')), 415, 'not_audio');
    await expectErr(Buffer.from('<html>' .padEnd(5000, 'x')), 415, 'not_audio');
    await expectErr(wav(2), 422, 'sample_length');
    await expectErr(wav(40), 422, 'sample_length');
    await expectErr(Buffer.concat([wav(10), Buffer.alloc(3 * 1024 * 1024)]), 413, 'payload_too_large'); // refused by the transport limit before it is buffered
    assert.equal(all(env.db, `SELECT * FROM voices WHERE status != 'awaiting_audio'`).length, 0);
    assert.equal(blobFiles(), 0, 'rejected uploads must not be stored');
  });

  it('requires an audio content type', async () => {
    const u = await setup();
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    const res = await env.app.inject({ method: 'PUT', url: `/v1/voices/${id}/audio`, headers: { ...auth(u.token), 'content-type': 'application/json' }, payload: { a: 1 } });
    assert.ok(res.statusCode >= 400 && res.statusCode < 500);
  });

  it('stores the sample encrypted, accepts it once, and refuses a second upload for a voice in use', async () => {
    const u = await setup();
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    const sample = wav(10);
    const up = await uploadVoice(env, u.token, id, sample);
    assert.equal(up.statusCode, 200);
    assert.equal(up.json().voice.status, 'enrolling');
    const row = one(env.db, 'SELECT * FROM voices WHERE id = ?', id)!;
    assert.deepEqual(await env.deps.blobs.get(String(row['audio_blob_key'])), sample);
    const again = await uploadVoice(env, u.token, id, wav(10));
    assert.equal(again.statusCode, 409);
  });
});

describe('enrollment', () => {
  it('enrolls through the provider and exposes only a safe view of the voice', async () => {
    const u = await setup();
    const id = await readyVoice(env, u.token);
    const v = await voiceOf(u.token, id);
    assert.equal(v.status, 'ready');
    assert.equal(v.supportsSinging, true);
    assert.ok(!('providerVoiceId' in v) && !JSON.stringify(v).includes('vocal-1'), 'provider ids stay server-side');
    assert.equal(one(env.db, 'SELECT provider_cost_micros AS c FROM voices WHERE id = ?', id)!['c'], 5_000_000);
  });

  it('retries only failures where the provider provably did nothing', async () => {
    const u = await setup();
    env.provider.onEnroll = failFirst(1, () => providerError('provider_rate_limited', 'not_started'), async (n) => ({ providerVoiceId: `vocal-${n}`, costMicros: 5_000_000 }));
    const id = await readyVoice(env, u.token);
    assert.equal((await voiceOf(u.token, id)).status, 'ready');
    assert.equal(env.provider.calls.enroll, 2);
  });

  it('does NOT retry when the outcome is unknown (the provider may have billed a Vocal ID)', async () => {
    const u = await setup();
    env.provider.onEnroll = async () => { throw providerError('provider_server_error', 'unknown'); };
    const created = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, created);
    await env.drain();
    const v = await voiceOf(u.token, created);
    assert.equal(v.status, 'failed');
    assert.match(v.failureMessage, /could not confirm/);
    assert.equal(env.provider.calls.enroll, 1);
  });

  it('a hung provider is a failed (unconfirmed) enrollment, not a hang', async () => {
    const u = await setup({ timeouts: { enrollMs: 40 } });
    env.provider.onEnroll = async (_n, signal) => hang(signal);
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, id);
    await env.drain();
    assert.equal((await voiceOf(u.token, id)).status, 'failed');
  });

  it('a provider rejection fails with a user-safe message (no provider text)', async () => {
    const u = await setup();
    env.provider.onEnroll = async () => { throw providerError('provider_rejected', 'terminal'); };
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, id);
    await env.drain();
    const v = await voiceOf(u.token, id);
    assert.equal(v.status, 'failed');
    assert.ok(!JSON.stringify(v).includes('scripted'));
  });

  it('a failed enrollment can be retried a limited number of times', async () => {
    const u = await setup();
    env.provider.onEnroll = async () => { throw providerError('provider_rejected', 'terminal'); };
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, id);
    await env.drain();
    let guard = 0;
    for (; guard < 5; guard++) {
      const retry = await env.app.inject({ method: 'POST', url: `/v1/voices/${id}/retry`, headers: auth(u.token) });
      if (retry.statusCode !== 200) { assert.equal(retry.json().error.code, 'enroll_attempts_exhausted'); break; }
      await env.drain();
    }
    assert.ok(env.provider.calls.enroll <= 3, `enrollment attempted ${env.provider.calls.enroll} times`);
    assert.equal((await voiceOf(u.token, id)).status, 'failed');
  });

  it('with Mureka but no verified clone endpoint configured, enrollment fails closed and says why', async () => {
    const u = await setup({ provider: new MurekaProvider({ apiKey: 'k-test', baseUrl: 'https://api.mureka.ai' }) as never });
    assert.equal(env.provider.capabilities().voiceConditioning, false);
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, id, wav(20)); // Mureka asks for 15-30 s
    await env.drain();
    const v = await voiceOf(u.token, id);
    assert.equal(v.status, 'failed');
    assert.equal(v.supportsSinging, false);
    assert.equal(one(env.db, 'SELECT failure_code AS c FROM voices WHERE id = ?', id)!['c'], 'provider_contract_unverified');
  });
});

describe('revocation and deletion', () => {
  it('revoking stops new songs immediately and records the revocation time', async () => {
    const u = await setup();
    await grantCredits(env, u.email, 3);
    const id = await readyVoice(env, u.token);
    const res = await env.app.inject({ method: 'POST', url: `/v1/voices/${id}/revoke`, headers: auth(u.token) });
    assert.equal(res.json().voice.status, 'revoked');
    assert.ok(one(env.db, 'SELECT revoked_at FROM consents WHERE voice_id = ?', id)!['revoked_at']);
    assert.equal((await submitJob(env, u.token, { voiceId: id })).statusCode, 409);
  });

  it('delete removes the stored recording, tombstones the row, keeps the consent record, and discloses the provider limit', async () => {
    const u = await setup();
    const id = await readyVoice(env, u.token);
    assert.equal(blobFiles(), 1);
    const res = await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) });
    assert.equal(res.statusCode, 200);
    const out = res.json();
    assert.equal(out.localAudioDeleted, true);
    assert.equal(out.providerDeletion, 'unsupported');
    assert.match(out.disclosure, /could not delete its copy/);
    assert.equal(blobFiles(), 0, 'the recording is gone from storage');
    const row = one(env.db, 'SELECT * FROM voices WHERE id = ?', id)!;
    assert.equal(row['status'], 'deleted');
    assert.equal(row['audio_blob_key'], null);
    assert.equal(row['display_name'], 'Deleted voice');
    assert.equal(row['provider_deletion'], 'unsupported');
    assert.ok(one(env.db, 'SELECT revoked_at FROM consents WHERE voice_id = ?', id)!['revoked_at'], 'consent kept for accountability, marked revoked');
    assert.deepEqual((await env.app.inject({ method: 'GET', url: '/v1/voices', headers: auth(u.token) })).json().voices, []);
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) })).statusCode, 404);
  });

  it('says "deleted" at the provider only when the provider confirmed it', async () => {
    const u = await setup();
    env.provider.onDelete = async () => 'deleted';
    const id = await readyVoice(env, u.token);
    const out = (await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) })).json();
    assert.equal(out.providerDeletion, 'deleted');
    assert.match(out.disclosure, /here and at the music provider/);
  });

  it('a provider deletion error is reported as failed, local data is still removed', async () => {
    const u = await setup();
    env.provider.onDelete = async () => { throw new Error('network down'); };
    const id = await readyVoice(env, u.token);
    const out = (await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) })).json();
    assert.equal(out.providerDeletion, 'failed');
    assert.equal(out.localAudioDeleted, true);
    assert.equal(blobFiles(), 0);
  });

  it('a voice that never reached the provider says so', async () => {
    const u = await setup();
    const id = (await createVoiceRecord(env, u.token)).json().voice.id as string;
    await uploadVoice(env, u.token, id);
    const out = (await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) })).json();
    assert.equal(out.providerDeletion, 'not_applicable');
    assert.match(out.disclosure, /had not been sent/);
  });

  it('refuses to delete a voice while a song is being made with it', async () => {
    const u = await setup();
    await grantCredits(env, u.email, 2);
    const id = await readyVoice(env, u.token);
    await submitJob(env, u.token, { voiceId: id });
    const res = await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) });
    assert.equal(res.statusCode, 409);
    assert.equal(res.json().error.code, 'voice_in_use');
    await env.drain();
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/voices/${id}`, headers: auth(u.token) })).statusCode, 200);
  });

  it('can also delete the songs made with the voice, wiping their text and audio; otherwise keeps them', async () => {
    const u = await setup();
    await grantCredits(env, u.email, 4);
    const keep = await readyVoice(env, u.token, { displayName: 'Keep' });
    const drop = await readyVoice(env, u.token, { displayName: 'Drop' });
    await submitJob(env, u.token, { voiceId: keep, title: 'Kept song' });
    await submitJob(env, u.token, { voiceId: drop, title: 'Dropped song', lyrics: 'private words' });
    await env.drain();
    assert.equal(all(env.db, 'SELECT * FROM songs').length, 2);
    const before = blobFiles();

    // Default: songs survive voice deletion (the voice name stays as historic metadata).
    await env.app.inject({ method: 'DELETE', url: `/v1/voices/${keep}`, headers: auth(u.token) });
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs.length, 2);

    const out = (await env.app.inject({ method: 'DELETE', url: `/v1/voices/${drop}?deleteSongs=true`, headers: auth(u.token) })).json();
    assert.equal(out.songsDeleted, 1);
    const songs = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs;
    assert.deepEqual(songs.map((s: { title: string }) => s.title), ['Kept song']);
    const wiped = one(env.db, `SELECT title, lyrics, deleted_at FROM songs WHERE title = '' AND deleted_at IS NOT NULL`)!;
    assert.equal(wiped['lyrics'], '');
    assert.equal(before, 4, 'two voice samples + two songs');
    assert.equal(blobFiles(), 1, 'only the kept song\'s audio remains: both voice samples and the dropped song are gone');
  });
});
