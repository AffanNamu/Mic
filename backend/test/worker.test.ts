import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import {
  makeEnv, register, auth, grantCredits, submitJob, readyVoice, balanceOf, getJob, assertLedgerInvariants,
} from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { failFirst, hang, providerError } from './support/scripted-provider.ts';
import { wav } from './support/wav.ts';
import { all, one, run } from '../src/db.ts';
import { sha256Hex } from '../src/crypto.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

async function setup(opts: Parameters<typeof makeEnv>[0] = {}, credits = 5) {
  env = makeEnv(opts);
  const u = await register(env);
  await grantCredits(env, u.email, credits);
  const voiceId = await readyVoice(env, u.token);
  const submit = async (over: Record<string, unknown> = {}) => {
    const res = await submitJob(env, u.token, { voiceId, ...over });
    assert.equal(res.statusCode, 202, res.body);
    return res.json().job.id as string;
  };
  return { u, voiceId, submit };
}

const status = async (u: { token: string }, id: string) => getJob(env, u.token, id);

describe('happy path (test double: proves plumbing only)', () => {
  it('queued → processing → completed, stores the audio, creates a song, captures the credit', async () => {
    const { u, voiceId, submit } = await setup();
    const audio = wav(4);
    env.provider.onDownload = async () => audio;
    const id = await submit();
    assert.equal((await status(u, id))['status'], 'queued');

    await env.worker.tick(1);
    assert.equal((await status(u, id))['status'], 'processing');
    assert.equal(one(env.db, 'SELECT provider_task_id FROM jobs WHERE id = ?', id)!['provider_task_id'], 'task-1');

    await env.drain();
    const job = await status(u, id);
    assert.equal(job['status'], 'completed');
    assert.ok(job['songId']);

    const song = one(env.db, 'SELECT * FROM songs WHERE id = ?', String(job['songId']))!;
    assert.equal(song['audio_sha256'], sha256Hex(audio));
    assert.equal(song['audio_mime'], 'audio/wav');
    assert.equal(song['voice_id'], voiceId);
    assert.deepEqual(await env.deps.blobs.get(String(song['audio_blob_key'])), audio);
    assert.deepEqual(await balanceOf(env, u.token), { available: 4, held: 0 });
    assertLedgerInvariants(env.db);
  });

  it('sends the provider the lyrics, the style text and the enrolled voice id — nothing else of the user\'s', async () => {
    const { submit } = await setup();
    await submit({ lyrics: 'Bismillah, I begin with Your name', style: { genre: 'english_nasheed', mood: 'peaceful', tempo: 'slow' } });
    await env.drain();
    const req = env.provider.submitted[0]!;
    assert.equal(req.lyrics, 'Bismillah, I begin with Your name');
    assert.equal(req.providerVoiceId, 'vocal-1');
    assert.match(req.stylePrompt, /English nasheed.*peaceful.*slow tempo/);
  });

  it('keeps polling while the provider says it is still running', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async (_t, n) => (n < 4
      ? { state: 'running' }
      : { state: 'succeeded', audioUrl: 'https://test-double.invalid/a.wav', durationMs: 3000, costMicros: null });
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['status'], 'completed');
    assert.equal(env.provider.calls.poll, 4);
    assert.equal(env.provider.calls.submit, 1);
  });
});

