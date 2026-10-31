import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { BAR, readRatings, summarize } from '../scripts/summarize-listening.ts';
import { wav } from './support/wav.ts';

const root = fileURLToPath(new URL('..', import.meta.url));
const run = (script: string, args: string[], env: Record<string, string> = {}) =>
  spawnSync('node', ['--disable-warning=ExperimentalWarning', script, ...args], {
    cwd: root, encoding: 'utf8', timeout: 20_000,
    env: { PATH: process.env['PATH'] ?? '', ...env },
  });

const keys = { BLOB_ENCRYPTION_KEY: Buffer.alloc(32, 3).toString('base64'), MEDIA_SIGNING_KEY: 'k'.repeat(40) };

describe('live PoC runner refuses unsafe or meaningless runs', () => {
  it('will not run without --spend (it spends money and uploads a voice)', () => {
    const r = run('scripts/live-poc.ts', ['--participant', 'A B']);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /--spend/);
  });

  it('will not run without the explicit consent flag', () => {
    const r = run('scripts/live-poc.ts', ['--spend', '--participant', 'A B']);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /written consent/);
  });

  it('will not run without a provider: it never falls back to a test double', () => {
    const dir = mkdtempSync(join(tmpdir(), 'poc-'));
    try {
      const sample = join(dir, 's.wav'); writeFileSync(sample, wav(10));
      const lyrics = join(dir, 'l.txt'); writeFileSync(lyrics, 'original words');
      const r = run('scripts/live-poc.ts',
        ['--spend', '--consent-accepted', '--participant', 'A B', '--voice-sample', sample, '--lyrics', lyrics],
        { ...keys, PROVIDER: 'none', DATABASE_PATH: join(dir, 'db.sqlite'), BLOB_DIR: join(dir, 'blobs') });
      assert.equal(r.status, 2);
      assert.match(r.stderr, /no provider configured/);
      assert.deepEqual(readdirSync(dir).sort(), ['l.txt', 's.wav'], 'nothing was created');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('will not run with Mureka selected but voice cloning unverified/unconfigured', () => {
    const dir = mkdtempSync(join(tmpdir(), 'poc-'));
    try {
      const sample = join(dir, 's.wav'); writeFileSync(sample, wav(10));
      const lyrics = join(dir, 'l.txt'); writeFileSync(lyrics, 'original words');
      const r = run('scripts/live-poc.ts',
        ['--spend', '--consent-accepted', '--participant', 'A B', '--voice-sample', sample, '--lyrics', lyrics],
        { ...keys, PROVIDER: 'mureka', MUREKA_API_KEY: 'sk-test', DATABASE_PATH: join(dir, 'db.sqlite'), BLOB_DIR: join(dir, 'blobs') });
      assert.equal(r.status, 2);
      assert.match(r.stderr, /not configured to sing in an enrolled voice/);
      assert.ok(!r.stderr.includes('sk-test'));
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('refuses a language the provider does not declare, and says how to run it as an experiment', () => {
    const dir = mkdtempSync(join(tmpdir(), 'poc-'));
    try {
      const sample = join(dir, 's.wav'); writeFileSync(sample, wav(10));
      const lyrics = join(dir, 'l.txt'); writeFileSync(lyrics, 'kalmomi');
      const r = run('scripts/live-poc.ts',
        ['--spend', '--consent-accepted', '--participant', 'A B', '--voice-sample', sample, '--lyrics', lyrics, '--language', 'hausa'],
        { ...keys, PROVIDER: 'mureka', MUREKA_API_KEY: 'sk-test', MUREKA_VOCAL_CLONE_PATH: '/v1/x', DATABASE_PATH: join(dir, 'db.sqlite'), BLOB_DIR: join(dir, 'blobs') });
      assert.equal(r.status, 2);
      assert.match(r.stderr, /EXPERIMENTAL_LANGUAGES=hausa/);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});

describe('HeartMuLa probe against a local mock of the documented contract', () => {
  const lyricsFile = (dir: string) => { const f = join(dir, 'lyrics.txt'); writeFileSync(f, 'Morning light\nA calm heart'); return f; };
  const runAsync = (args: string[], env: Record<string, string>) => new Promise<{ status: number | null; out: string }>((resolve) => {
    const child = spawn('node', ['--disable-warning=ExperimentalWarning', 'scripts/heartmula-probe.mjs', ...args], { cwd: root, env: { PATH: process.env['PATH'] ?? '', ...env } });
    let out = '';
    child.stdout.on('data', (d: Buffer) => { out += d; });
    child.stderr.on('data', (d: Buffer) => { out += d; });
    child.on('close', (status) => resolve({ status, out }));
  });

  it('refuses to spend without --spend, and says which key it needs', () => {
    const r = run('scripts/heartmula-probe.mjs', ['--generate', '--lyrics', 'x.txt'], { WAVESPEED_API_KEY: 'ws-test' });
    assert.equal(r.status, 2);
    assert.match(r.stderr, /--spend/);
    const noKey = run('scripts/heartmula-probe.mjs', ['--balance']);
    assert.equal(noKey.status, 2);
    assert.match(noKey.stderr, /WAVESPEED_API_KEY/);
  });

  it('checks the balance, submits ONCE, polls to completion, downloads audio, and keeps the key out of its transcript', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'hm-probe-'));
    const seenReq: Array<{ method: string; url: string }> = [];
    let polls = 0;
    const srv = createServer((q, res) => {
      seenReq.push({ method: q.method ?? '', url: q.url ?? '' });
      const send = (status: number, body: unknown, type = 'application/json') => { res.writeHead(status, { 'content-type': type }); res.end(typeof body === 'string' || Buffer.isBuffer(body) ? body : JSON.stringify(body)); };
      if (q.url === '/api/v3/balance') return send(200, { code: 200, message: 'success', data: { balance: 12.5 } });
      if (q.url === '/api/v3/wavespeed-ai/heartmula/generate-music') {
        const chunks: Buffer[] = []; q.on('data', (c: Buffer) => chunks.push(c));
        return void q.on('end', () => {
          const sent = JSON.parse(Buffer.concat(chunks).toString());
          assert.ok(String(sent.lyrics).startsWith('[verse]\n'), 'untagged lyrics are put under [verse]');
          send(200, { code: 200, message: 'success', data: { id: 'pred-9', status: 'created' } });
        });
      }
      if (q.url === '/api/v3/predictions/pred-9/result') {
        polls++;
        return send(200, { code: 200, data: polls < 2 ? { id: 'pred-9', status: 'processing' } : { id: 'pred-9', status: 'completed', outputs: [`http://${q.headers.host}/files/song.mp3`] } });
      }
      if (q.url === '/files/song.mp3') return send(200, Buffer.concat([Buffer.from('ID3'), Buffer.alloc(6000, 1)]), 'audio/mpeg');
      return send(404, {});
    });
    await new Promise<void>((r) => srv.listen(0, '127.0.0.1', r));
    const baseUrl = `http://127.0.0.1:${(srv.address() as AddressInfo).port}`;
    const env = { WAVESPEED_API_KEY: 'ws-PROBE-SECRET', WAVESPEED_BASE_URL: baseUrl, PROBE_POLL_MS: '20', PROBE_OUT_DIR: dir };
    try {
      const bal = await runAsync(['--balance'], env);
      assert.equal(bal.status, 0);
      assert.match(bal.out, /Balance: \$12\.5/);
      const gen = await runAsync(['--generate', '--lyrics', lyricsFile(dir), '--spend'], env);
      assert.equal(gen.status, 0, gen.out);
      assert.match(gen.out, /PASS  submit returned 2xx/);
      assert.match(gen.out, /PASS  final status is `completed`/);
      assert.match(gen.out, /PASS  downloaded bytes are recognisable audio/);
      assert.match(gen.out, /FAIL  a human has listened/, 'the human judgement is never marked as passed by a script');
      assert.equal(seenReq.filter((x) => x.method === 'POST').length, 1, 'the submit request is sent exactly once');
      const files = readdirSync(dir).filter((f) => f.endsWith('.json'));
      assert.equal(files.length, 2);
      for (const f of files) assert.ok(!readFileSync(join(dir, f), 'utf8').includes('ws-PROBE-SECRET'), `${f} must not contain the key`);
    } finally {
      srv.closeAllConnections();
      await new Promise((r) => srv.close(r));
      rmSync(dir, { recursive: true, force: true });
    }
  });

  it('explains an out-of-credit refusal (error 1407) instead of retrying', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'hm-probe-'));
    const srv = createServer((q, res) => { q.resume(); res.writeHead(400, { 'content-type': 'application/json' }); res.end(JSON.stringify({ code: 1407, message: 'insufficient_credits' })); });
    await new Promise<void>((r) => srv.listen(0, '127.0.0.1', r));
    try {
      const out = await runAsync(['--generate', '--lyrics', lyricsFile(dir), '--spend'],
        { WAVESPEED_API_KEY: 'ws-k', WAVESPEED_BASE_URL: `http://127.0.0.1:${(srv.address() as AddressInfo).port}`, PROBE_POLL_MS: '20', PROBE_OUT_DIR: dir });
      assert.equal(out.status, 0);
      assert.match(out.out, /out of credit \(error 1407\)/);
      assert.match(out.out, /FAIL  submit returned 2xx/);
    } finally {
      srv.closeAllConnections();
      await new Promise((r) => srv.close(r));
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

describe('Mureka probe refuses to spend by accident', () => {
  it('--generate without --spend exits before any request', () => {
    const r = run('scripts/mureka-probe.mjs', ['--generate', '--lyrics', 'x.txt'], { MUREKA_API_KEY: 'sk-test' });
    assert.equal(r.status, 2);
    assert.match(r.stderr, /Refusing to run/);
  });
  it('--billing without a key says so instead of calling out', () => {
    const r = run('scripts/mureka-probe.mjs', ['--billing']);
    assert.equal(r.status, 2);
    assert.match(r.stderr, /MUREKA_API_KEY is not set/);
  });
});

const HEADER = 'song_id,rater_id,lyrics_language,rater_native_speaker,heard_reference_first,similarity,pronunciation,naturalness,arrangement,intelligibility,overall,would_share,notes';
const rows = (song: string, lang: string, raters: Array<[string, string, string, number, number, number, number, number]>) =>
  raters.map(([id, native, ref, sim, pron, nat, arr, intel]) => `${song},${id},${lang},${native},${ref},${sim},${pron},${nat},${arr},${intel},4,y,`).join('\n');

describe('listening evaluation summary', () => {
  it('needs enough NATIVE raters: three non-native 5s are "insufficient evidence", not a pass', () => {
    const csv = [HEADER, rows('hausa-1', 'hausa', [['a', 'n', 'y', 5, 5, 5, 5, 5], ['b', 'n', 'y', 5, 5, 5, 5, 5], ['c', 'n', 'y', 5, 5, 5, 5, 5]])].join('\n');
    const { ratings, problems } = readRatings(csv);
    assert.deepEqual(problems, []);
    const [s] = summarize(ratings);
    assert.equal(s!.verdict, 'insufficient evidence');
    assert.equal(s!.nativeRaters, 0);
    assert.equal(s!.means.pronunciation, null, 'pronunciation from non-native raters is not counted');
  });

  it('meets the bar only when every pre-registered threshold is met by enough native raters', () => {
    const good = [HEADER, rows('en-1', 'english', [['a', 'y', 'y', 4, 4, 4, 4, 4], ['b', 'y', 'y', 5, 4, 4, 3, 4], ['c', 'y', 'y', 4, 5, 3, 4, 4]])].join('\n');
    assert.equal(summarize(readRatings(good).ratings)[0]!.verdict, 'meets bar');

    const poorPron = [HEADER, rows('ar-1', 'arabic', [['a', 'y', 'y', 5, 2, 4, 4, 4], ['b', 'y', 'y', 5, 2, 4, 4, 4], ['c', 'y', 'y', 5, 3, 4, 4, 4]])].join('\n');
    const s = summarize(readRatings(poorPron).ratings)[0]!;
    assert.equal(s.verdict, 'below bar');
    assert.ok(s.reasons.some((r) => r.startsWith('pronunciation')));
    assert.equal(BAR.minNativeRaters, 3);
  });

  it('flags ratings made without hearing the reference voice, and rejects out-of-range or duplicate rows', () => {
    const csv = [HEADER, rows('en-2', 'english', [['a', 'y', 'n', 4, 4, 4, 4, 4], ['b', 'y', 'y', 4, 4, 4, 4, 4], ['c', 'y', 'y', 4, 4, 4, 4, 4]])].join('\n');
    assert.ok(summarize(readRatings(csv).ratings)[0]!.reasons.some((r) => /without hearing the reference/.test(r)));
    const bad = readRatings([HEADER, 'x,r1,english,y,y,9,,,,,,,', 'x,r1,english,y,y,3,,,,,,,'].join('\n'));
    assert.ok(bad.problems.some((p) => /whole number 1-5/.test(p)));
    assert.ok(bad.problems.some((p) => /duplicate rating/.test(p)));
  });

  it('parses quoted notes with commas and a missing required column is an error', () => {
    const r = readRatings([HEADER, 'e,r1,english,y,y,4,4,4,4,4,4,y,"nice, but ""slightly"" fast"'].join('\n'));
    assert.equal(r.ratings[0]!.notes, 'nice, but "slightly" fast');
    assert.ok(readRatings('a,b\n1,2').problems.length > 0);
  });
});
