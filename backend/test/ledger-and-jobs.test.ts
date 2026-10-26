import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeEnv, register, auth, grantCredits, submitJob, jobPayload, readyVoice, balanceOf, getJob, newKey, assertLedgerInvariants,
} from './support/harness.ts';
import type { Env } from './support/harness.ts';
import * as ledger from '../src/ledger.ts';
import { all, one, run } from '../src/db.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

let voiceId = '';
async function setup(credits = 5) {
  env = makeEnv();
  const u = await register(env);
  if (credits > 0) await grantCredits(env, u.email, credits);
  voiceId = await readyVoice(env, u.token);
  return u;
}
/** Submits a song with the user's ready voice unless the test says otherwise. */
const job = (token: string, over: Record<string, unknown> = {}) => submitJob(env, token, { voiceId, ...over });

describe('credit ledger', () => {
  it('reserve holds, capture spends once, release returns once', async () => {
    const u = await setup(3);
    const { db, clock } = env.deps;
    ledger.reserve(db, clock, u.userId, 'job-a', 1);
    assert.deepEqual(ledger.balance(db, u.userId), { available: 2, held: 1 });
    assert.equal(ledger.capture(db, clock, 'job-a'), 'captured');
    assert.deepEqual(ledger.balance(db, u.userId), { available: 2, held: 0 });
    assert.equal(ledger.capture(db, clock, 'job-a'), 'already_final');
    assert.equal(ledger.release(db, clock, 'job-a', 'late'), 'already_final');
    assert.deepEqual(ledger.balance(db, u.userId), { available: 2, held: 0 });

    ledger.reserve(db, clock, u.userId, 'job-b', 2);
    assert.deepEqual(ledger.balance(db, u.userId), { available: 0, held: 2 });
    assert.equal(ledger.release(db, clock, 'job-b', 'failed'), 'released');
    assert.equal(ledger.release(db, clock, 'job-b', 'failed again'), 'already_final');
    assert.equal(ledger.capture(db, clock, 'job-b'), 'already_final');
    assert.deepEqual(ledger.balance(db, u.userId), { available: 2, held: 0 });
    assert.equal(ledger.release(db, clock, 'never-reserved', 'x'), 'no_hold');
  });

  it('refuses to reserve more than the available balance and records nothing', async () => {
    const u = await setup(1);
    const { db, clock } = env.deps;
    assert.throws(() => ledger.reserve(db, clock, u.userId, 'big', 2), (e: { status?: number; code?: string }) =>
      e.status === 402 && e.code === 'insufficient_credits');
    assert.equal(all(db, `SELECT * FROM credit_ledger WHERE job_id = 'big'`).length, 0);
    assert.throws(() => ledger.grant(db, clock, u.userId, -5, 'x'));
    assert.throws(() => ledger.grant(db, clock, u.userId, 1.5, 'x'));
  });

  it('every transaction is listed with a kind and the job it belongs to', async () => {
    const u = await setup(2);
    const res = await job(u.token);
    await env.drain();
    const tx = (await env.app.inject({ method: 'GET', url: '/v1/credits/transactions', headers: auth(u.token) })).json().transactions as Array<{ kind: string; jobId: string | null }>;
    assert.deepEqual(tx.map((t) => t.kind).reverse(), ['grant', 'reserve', 'capture']);
    assert.equal(tx[0]!.jobId, res.json().job.id);
  });
});

describe('job submission: credits', () => {
  it('rejects with 402 when the balance is too low, creating no job and no ledger entry', async () => {
    const u = await setup(0);
    const res = await job(u.token);
    assert.equal(res.statusCode, 402);
    assert.equal(res.json().error.code, 'insufficient_credits');
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 0);
    assert.equal(all(env.db, `SELECT * FROM credit_ledger WHERE kind != 'grant'`).length, 0);
    assert.equal(env.provider.calls.submit, 0, 'the provider must never be called without credits');
  });

  it('holds exactly the price on acceptance and the balance reflects it immediately', async () => {
    const u = await setup(3);
    const res = await job(u.token);
    assert.equal(res.statusCode, 202);
    assert.deepEqual(await balanceOf(env, u.token), { available: 2, held: 1 });
  });

  it('cannot spend the same credit on two jobs', async () => {
    const u = await setup(1);
    const results = await Promise.all([job(u.token), job(u.token), job(u.token)]);
    assert.deepEqual(results.map((r) => r.statusCode).sort(), [202, 402, 402]);
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 1);
    assert.deepEqual(await balanceOf(env, u.token), { available: 0, held: 1 });
  });
});