describe('submission failures', () => {
  it('retries a request the provider provably did not start (429) and then succeeds, billing once', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = failFirst(2, () => providerError('provider_rate_limited', 'not_started', { retryAfterMs: 1000 }),
      async (_r, n) => ({ providerTaskId: `task-${n}` }));
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['status'], 'completed');
    assert.equal(env.provider.calls.submit, 3);
    assert.deepEqual(await balanceOf(env, u.token), { available: 4, held: 0 });
    assertLedgerInvariants(env.db);
  });

  it('gives up after repeated "not started" failures, returns the credit and says why', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = async () => { throw providerError('provider_unreachable', 'not_started'); };
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['status'], 'failed');
    assert.equal(job['failureCode'], 'provider_unavailable');
    assert.match(String(job['failureMessage']), /credits were returned/);
    assert.equal(env.provider.calls.submit, 4);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
    assertLedgerInvariants(env.db);
  });

  it('NEVER resubmits when the outcome is unknown (5xx on a write): one call, credit returned', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = async () => { throw providerError('provider_server_error', 'unknown', { httpStatus: 502 }); };
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['status'], 'failed');
    assert.equal(job['failureCode'], 'submit_outcome_unknown');
    assert.equal(env.provider.calls.submit, 1, 'a second submit could bill a second song');
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
    assertLedgerInvariants(env.db);
  });

  it('treats a hung provider as a timeout with unknown outcome: no retry, credit returned', async () => {
    const { u, submit } = await setup({ timeouts: { submitMs: 40 } });
    env.provider.onSubmit = async (_r, _n, signal) => hang(signal);
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['status'], 'failed');
    assert.equal(job['failureCode'], 'submit_outcome_unknown');
    assert.equal(env.provider.calls.submit, 1);
    assertLedgerInvariants(env.db);
  });

  it('a provider rejection (bad input, policy) fails immediately without retry and returns the credit', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = async () => { throw providerError('provider_rejected', 'terminal', { httpStatus: 400 }); };
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['failureCode'], 'provider_rejected');
    assert.equal(env.provider.calls.submit, 1);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
  });

  it('does not show provider error text to the user', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = async () => { throw new (providerError('x', 'terminal').constructor as new (c: string, m: string, o: object) => Error)('x', 'SECRET-PROVIDER-DETAIL api key sk-live-abc', { outcome: 'terminal' }); };
    const id = await submit();
    await env.drain();
    const body = JSON.stringify(await status(u, id));
    assert.ok(!body.includes('SECRET-PROVIDER-DETAIL') && !body.includes('sk-live'));
  });
});

describe('expired / invalid provider credentials and exhausted provider funds', () => {
  it('fails the job, returns the credit, blocks new jobs fast, and recovers after an operator reset', async () => {
    const { u, voiceId, submit } = await setup();
    env.provider.onSubmit = async () => {
      throw providerError('provider_credentials', 'terminal', { credentialsInvalid: true, httpStatus: 401 });
    };
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['failureCode'], 'provider_credentials');
    assert.match(String(job['failureMessage']), /temporarily unavailable/);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });

    const blocked = await submitJob(env, u.token, { voiceId });
    assert.equal(blocked.statusCode, 503);
    assert.equal(blocked.json().error.code, 'provider_unavailable');
    const caps = (await env.app.inject({ method: 'GET', url: '/v1/generation/capabilities', headers: auth(u.token) })).json();
    assert.equal(caps.available, false, 'the client is told the service is down rather than being let to try');
    assert.equal(env.provider.calls.submit, 1, 'no further provider calls while credentials are known bad');
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });

    // After the block window passes it is tried again.
    env.clock.advance(5 * 60_000 + 1000);
    env.provider.onSubmit = async (_r, n) => ({ providerTaskId: `task-${n}` });
    const again = await submitJob(env, u.token, { voiceId });
    assert.equal(again.statusCode, 202);
    await env.drain();
    assert.equal((await status(u, again.json().job.id))['status'], 'completed');
  });

  it('credentials rejected while polling also fail the job and release the credit', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => { throw providerError('provider_credentials', 'terminal', { credentialsInvalid: true }); };
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['failureCode'], 'provider_credentials');
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
  });

  it('exhausted provider balance fails the job as "unavailable" and blocks new jobs', async () => {
    const { u, voiceId, submit } = await setup();
    env.provider.onSubmit = async () => { throw providerError('provider_funds', 'terminal', { providerFunds: true, httpStatus: 402 }); };
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['failureCode'], 'provider_unavailable');
    assert.equal((await submitJob(env, u.token, { voiceId })).statusCode, 503);
  });

  it('the operator can clear the block', async () => {
    const { u, voiceId, submit } = await setup();
    env.provider.onSubmit = async () => { throw providerError('provider_credentials', 'terminal', { credentialsInvalid: true }); };
    await submit();
    await env.drain();
    env.provider.onSubmit = async (_r, n) => ({ providerTaskId: `task-${n}` });
    const reset = await env.app.inject({ method: 'POST', url: '/v1/admin/provider/reset-health', headers: { authorization: 'Bearer test-admin-token-0123456789abcdef' } });
    assert.equal(reset.statusCode, 200);
    assert.equal((await submitJob(env, u.token, { voiceId })).statusCode, 202);
  });
});

