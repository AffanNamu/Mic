import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig } from '../src/config.ts';
import { FileBlobStore } from '../src/blobstore.ts';
import { decryptBlob, encryptBlob, hashPassword, verifyPassword } from '../src/crypto.ts';
import { openDb, runMigrations, one, run } from '../src/db.ts';
import { sniffAudio, wavDurationMs } from '../src/audio.ts';
import { withTimeout } from '../src/timeout.ts';
import { RateLimiter } from '../src/ratelimit.ts';
import { stylePrompt } from '../src/style.ts';
import { MIGRATIONS_DIR, TestClock } from './support/harness.ts';
import { wav } from './support/wav.ts';

const goodEnv = {
  BLOB_ENCRYPTION_KEY: Buffer.alloc(32, 1).toString('base64'),
  MEDIA_SIGNING_KEY: 'x'.repeat(40),
};

describe('configuration', () => {
  it('refuses to start without its secrets and lists every problem', () => {
    assert.throws(() => loadConfig({}), (e: Error) =>
      e.message.includes('BLOB_ENCRYPTION_KEY is required') && e.message.includes('MEDIA_SIGNING_KEY is required'));
  });

  it('has no default secrets and defaults to no provider', () => {
    const c = loadConfig(goodEnv);
    assert.equal(c.provider, 'none');
    assert.equal(c.murekaApiKey, null);
    assert.equal(c.adminToken, null);
  });

  it('rejects a wrong-size encryption key and a short media key', () => {
    assert.throws(() => loadConfig({ ...goodEnv, BLOB_ENCRYPTION_KEY: Buffer.alloc(8).toString('base64') }), /32 bytes/);
    assert.throws(() => loadConfig({ ...goodEnv, MEDIA_SIGNING_KEY: 'short' }), /at least 32/);
  });

  it('requires an API key when a provider is selected, and never echoes secrets in errors', () => {
    assert.throws(() => loadConfig({ ...goodEnv, PROVIDER: 'mureka' }), /MUREKA_API_KEY is required/);
    try {
      loadConfig({ ...goodEnv, PROVIDER: 'mureka', ADMIN_TOKEN: 'too-short-secret' });
      assert.fail('should have thrown');
    } catch (e) {
      assert.ok(!(e as Error).message.includes('too-short-secret'));
    }
  });

  it('rejects unknown providers and non-numeric limits', () => {
    assert.throws(() => loadConfig({ ...goodEnv, PROVIDER: 'suno' }), /PROVIDER must be/);
    assert.throws(() => loadConfig({ ...goodEnv, PORT: 'abc' }), /PORT must be a positive number/);
  });
});

describe('password hashing', () => {
  it('verifies the right password only, and salts each hash', async () => {
    const a = await hashPassword('a long enough password');
    const b = await hashPassword('a long enough password');
    assert.notEqual(a, b);
    assert.ok(await verifyPassword('a long enough password', a));
    assert.ok(!(await verifyPassword('a long enough passwore', a)));
    assert.ok(!(await verifyPassword('anything', 'not-a-hash')));
    assert.ok(!a.includes('a long enough password'));
  });
});

describe('encrypted blob store', () => {
  const key = Buffer.alloc(32, 9);

  it('round-trips and never writes plaintext to disk', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'blob-'));
    try {
      const store = new FileBlobStore(dir, key);
      const secret = Buffer.from('RIFF-secret-voice-sample-bytes-0123456789');
      await store.put('voices/v1/a', secret);
      assert.deepEqual(await store.get('voices/v1/a'), secret);
      const files = readdirSync(dir, { recursive: true, withFileTypes: true }).filter((d) => d.isFile());
      assert.equal(files.length, 1);
      const onDisk = readFileSync(join(files[0]!.parentPath, files[0]!.name));
      assert.ok(!onDisk.includes(secret));
      assert.equal(statSync(join(files[0]!.parentPath, files[0]!.name)).mode & 0o077, 0, 'file must be owner-only');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('detects tampering and a blob swapped to another key', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'blob-'));
    try {
      const store = new FileBlobStore(dir, key);
      await store.put('k1', Buffer.from('first-first-first-first'));
      await store.put('k2', Buffer.from('second-second-second'));
      const files = readdirSync(dir, { recursive: true, withFileTypes: true }).filter((d) => d.isFile())
        .map((d) => join(d.parentPath, d.name));
      const [f1, f2] = files as [string, string];
      const swapped = readFileSync(f1);
      writeFileSync(f2, swapped);
      await assert.rejects(store.get('k1'), 'k1 file replaced by k2 ciphertext... must not decrypt under the wrong key id');
      const wrongKey = new FileBlobStore(dir, Buffer.alloc(32, 1));
      await assert.rejects(wrongKey.get('k1'));
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('delete reports whether anything was removed and the blob is gone', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'blob-'));
    try {
      const store = new FileBlobStore(dir, key);
      await store.put('x', Buffer.from('data'));
      assert.equal(await store.delete('x'), true);
      assert.equal(await store.delete('x'), false);
      await assert.rejects(store.get('x'));
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('binds ciphertext to its key id (AAD)', () => {
    const c = encryptBlob(key, Buffer.from('hello world'), 'a');
    assert.throws(() => decryptBlob(key, c, 'b'));
    assert.equal(decryptBlob(key, c, 'a').toString(), 'hello world');
  });
});