describe('job submission: idempotency and duplicates', () => {
  it('the same key with the same request returns the same job and charges once', async () => {
    const u = await setup(5);
    const payload = jobPayload({ voiceId });
    const send = () => env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(u.token), payload });
    const first = await send();
    const second = await send();
    assert.equal(first.statusCode, 202);
    assert.equal(first.json().deduplicated, false);
    assert.equal(second.statusCode, 200);
    assert.equal(second.json().deduplicated, true);
    assert.equal(second.json().job.id, first.json().job.id);
    assert.deepEqual(await balanceOf(env, u.token), { available: 4, held: 1 });
    await env.drain();
    assert.equal(env.provider.calls.submit, 1, 'one provider submission for two client requests');
  });

  it('concurrent duplicate requests (a double tap or a retry racing the first) produce one job', async () => {
    const u = await setup(5);
    const payload = jobPayload({ voiceId });
    const results = await Promise.all(Array.from({ length: 6 }, () =>
      env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(u.token), payload })));
    const ids = new Set(results.map((r) => r.json().job.id));
    assert.equal(ids.size, 1);
    assert.equal(results.filter((r) => r.statusCode === 202).length, 1);
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 1);
    assert.equal(all(env.db, `SELECT * FROM credit_ledger WHERE kind = 'reserve'`).length, 1);
  });

  it('the same key with a different request is refused, not silently merged', async () => {
    const u = await setup(5);
    const key = newKey();
    assert.equal((await job(u.token, { idempotencyKey: key })).statusCode, 202);
    const changed = await job(u.token, { idempotencyKey: key, lyrics: 'different words' });
    assert.equal(changed.statusCode, 422);
    assert.equal(changed.json().error.code, 'idempotency_key_reuse');
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 1);
  });

  it('a retry after the job already finished still returns the finished job without a second charge', async () => {
    const u = await setup(5);
    const payload = jobPayload({ voiceId });
    const first = await env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(u.token), payload });
    await env.drain();
    const again = await env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(u.token), payload });
    assert.equal(again.json().job.id, first.json().job.id);
    assert.equal(again.json().job.status, 'completed');
    assert.deepEqual(await balanceOf(env, u.token), { available: 4, held: 0 });
    assert.equal(all(env.db, 'SELECT * FROM songs').length, 1);
  });

  it('keys are scoped per user', async () => {
    const a = await setup(2);
    const b = await register(env, 'b@example.com');
    await grantCredits(env, b.email, 2);
    const key = newKey();
    const ra = await job(a.token, { idempotencyKey: key });
    const rb = await submitJob(env, b.token, { idempotencyKey: key, voiceId: await readyVoice(env, b.token) });
    assert.equal(ra.statusCode, 202);
    assert.equal(rb.statusCode, 202);
    assert.notEqual(ra.json().job.id, rb.json().job.id);
  });

  it('rejects malformed idempotency keys', async () => {
    const u = await setup(2);
    assert.equal((await job(u.token, { idempotencyKey: 'short' })).statusCode, 400);
    assert.equal((await job(u.token, { idempotencyKey: 'has spaces and !!! in it' })).statusCode, 400);
  });
});