describe('polling failures', () => {
  it('survives transient poll errors', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = failFirst(3, () => providerError('provider_server_error', 'not_started'),
      async () => ({ state: 'succeeded', audioUrl: 'https://test-double.invalid/a.wav', durationMs: 3000, costMicros: null }));
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['status'], 'completed');
    assert.equal(env.provider.calls.submit, 1, 'poll trouble must never cause a resubmission');
  });

  it('gives up after repeated poll failures and returns the credit', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => { throw providerError('provider_server_error', 'not_started'); };
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['failureCode'], 'poll_failed');
    assert.equal(env.provider.calls.poll, 5);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
  });

  it('a provider-reported failure fails the job and returns the credit', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => ({ state: 'failed', code: 'failed', message: 'PROVIDER SAID: lyrics violated policy' });
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['failureCode'], 'provider_failed');
    assert.ok(!JSON.stringify(job).includes('PROVIDER SAID'));
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
  });

  it('a hung poll times out and is retried as a read', async () => {
    const { u, submit } = await setup({ timeouts: { pollMs: 40 } });
    env.provider.onPoll = failFirst(1, () => new Error('unused'), async () => ({ state: 'succeeded', audioUrl: 'https://test-double.invalid/a.wav', durationMs: 1, costMicros: null }));
    env.provider.onPoll = (() => {
      let n = 0;
      return async (_t: string, _n: number, signal: AbortSignal) => {
        if (n++ === 0) return hang(signal);
        return { state: 'succeeded' as const, audioUrl: 'https://test-double.invalid/a.wav', durationMs: 1, costMicros: null };
      };
    })();
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['status'], 'completed');
  });

  it('stops waiting at the job deadline even if the provider says "running" forever', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => ({ state: 'running' });
    const id = await submit();
    await env.drain({ stepMs: 60_000, maxRounds: 100 });
    const job = await status(u, id);
    assert.equal(job['status'], 'failed');
    assert.equal(job['failureCode'], 'timeout');
    assert.match(String(job['failureMessage']), /too long/);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
    assertLedgerInvariants(env.db);
  });
});

describe('empty and invalid results: a 200 is not a song', () => {
  const cases: Array<[string, () => Buffer, string]> = [
    ['an empty body', () => Buffer.alloc(0), 'empty_result'],
    ['an HTML error page', () => Buffer.from('<!doctype html><html><body>Service Unavailable</body></html>'.padEnd(6000, ' ')), 'invalid_audio'],
    ['a JSON error body', () => Buffer.from(JSON.stringify({ error: 'quota exceeded', pad: 'x'.repeat(6000) })), 'invalid_audio'],
    ['a truncated file smaller than any real song', () => wav(0.05), 'invalid_audio'],
    ['random bytes', () => Buffer.alloc(8000, 0x41), 'invalid_audio'],
  ];
  for (const [name, body, code] of cases) {
    it(`rejects ${name}: no song is created, the credit is returned`, async () => {
      const { u, submit } = await setup();
      env.provider.onDownload = async () => body();
      const id = await submit();
      await env.drain();
      const job = await status(u, id);
      assert.equal(job['status'], 'failed');
      assert.equal(job['failureCode'], code);
      assert.equal(job['songId'], null);
      assert.equal(all(env.db, 'SELECT * FROM songs').length, 0);
      assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
      assertLedgerInvariants(env.db);
    });
  }

  it('a "succeeded" poll without an audio URL is an empty result', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => ({ state: 'succeeded', audioUrl: null, durationMs: null, costMicros: null });
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['failureCode'], 'empty_result');
    assert.equal(env.provider.calls.download, 0);
  });

  it('download errors are retried a few times, then fail; a later success completes', async () => {
    const { u, submit } = await setup();
    env.provider.onDownload = failFirst(2, () => providerError('provider_network_error', 'not_started'), async () => wav(3));
    const id = await submit();
    await env.drain();
    assert.equal((await status(u, id))['status'], 'completed');
    assert.equal(env.provider.calls.download, 3);

    const id2 = await submit({ title: 'Second' });
    env.provider.onDownload = async () => { throw providerError('provider_network_error', 'not_started'); };
    await env.drain();
    assert.equal((await status(u, id2))['failureCode'], 'download_failed');
    assertLedgerInvariants(env.db);
  });
});

