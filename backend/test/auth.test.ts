import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { makeEnv, register, auth, grantCredits, createVoiceRecord, submitJob, readyVoice, ADMIN_TOKEN } from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { all, one } from '../src/db.ts';
import { sha256Hex } from '../src/crypto.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

describe('authentication', () => {
  it('registers, returns a token, and stores only its hash', async () => {
    env = makeEnv();
    const u = await register(env);
    assert.ok(u.token.length >= 40);
    const row = one(env.db, 'SELECT token_hash FROM sessions WHERE user_id = ?', u.userId)!;
    assert.equal(row['token_hash'], sha256Hex(u.token));
    assert.ok(!JSON.stringify(all(env.db, 'SELECT * FROM sessions')).includes(u.token));
    const users = JSON.stringify(all(env.db, 'SELECT * FROM users'));
    assert.ok(!users.includes(u.password), 'password must never be stored');
    assert.match(String(one(env.db, 'SELECT password_hash FROM users')!['password_hash']), /^scrypt\$/);
  });

  it('rejects weak passwords, bad emails and duplicate accounts (case-insensitive)', async () => {
    env = makeEnv();
    const bad = async (payload: object) => env.app.inject({ method: 'POST', url: '/v1/auth/register', payload });
    assert.equal((await bad({ email: 'a@example.com', password: 'short' })).statusCode, 400);
    assert.equal((await bad({ email: 'not-an-email', password: 'long enough password' })).statusCode, 400);
    assert.equal((await bad({ email: 'a@example.com' })).statusCode, 400);
    assert.equal((await bad({ email: 'a@example.com', password: 'long enough password', admin: true })).statusCode, 400, 'unknown fields are rejected, not silently dropped');
    assert.equal((await bad({ email: 'Amina@Example.com', password: 'long enough password' })).statusCode, 201);
    const dup = await bad({ email: 'amina@example.com', password: 'another long password' });
    assert.equal(dup.statusCode, 409);
    assert.equal(dup.json().error.code, 'email_taken');
  });

  it('logs in with the right password and gives the same error for a wrong password and an unknown email', async () => {
    env = makeEnv();
    const u = await register(env);
    const ok = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email.toUpperCase(), password: u.password } });
    assert.equal(ok.statusCode, 200);
    const wrong = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: 'wrong password!!' } });
    const unknown = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'nobody@example.com', password: 'wrong password!!' } });
    assert.equal(wrong.statusCode, 401);
    assert.equal(unknown.statusCode, 401);
    assert.deepEqual(wrong.json(), unknown.json());
  });

  it('rate-limits repeated login attempts', async () => {
    env = makeEnv();
    const attempt = () => env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'a@example.com', password: 'whatever long' } });
    const codes: number[] = [];
    for (let i = 0; i < 12; i++) codes.push((await attempt()).statusCode);
    assert.equal(codes[0], 401);
    assert.equal(codes[11], 429);
  });

  it('expires sessions and honours logout', async () => {
    env = makeEnv();
    const u = await register(env);
    const me = () => env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(u.token) });
    assert.equal((await me()).statusCode, 200);
    env.clock.advance(env.config.sessionTtlMs + 1000);
    const expired = await me();
    assert.equal(expired.statusCode, 401);
    assert.match(expired.json().error.message, /expired/);

    const second = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: u.password } });
    const token2 = second.json().token as string;
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(token2) })).statusCode, 200);
    assert.equal((await env.app.inject({ method: 'POST', url: '/v1/auth/logout', headers: auth(token2) })).statusCode, 204);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(token2) })).statusCode, 401);
  });

  it('rejects disabled accounts even with a live session', async () => {
    env = makeEnv();
    const u = await register(env);
    env.db.prepare('UPDATE users SET disabled_at = ? WHERE id = ?').run(env.clock.now().toISOString(), u.userId);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(u.token) })).statusCode, 401);
    const login = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: u.password } });
    assert.equal(login.statusCode, 401);
  });
});