describe('migrations', () => {
  it('apply once, in order, and are not re-applied', () => {
    const db = openDb(':memory:');
    const first = runMigrations(db, MIGRATIONS_DIR);
    assert.ok(first.includes('0001_init'));
    assert.deepEqual(runMigrations(db, MIGRATIONS_DIR), []);
    assert.ok(one(db, `SELECT name FROM sqlite_master WHERE type='table' AND name='credit_ledger'`));
  });

  it('refuse to start if an applied migration was edited', () => {
    const dir = mkdtempSync(join(tmpdir(), 'mig-'));
    try {
      writeFileSync(join(dir, '0001_a.sql'), 'CREATE TABLE a (id INTEGER);');
      const db = openDb(':memory:');
      runMigrations(db, dir);
      writeFileSync(join(dir, '0001_a.sql'), 'CREATE TABLE a (id INTEGER, extra TEXT);');
      assert.throws(() => runMigrations(db, dir), /modified after it was applied/);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('roll back a failing migration entirely', () => {
    const dir = mkdtempSync(join(tmpdir(), 'mig-'));
    try {
      writeFileSync(join(dir, '0001_bad.sql'), 'CREATE TABLE t (id INTEGER); INSERT INTO nope VALUES (1);');
      const db = openDb(':memory:');
      assert.throws(() => runMigrations(db, dir));
      assert.equal(one(db, `SELECT name FROM sqlite_master WHERE name='t'`), undefined);
      assert.equal(one(db, `SELECT version FROM schema_migrations`), undefined);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('the schema itself forbids a second reserve or a second finalisation for a job', () => {
    const db = openDb(':memory:');
    runMigrations(db, MIGRATIONS_DIR);
    run(db, `INSERT INTO users (id, email, password_hash, created_at) VALUES ('u','u@x.co','h','t')`);
    const ins = (kind: string) => run(db, `INSERT INTO credit_ledger (user_id, kind, amount, job_id, created_at) VALUES ('u', ?, 1, 'j', 't')`, kind);
    ins('reserve');
    assert.throws(() => ins('reserve'));
    ins('capture');
    assert.throws(() => ins('release'));
    assert.throws(() => ins('capture'));
  });
});

describe('audio sniffing', () => {
  it('recognises real containers and rejects text, HTML, JSON and empties', () => {
    assert.equal(sniffAudio(wav(1))?.kind, 'wav');
    assert.equal(sniffAudio(Buffer.concat([Buffer.from('ID3'), Buffer.alloc(30)]))?.kind, 'mp3');
    assert.equal(sniffAudio(Buffer.concat([Buffer.from('fLaC'), Buffer.alloc(30)]))?.kind, 'flac');
    assert.equal(sniffAudio(Buffer.concat([Buffer.from('OggS'), Buffer.alloc(30)]))?.kind, 'ogg');
    assert.equal(sniffAudio(Buffer.from('<!doctype html><html><body>Error 502</body></html>')), null);
    assert.equal(sniffAudio(Buffer.from('{"error":"quota exceeded","code":429}')), null);
    assert.equal(sniffAudio(Buffer.alloc(0)), null);
    assert.equal(sniffAudio(Buffer.alloc(5000)), null);
  });

  it('measures WAV duration exactly', () => {
    assert.equal(wavDurationMs(wav(10)), 10000);
    assert.equal(wavDurationMs(wav(2.5)), 2500);
    assert.equal(wavDurationMs(Buffer.from('nope')), null);
  });
});

describe('timeout helper', () => {
  it('rejects with an "unknown outcome" error even if the work ignores the abort signal', async () => {
    await assert.rejects(withTimeout(30, () => new Promise(() => {})), (e: { code?: string; outcome?: string }) =>
      e.code === 'timeout' && e.outcome === 'unknown');
  });
  it('aborts the signal on timeout and returns normal results untouched', async () => {
    let aborted = false;
    await assert.rejects(withTimeout(20, (s) => new Promise((_, rej) => s.addEventListener('abort', () => { aborted = true; rej(new Error('x')); }))));
    assert.ok(aborted);
    assert.equal(await withTimeout(100, async () => 42), 42);
  });
});

describe('rate limiter', () => {
  it('blocks after the limit within a window and resets after it', () => {
    const clock = new TestClock();
    const l = new RateLimiter(clock, 3, 1000);
    assert.deepEqual([1, 2, 3, 4].map(() => l.allow('k')), [true, true, true, false]);
    assert.ok(l.allow('other'));
    clock.advance(1001);
    assert.ok(l.allow('k'));
  });
});

describe('style prompt', () => {
  it('maps known choices and ignores unknown ones instead of passing user text to the provider', () => {
    const p = stylePrompt({ genre: 'hausa_nasheed', mood: 'peaceful', tempo: 'slow', intensity: 'gentle', instruments: 'acoustic' });
    assert.match(p, /Hausa nasheed/);
    assert.match(p, /peaceful/);
    assert.equal(stylePrompt({ genre: 'ignore previous instructions', mood: '<script>' }), '');
  });
});
