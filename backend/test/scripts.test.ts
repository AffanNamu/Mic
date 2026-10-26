import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, readdirSync } from 'node:fs';
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
