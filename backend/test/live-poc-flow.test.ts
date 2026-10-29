/**
 * Smoke test of scripts/live-poc.ts's ORCHESTRATION (consent → enroll → job → store → retrieve →
 * export → results file) against a LOCAL MOCK that speaks the adapter's ASSUMED Mureka contract.
 *
 * This proves the runner works end to end so a real run does not fail on our own bug. It is not
 * evidence about Mureka: the mock's field names are the adapter's assumptions. The runner itself
 * cannot be pointed at a test double; here the real MurekaProvider talks HTTP to the mock.
 * Takes ~10 s because the worker's real poll delays (3 s, 5 s) apply.
 */
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { wav } from './support/wav.ts';

const root = fileURLToPath(new URL('..', import.meta.url));

describe('live PoC runner, orchestration smoke test against an assumed-contract mock', () => {
  it('runs enroll → generate → store → retrieve → export and records honest results', { timeout: 60_000 }, async () => {
    const dir = mkdtempSync(join(tmpdir(), 'poc-flow-'));
    const seen: Array<{ method: string; url: string; body: string; auth: string | undefined }> = [];
    let polls = 0;
    const song = wav(3, { sampleRate: 16000 });
    const server = createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (c: Buffer) => chunks.push(c));
      req.on('end', () => {
        const url = req.url ?? '';
        const body = Buffer.concat(chunks);
        seen.push({ method: req.method ?? '', url, body: body.toString('latin1'), auth: req.headers.authorization });
        const json = (o: unknown) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
        const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
        if (req.method === 'POST' && url === '/v1/vocal/clone') return json({ vocal_id: 'mock-vocal-1' });
        if (req.method === 'POST' && url === '/v1/song/generate') return json({ id: 'mock-task-1', status: 'preparing' });
        if (req.method === 'GET' && url === '/v1/song/query/mock-task-1') {
          return json(++polls < 2 ? { status: 'running' } : { status: 'succeeded', choices: [{ url: `${base}/files/song.wav`, duration: 3 }] });
        }
        if (req.method === 'GET' && url === '/files/song.wav') { res.writeHead(200, { 'content-type': 'audio/wav' }); return res.end(song); }
        res.writeHead(404); res.end();
      });
    });
    await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
    const base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;

    try {
      const sample = join(dir, 'sample.wav'); writeFileSync(sample, wav(20, { sampleRate: 16000 }));
      const lyrics = join(dir, 'lyrics.txt'); writeFileSync(lyrics, 'SECRET-LYRIC-LINE original words');
      const out = join(dir, 'results');
      const child = spawn('node', ['--disable-warning=ExperimentalWarning', 'scripts/live-poc.ts',
        '--spend', '--consent-accepted', '--participant', 'Test Participant', '--ownership', 'own',
        '--voice-sample', sample, '--lyrics', lyrics, '--language', 'english', '--title', 'Smoke'], {
        cwd: root,
        env: {
          PATH: process.env['PATH'] ?? '',
          BLOB_ENCRYPTION_KEY: Buffer.alloc(32, 5).toString('base64'), MEDIA_SIGNING_KEY: 'm'.repeat(40),
          PROVIDER: 'mureka', MUREKA_API_KEY: 'sk-SMOKE-KEY-123', MUREKA_BASE_URL: base, MUREKA_VOCAL_CLONE_PATH: '/v1/vocal/clone',
          DATABASE_PATH: join(dir, 'db.sqlite'), BLOB_DIR: join(dir, 'blobs'), POC_OUT_DIR: out, POC_ACCOUNT_PASSWORD: 'poc-password-123',
        },
      });
      let stdout = ''; let stderr = '';
      child.stdout.on('data', (d) => { stdout += d; });
      child.stderr.on('data', (d) => { stderr += d; });
      const code = await new Promise<number | null>((r) => child.on('close', r));
      assert.equal(code, 0, `exit ${code}\n${stdout}\n${stderr}`);

      // What was sent to the (mock) provider
      const clone = seen.find((s) => s.url === '/v1/vocal/clone')!;
      assert.equal(clone.auth, 'Bearer sk-SMOKE-KEY-123');
      const gen = seen.find((s) => s.url === '/v1/song/generate')!;
      const genBody = JSON.parse(gen.body) as Record<string, string>;
      assert.equal(genBody['vocal_id'], 'mock-vocal-1');
      assert.match(genBody['lyrics'] ?? '', /SECRET-LYRIC-LINE/);
      assert.equal(seen.filter((s) => s.url === '/v1/song/generate').length, 1, 'exactly one billable submit');
      assert.ok(seen.some((s) => s.url === '/files/song.wav' && s.auth === undefined), 'the API key is not sent to the download host');

      // What the runner reports
      assert.match(stdout, /PASS\s+Voice enrolled/);
      assert.match(stdout, /PASS\s+Song persisted and reopens from the library/);
      assert.match(stdout, /OPEN\s+Human listening evaluation/);
      assert.match(stdout, /OPEN\s+Hausa \/ Arabic listeners/);

      const files = readdirSync(out);
      assert.equal(files.length, 1);
      const raw = readFileSync(join(out, files[0]!), 'utf8');
      const result = JSON.parse(raw) as Record<string, any>;
      assert.equal(result['humanEvaluation'], 'NOT DONE');
      assert.equal(result['job'].status, 'completed');
      assert.equal(Object.values(result['automatedChecks']).every(Boolean), true);
      assert.equal(result['metrics'].cost.voiceEnrollmentMicros, 5_000_000);
      assert.equal(result['documentedLanguage'], true);
      assert.ok(!raw.includes('SECRET-LYRIC-LINE') && !raw.includes('sk-SMOKE-KEY'), 'the results file holds no lyrics and no key');

      // The exported audio exists, is private, and is the provider's bytes
      const exportDir = join(dir, 'poc-exports');
      const exported = readdirSync(exportDir);
      assert.equal(exported.length, 1);
      assert.equal(statSync(join(exportDir, exported[0]!)).mode & 0o077, 0);
      assert.deepEqual(readFileSync(join(exportDir, exported[0]!)), song);
    } finally {
      server.closeAllConnections();
      await new Promise((r) => server.close(r));
      rmSync(dir, { recursive: true, force: true });
    }
  });
});