describe('job submission: validation against what the engine can honestly do', () => {
  it('rejects empty/oversized lyrics, bad titles, unsupported languages, types and options', async () => {
    const u = await setup(10);
    const expectCode = async (over: Record<string, unknown>, status: number, code: string) => {
      const res = await job(u.token, over);
      assert.equal(res.statusCode, status, `${code}: ${res.body}`);
      assert.equal(res.json().error.code, code);
    };
    await expectCode({ lyrics: '   ' }, 400, 'lyrics_required');
    await expectCode({ lyrics: 'x'.repeat(3001) }, 400, 'lyrics_too_long');
    await expectCode({ title: '   ' }, 400, 'invalid_title');
    await expectCode({ title: 'T'.repeat(81) }, 400, 'invalid_title');
    await expectCode({ language: 'hausa' }, 422, 'unsupported_language');
    await expectCode({ songType: 'karaoke' }, 422, 'unsupported_song_type');
    await expectCode({ advanced: { reverb: 'max' } }, 422, 'unsupported_option');
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 0);
    assert.deepEqual(await balanceOf(env, u.token), { available: 10, held: 0 });
  });

  it('voice-based types need a voice that is ready, owned, consented and able to sing', async () => {
    const u = await setup(10);
    assert.equal((await job(u.token, { voiceId: null })).json().error.code, 'voice_required');
    assert.equal((await job(u.token, { voiceId: 'does-not-exist' })).statusCode, 404);
    run(env.db, `UPDATE voices SET supports_singing = 0 WHERE id = ?`, voiceId); // e.g. a speech-only profile
    const speechOnly = await job(u.token);
    assert.equal(speechOnly.statusCode, 409);
    assert.equal(speechOnly.json().error.code, 'voice_not_ready');
    run(env.db, `UPDATE voices SET supports_singing = 1 WHERE id = ?`, voiceId);

    await env.app.inject({ method: 'POST', url: `/v1/voices/${voiceId}/revoke`, headers: auth(u.token) });
    const revoked = await job(u.token);
    assert.equal(revoked.statusCode, 409);
    assert.equal(all(env.db, 'SELECT * FROM jobs').length, 0);
  });

  it('refuses a voice-based song when the engine cannot sing in a saved voice', async () => {
    const u = await setup(5);
    env.provider.caps = { voiceConditioning: false };
    const res = await job(u.token);
    assert.equal(res.statusCode, 422);
    assert.equal(res.json().error.code, 'voice_conditioning_unsupported');
  });

  it('an instrumental needs no voice', async () => {
    const u = await setup(2);
    const res = await job(u.token, { songType: 'instrumental', voiceId: null });
    assert.equal(res.statusCode, 202);
  });

  it('with no provider configured nothing is accepted and nothing is charged', async () => {
    const u = await setup(2);
    env.provider.configured = false;
    const res = await job(u.token);
    assert.equal(res.statusCode, 503);
    assert.equal(res.json().error.code, 'provider_not_configured');
    assert.deepEqual(await balanceOf(env, u.token), { available: 2, held: 0 });
  });
});

describe('cancellation', () => {
  it('cancels a queued job and returns the credit; refuses once the provider has it', async () => {
    const u = await setup(2);
    const a = (await job(u.token)).json().job.id as string;
    const cancel = await env.app.inject({ method: 'POST', url: `/v1/generation/jobs/${a}/cancel`, headers: auth(u.token) });
    assert.equal(cancel.json().job.status, 'cancelled');
    assert.deepEqual(await balanceOf(env, u.token), { available: 2, held: 0 });
    await env.drain();
    assert.equal(env.provider.calls.submit, 0, 'a cancelled job is never sent to the provider');

    const b = (await job(u.token)).json().job.id as string;
    await env.worker.tick(1);
    assert.equal((await getJob(env, u.token, b))['status'], 'processing');
    const late = await env.app.inject({ method: 'POST', url: `/v1/generation/jobs/${b}/cancel`, headers: auth(u.token) });
    assert.equal(late.statusCode, 409);
    assertLedgerInvariants(env.db);
  });
});

describe('quote and capabilities are honest', () => {
  it('report the engine and what it cannot do', async () => {
    const u = await setup(0);
    const caps = (await env.app.inject({ method: 'GET', url: '/v1/generation/capabilities', headers: auth(u.token) })).json();
    assert.equal(caps.engineName, 'Test double');
    assert.deepEqual(caps.documentedLanguages, ['english']);
    assert.ok(!caps.languages.includes('hausa'));
    assert.equal(caps.available, true);
    const quote = (await env.app.inject({ method: 'GET', url: '/v1/generation/quote', headers: auth(u.token) })).json();
    assert.equal(quote.credits, 1);
    void one;
  });
});
