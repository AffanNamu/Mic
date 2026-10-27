import { describe, it, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';
import {
  makeEnv, register, auth, grantCredits, submitJob, createVoiceRecord, readyVoice, balanceOf, assertLedgerInvariants,
} from './support/harness.ts';
import type { Env } from './support/harness.ts';
import { all, one } from '../src/db.ts';

let env: Env;
afterEach(async () => { await env?.close(); });

const blobFiles = () => readdirSync(env.blobDir, { recursive: true, withFileTypes: true }).filter((d) => d.isFile()).length;
const del = (token: string, payload: unknown = { password: 'correct horse battery' }) =>
  env.app.inject({ method: 'DELETE', url: '/v1/me', headers: auth(token), payload: payload as Record<string, unknown> });

/** Every row of every table, as text, so a test can assert that something is nowhere in the database. */
function dumpDatabase(): string {
  const tables = all(env.db, `SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'`)
    .map((r) => String(r['name']));
  return tables.map((t) => `${t}: ${JSON.stringify(all(env.db, `SELECT * FROM ${t}`))}`).join('\n');
}

const LYRICS = 'Original lyrics line one\nOriginal lyrics line two';
const SPEAKER = 'Sister Aisha Bello (spoken permission, 2026-10-20)';

/** A person with a ready own voice, an authorized voice, credits and a finished song. */
async function populatedUser(email = 'amina@example.com') {
  const u = await register(env, email);
  await grantCredits(env, email, 5);
  const own = await readyVoice(env, u.token, { displayName: 'Amina’s own voice' });
  const other = await readyVoice(env, u.token, { displayName: 'Sister Aisha', ownership: 'authorized', authorizedBy: SPEAKER });
  // The own-voice song: submit, let the worker finish it.
  const res = await submitJob(env, u.token, { voiceId: own, title: 'Private title', lyrics: LYRICS });
  assert.equal(res.statusCode, 202, res.body);
  await env.drain();
  return { ...u, own, other };
}

describe('deleting an account', () => {
  it('needs a session, and refuses anonymous callers before reading the body', async () => {
    env = makeEnv();
    const res = await env.app.inject({ method: 'DELETE', url: '/v1/me', payload: { password: 'x'.repeat(12) } });
    assert.equal(res.statusCode, 401);
    const bad = await env.app.inject({ method: 'DELETE', url: '/v1/me', payload: 'not even json', headers: { 'content-type': 'application/json' } });
    assert.equal(bad.statusCode, 401, 'authentication comes before validation');
  });

  it('is strict about the body: a password and nothing else', async () => {
    env = makeEnv();
    const u = await register(env);
    for (const payload of [{}, { password: '' }, { password: 5 }, { password: 'x', confirm: true }, { pass: 'x' }]) {
      const res = await del(u.token, payload);
      assert.equal(res.statusCode, 400, JSON.stringify(payload));
    }
    const still = await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(u.token) });
    assert.equal(still.statusCode, 200, 'a refused request deletes nothing');
  });

  it('a wrong password is a 403 (not a 401 that would sign the app out), deletes nothing, and is recorded', async () => {
    env = makeEnv();
    const u = await populatedUser();
    const files = blobFiles();
    const res = await del(u.token, { password: 'not the password' });
    assert.equal(res.statusCode, 403);
    assert.equal(res.json().error.code, 'password_incorrect');
    assert.equal(blobFiles(), files);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs.length, 1);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(u.token) })).statusCode, 200);
    assert.equal(one(env.db, `SELECT COUNT(*) AS n FROM audit_events WHERE kind = 'account.delete_denied'`)?.['n'], 1);
  });

  it('a stolen session cannot guess the password: five tries a minute', async () => {
    env = makeEnv();
    const u = await register(env);
    for (let i = 0; i < 5; i++) assert.equal((await del(u.token, { password: `wrong guess ${i}` })).statusCode, 403);
    const sixth = await del(u.token, { password: 'correct horse battery' });
    assert.equal(sixth.statusCode, 429, 'even the right password is refused while limited');
    env.clock.advance(61_000);
    assert.equal((await del(u.token)).statusCode, 200);
  });

  it('refuses while a song is being made, and deletes nothing', async () => {
    env = makeEnv();
    const u = await register(env);
    await grantCredits(env, u.email, 3);
    const voiceId = await readyVoice(env, u.token);
    const res = await submitJob(env, u.token, { voiceId, lyrics: LYRICS });
    assert.equal(res.statusCode, 202, res.body);
    const out = await del(u.token);
    assert.equal(out.statusCode, 409);
    assert.equal(out.json().error.code, 'account_busy');
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(u.token) })).statusCode, 200);
    // Once it has finished the account can go.
    await env.drain();
    assert.equal((await del(u.token)).statusCode, 200);
  });

  it('removes recordings and songs from storage, ends every session, and says what it did', async () => {
    env = makeEnv();
    const u = await populatedUser();
    assert.ok(blobFiles() >= 3, 'two recordings and a song are stored');
    const second = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: u.password } });
    assert.equal(second.statusCode, 200);

    const res = await del(u.token);
    assert.equal(res.statusCode, 200, res.body);
    const body = res.json();
    assert.equal(body.deleted, true);
    assert.equal(body.voicesDeleted, 2);
    assert.equal(body.songsDeleted, 1);
    assert.equal(blobFiles(), 0, 'nothing of theirs is left in private storage');
    for (const token of [u.token, second.json().token as string]) {
      assert.equal((await env.app.inject({ method: 'GET', url: '/v1/me', headers: auth(token) })).statusCode, 401);
    }
    const login = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: u.email, password: u.password } });
    assert.equal(login.statusCode, 401, 'the old email and password no longer sign in');
    assert.match(body.disclosure, /Your account, recordings, songs and lyrics were deleted/);
  });

  it('leaves no email, name, lyrics, title, IP or device details anywhere in the database', async () => {
    env = makeEnv();
    const u = await populatedUser();
    // A different person's data must survive, so the scan below cannot pass by deleting everything.
    const keeper = await populatedUser('keeper@example.com');

    const before = dumpDatabase();
    for (const needle of [u.email, LYRICS.split('\n')[0]!, 'Private title', SPEAKER, 'Amina’s own voice']) {
      assert.ok(before.includes(needle), `test setup: ${needle} should exist before deletion`);
    }
    assert.equal((await del(u.token)).statusCode, 200);

    // Strip the other person's rows, then scan what is left for this person's data.
    const dump = dumpDatabase();
    const mine = all(env.db, `SELECT * FROM users WHERE id = ?`, u.userId)[0]!;
    assert.match(String(mine['email']), /^deleted-.+@deleted\.invalid$/);
    assert.equal(mine['password_hash'], '!');
    assert.ok(mine['deleted_at'] && mine['disabled_at']);
    const theirRows = (sql: string) => all(env.db, sql, u.userId);
    const text = [
      ...theirRows('SELECT * FROM users WHERE id = ?'), ...theirRows('SELECT * FROM voices WHERE user_id = ?'),
      ...theirRows('SELECT * FROM consents WHERE user_id = ?'), ...theirRows('SELECT * FROM jobs WHERE user_id = ?'),
      ...theirRows('SELECT * FROM songs WHERE user_id = ?'), ...theirRows('SELECT * FROM sessions WHERE user_id = ?'),
      ...theirRows('SELECT * FROM audit_events WHERE user_id = ?'), ...theirRows('SELECT * FROM credit_ledger WHERE user_id = ?'),
    ].map((r) => JSON.stringify(r)).join('\n');
    for (const needle of [
      u.email, 'amina', 'Original lyrics', 'Private title', 'Sister Aisha', 'Aisha Bello', 'Amina’s own voice',
      '127.0.0.1', 'light-my-request',
    ]) {
      assert.ok(!text.includes(needle), `${needle} is still in the database after deletion`);
    }
    assert.equal(theirRows('SELECT * FROM sessions WHERE user_id = ?').length, 0);
    assert.ok(dump.includes('keeper@example.com'), 'someone else\'s account is untouched');
    assert.ok(dump.includes(LYRICS.split('\n')[0]!), 'and so are their songs');
    void keeper;
  });

  it('keeps what accountability needs, without personal details', async () => {
    env = makeEnv();
    const u = await populatedUser();
    const consentBefore = all(env.db, `SELECT statement_version, statement_sha256, accepted_at FROM consents WHERE user_id = ? ORDER BY id`, u.userId);
    const ledgerBefore = all(env.db, `SELECT kind, amount, job_id FROM credit_ledger WHERE user_id = ? ORDER BY id`, u.userId);
    assert.ok(consentBefore.length === 2 && ledgerBefore.length >= 2);

    const res = await del(u.token);
    assert.equal(res.statusCode, 200);
    assert.deepEqual(all(env.db, `SELECT statement_version, statement_sha256, accepted_at FROM consents WHERE user_id = ? ORDER BY id`, u.userId), consentBefore);
    assert.deepEqual(all(env.db, `SELECT kind, amount, job_id FROM credit_ledger WHERE user_id = ? ORDER BY id`, u.userId), ledgerBefore);
    const consent = all(env.db, `SELECT * FROM consents WHERE user_id = ?`, u.userId);
    assert.ok(consent.every((c) => c['ip'] === null && c['user_agent'] === null && c['authorized_by'] === null && c['revoked_at']));
    assert.equal(res.json().kept.length, 3, 'the response says what is kept');
    assertLedgerInvariants(env.db);
    assert.equal(one(env.db, `SELECT COUNT(*) AS n FROM audit_events WHERE kind = 'account.deleted'`)?.['n'], 1);
  });

  it('asks the provider to delete each voice, and reports the worst outcome truthfully', async () => {
    env = makeEnv();
    const u = await populatedUser();
    let calls = 0;
    env.provider.onDelete = async () => (++calls === 1 ? 'deleted' : 'unsupported');
    const res = await del(u.token);
    assert.equal(res.statusCode, 200);
    assert.equal(calls, 2, 'both voices were offered to the provider for deletion');
    assert.equal(res.json().providerDeletion, 'unsupported');
    assert.match(res.json().disclosure, /could not delete its copy of your voice recordings/);
  });

  it('a provider failure does not stop the deletion, and is reported as failed', async () => {
    env = makeEnv();
    const u = await populatedUser();
    env.provider.onDelete = async () => { throw new Error('provider is down'); };
    const res = await del(u.token);
    assert.equal(res.statusCode, 200);
    assert.equal(res.json().providerDeletion, 'failed');
    assert.equal(blobFiles(), 0);
    assert.match(res.json().disclosure, /could not delete its copy/);
  });

  it('says nothing about a provider when none ever held a recording', async () => {
    env = makeEnv();
    const u = await register(env);
    await createVoiceRecord(env, u.token); // consent recorded, no audio ever uploaded
    const res = await del(u.token);
    assert.equal(res.json().providerDeletion, 'not_applicable');
    assert.doesNotMatch(res.json().disclosure, /provider/);
    assert.equal(res.json().voicesDeleted, 1);
  });

  it('the same email can start again with nothing carried over', async () => {
    env = makeEnv();
    const u = await populatedUser();
    assert.equal((await del(u.token)).statusCode, 200);
    const again = await register(env, u.email, 'a different long password');
    assert.notEqual(again.userId, u.userId);
    assert.equal((await balanceOf(env, again.token)).available, 0);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(again.token) })).json().songs.length, 0);
    assert.equal((await env.app.inject({ method: 'GET', url: '/v1/voices', headers: auth(again.token) })).json().voices.length, 0);
  });

  it('cannot be done twice, and a deleted account cannot be signed back into', async () => {
    env = makeEnv();
    const u = await register(env);
    assert.equal((await del(u.token)).statusCode, 200);
    assert.equal((await del(u.token)).statusCode, 401);
    // The anonymised row cannot be reached by guessing its placeholder email either.
    const guess = await env.app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: `deleted-${u.userId}@deleted.invalid`, password: '!' + '!'.repeat(10) } });
    assert.equal(guess.statusCode, 401);
  });

  it('deleting one song, or one voice with its songs, also forgets the voice\'s name', async () => {
    env = makeEnv();
    const u = await populatedUser();
    const songs = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs as Array<{ id: string; voiceName: string }>;
    assert.equal(songs[0]!.voiceName, 'Amina’s own voice');
    assert.equal((await env.app.inject({ method: 'DELETE', url: `/v1/songs/${songs[0]!.id}`, headers: auth(u.token) })).statusCode, 204);
    assert.equal(one(env.db, 'SELECT voice_name FROM songs WHERE id = ?', songs[0]!.id)?.['voice_name'], null);

    // And a voice deleted together with the songs made with it.
    await submitJob(env, u.token, { voiceId: u.own, title: 'Second', lyrics: LYRICS });
    await env.drain();
    const again = await env.app.inject({ method: 'DELETE', url: `/v1/voices/${u.own}?deleteSongs=true`, headers: auth(u.token) });
    assert.equal(again.statusCode, 200, again.body);
    assert.equal(all(env.db, `SELECT voice_name FROM songs WHERE user_id = ? AND voice_name IS NOT NULL`, u.userId).length, 0);
  });

  it('also scrubs songs deleted before this code existed (rows that still carry a voice name)', async () => {
    env = makeEnv();
    const u = await populatedUser();
    const songs = (await env.app.inject({ method: 'GET', url: '/v1/songs', headers: auth(u.token) })).json().songs as Array<{ id: string }>;
    await env.app.inject({ method: 'DELETE', url: `/v1/songs/${songs[0]!.id}`, headers: auth(u.token) });
    env.db.prepare(`UPDATE songs SET voice_name = 'Legacy voice name' WHERE id = ?`).run(songs[0]!.id);
    assert.equal((await del(u.token)).statusCode, 200);
    assert.equal(one(env.db, 'SELECT voice_name FROM songs WHERE id = ?', songs[0]!.id)?.['voice_name'], null);
  });

  it('the schema change is a new migration, not an edit to the first', () => {
    env = makeEnv();
    const versions = all(env.db, 'SELECT version FROM schema_migrations ORDER BY version').map((r) => String(r['version']));
    assert.deepEqual(versions, ['0001_init', '0002_account_deletion']);
  });
});