describe('recovery after a crash or restart', () => {
  it('a job found in "submitting" is failed as outcome-unknown and never resubmitted', async () => {
    const { u, submit } = await setup();
    const id = await submit();
    // The process died after persisting "submitting" and before learning the result.
    run(env.db, `UPDATE jobs SET status = 'submitting', submit_started_at = ?, lease_until = ? WHERE id = ?`,
      env.clock.now().toISOString(), new Date(env.clock.now().getTime() - 1).toISOString(), id);
    env.provider.calls.submit = 0;
    const after = env.restart();
    await after.drain();
    const job = (await after.app.inject({ method: 'GET', url: `/v1/generation/jobs/${id}`, headers: auth(u.token) })).json().job;
    assert.equal(job.status, 'failed');
    assert.equal(job.failureCode, 'submit_outcome_unknown');
    assert.equal(env.provider.calls.submit, 0);
    assertLedgerInvariants(env.db);
    assert.deepEqual((await after.app.inject({ method: 'GET', url: '/v1/credits', headers: auth(u.token) })).json(), { available: 5, held: 0 });
  });

  it('a "processing" job resumes polling after a restart without a second submission', async () => {
    const { u, submit } = await setup();
    env.provider.onPoll = async () => ({ state: 'running' });
    const id = await submit();
    await env.worker.tick(2);
    assert.equal((await status(u, id))['status'], 'processing');
    const submitsBefore = env.provider.calls.submit;

    env.provider.onPoll = async () => ({ state: 'succeeded', audioUrl: 'https://test-double.invalid/a.wav', durationMs: 3000, costMicros: null });
    env.clock.advance(60_000);
    const after = env.restart();
    await after.drain();
    assert.equal((await after.app.inject({ method: 'GET', url: `/v1/generation/jobs/${id}`, headers: auth(u.token) })).json().job.status, 'completed');
    assert.equal(env.provider.calls.submit, submitsBefore);
  });

  it('a "downloading" job resumes from the stored result URL (the provider is not asked again)', async () => {
    const { u, submit } = await setup();
    const id = await submit();
    await env.worker.tick(1); // submit
    run(env.db, `UPDATE jobs SET status = 'downloading', result_json = ?, next_run_at = ? WHERE id = ?`,
      JSON.stringify({ audioUrl: 'https://test-double.invalid/kept.wav', durationMs: 3000, costMicros: null }), env.clock.now().toISOString(), id);
    env.provider.calls.poll = 0;
    const urls: string[] = [];
    env.provider.onDownload = async (url) => { urls.push(url); return wav(3); };
    const after = env.restart();
    await after.drain();
    assert.deepEqual(urls, ['https://test-double.invalid/kept.wav']);
    assert.equal(env.provider.calls.poll, 0);
    assert.equal((await after.app.inject({ method: 'GET', url: `/v1/generation/jobs/${id}`, headers: auth(u.token) })).json().job.status, 'completed');
  });

  it('a live lease stops a second worker from taking the same job', async () => {
    const { submit } = await setup();
    await submit();
    const a = env.worker;
    const b = env.restart().worker; // second worker over the same DB
    env.provider.onSubmit = async (_r, n, signal) => { await new Promise((r) => setTimeout(r, 60)); void signal; return { providerTaskId: `task-${n}` }; };
    await Promise.all([a.tick(1), b.tick(1)]);
    assert.equal(env.provider.calls.submit, 1, 'only one worker may submit the job');
  });

  it('a restarted server keeps users, jobs and songs (persistence)', async () => {
    const { u, submit } = await setup();
    const id = await submit();
    await env.drain();
    const after = env.restart();
    const login = await after.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: u.password } });
    assert.equal(login.statusCode, 200);
    const songs = (await after.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs;
    assert.equal(songs.length, 1);
    assert.equal((await after.app.inject({ method: 'GET', url: `/v1/generation/jobs/${id}`, headers: auth(u.token) })).json().job.status, 'completed');
  });
});

describe('voice no longer usable by the time the job runs', () => {
  it('revoking the voice while a job is queued fails the job before any provider call', async () => {
    const { u, voiceId, submit } = await setup();
    const id = await submit();
    await env.app.inject({ method: 'POST', url: `/v1/voices/${voiceId}/revoke`, headers: auth(u.token) });
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['failureCode'], 'voice_unavailable');
    assert.equal(env.provider.calls.submit, 0);
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
  });
});

describe('unexpected faults inside the worker', () => {
  it('an unexpected exception fails the job safely and returns the credit', async () => {
    const { u, submit } = await setup();
    env.provider.onSubmit = async () => { throw new TypeError('boom'); };
    const id = await submit();
    await env.drain();
    const job = await status(u, id);
    assert.equal(job['status'], 'failed');
    assert.equal(job['failureCode'], 'submit_outcome_unknown');
    assert.deepEqual(await balanceOf(env, u.token), { available: 5, held: 0 });
    assertLedgerInvariants(env.db);
  });
});