describe('every protected route requires a valid token', () => {
  const routes: Array<[string, string]> = [
    ['GET', '/v1/me'], ['GET', '/v1/credits'], ['GET', '/v1/credits/transactions'],
    ['GET', '/v1/generation/capabilities'], ['GET', '/v1/generation/quote'],
    ['POST', '/v1/generation/jobs'], ['GET', '/v1/generation/jobs'], ['GET', '/v1/generation/jobs/x'],
    ['POST', '/v1/generation/jobs/x/cancel'], ['GET', '/v1/voices'], ['POST', '/v1/voices'],
    ['PUT', '/v1/voices/x/audio'], ['POST', '/v1/voices/x/retry'], ['POST', '/v1/voices/x/revoke'],
    ['DELETE', '/v1/voices/x'], ['GET', '/v1/songs'], ['GET', '/v1/songs/x'], ['PATCH', '/v1/songs/x'],
    ['DELETE', '/v1/songs/x'], ['POST', '/v1/songs/x/audio-url'], ['POST', '/v1/auth/logout'],
  ];
  it('returns 401 without a token, with a garbage token and with a non-bearer scheme', async () => {
    env = makeEnv();
    for (const [method, url] of routes) {
      for (const headers of [{}, { authorization: 'Bearer not-a-real-token' }, { authorization: 'Basic abc' }]) {
        const res = await env.app.inject({ method: method as 'GET', url, headers });
        assert.equal(res.statusCode, 401, `${method} ${url} with ${JSON.stringify(headers)} gave ${res.statusCode}`);
      }
    }
  });

  it('operator routes reject user tokens and missing tokens', async () => {
    env = makeEnv();
    const u = await register(env);
    for (const [method, url] of [['POST', '/v1/admin/credits/grant'], ['GET', '/v1/admin/metrics'], ['POST', '/v1/admin/provider/reset-health']] as const) {
      assert.equal((await env.app.inject({ method, url })).statusCode, 403);
      assert.equal((await env.app.inject({ method, url, headers: auth(u.token) })).statusCode, 403);
    }
    const ok = await env.app.inject({ method: 'GET', url: '/v1/admin/metrics', headers: { authorization: `Bearer ${ADMIN_TOKEN}` } });
    assert.equal(ok.statusCode, 200);
  });

  it('operator routes are disabled when no admin token is configured', async () => {
    env = makeEnv({ config: { adminToken: null } });
    const res = await env.app.inject({ method: 'GET', url: '/v1/admin/metrics', headers: { authorization: 'Bearer anything' } });
    assert.equal(res.statusCode, 403);
  });
});

describe('authorization: users cannot reach each other\'s data', () => {
  it('voices, jobs, songs and balances are isolated per user', async () => {
    env = makeEnv();
    const a = await register(env, 'a@example.com');
    const b = await register(env, 'b@example.com');
    await grantCredits(env, a.email, 5);
    await grantCredits(env, b.email, 5);
    const voiceId = await readyVoice(env, a.token);
    const job = await submitJob(env, a.token, { voiceId });
    assert.equal(job.statusCode, 202);
    const jobId = job.json().job.id as string;
    await env.drain();
    const songId = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(a.token) })).json().songs[0].id as string;

    const get = (url: string, token = b.token) => env.app.inject({ method: 'GET', url, headers: auth(token) });
    assert.equal((await get(`/v1/generation/jobs/${jobId}`)).statusCode, 404);
    assert.equal((await get(`/v1/songs/${songId}`)).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'POST', url: `/v1/songs/${songId}/audio-url`, headers: auth(b.token) })).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'PATCH', url: `/v1/songs/${songId}`, headers: auth(b.token), payload: { title: 'stolen' } })).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/songs/${songId}`, headers: auth(b.token) })).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'POST', url: `/v1/generation/jobs/${jobId}/cancel`, headers: auth(b.token) })).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/voices/${voiceId}`, headers: auth(b.token) })).statusCode, 404);
    assert.equal((await env.app.inject({ method: 'POST', url: `/v1/voices/${voiceId}/revoke`, headers: auth(b.token) })).statusCode, 404);
    assert.deepEqual((await get('/v1/voices')).json().voices, []);
    assert.deepEqual((await get('/v1/songs')).json().songs, []);
    assert.deepEqual((await get('/v1/generation/jobs')).json().jobs, []);

    // Using someone else's voice id to generate must look like "no such voice".
    const steal = await submitJob(env, b.token, { voiceId });
    assert.equal(steal.statusCode, 404);
    // b's balance is untouched by a's activity
    assert.equal((await get('/v1/credits')).json().available, 5);
  });
});

describe('voice creation requires a signed-in user and consent (smoke)', () => {
  it('cannot create a voice anonymously', async () => {
    env = makeEnv();
    const res = await env.app.inject({ method: 'POST', url: '/v1/voices', payload: { displayName: 'x', ownership: 'own', consent: { accepted: true, version: 'v1' } } });
    assert.equal(res.statusCode, 401);
    const u = await register(env);
    assert.equal((await createVoiceRecord(env, u.token)).statusCode, 201);
  });
});
