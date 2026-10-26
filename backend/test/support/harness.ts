import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../../src/http.ts';
import { openDb, runMigrations, all, one } from '../../src/db.ts';
import type { Db } from '../../src/db.ts';
import type { Clock } from '../../src/clock.ts';
import { FileBlobStore } from '../../src/blobstore.ts';
import { ProviderHealth } from '../../src/deps.ts';
import type { Deps, Logger } from '../../src/deps.ts';
import type { Config } from '../../src/config.ts';
import { JobWorker } from '../../src/worker.ts';
import type { WorkerTimeouts } from '../../src/worker.ts';
import type { MusicProvider } from '../../src/provider/types.ts';
import { ScriptedProvider } from './scripted-provider.ts';
import { wav } from './wav.ts';

export const MIGRATIONS_DIR = fileURLToPath(new URL('../../migrations', import.meta.url));
export const ADMIN_TOKEN = 'test-admin-token-0123456789abcdef';
export const MEDIA_KEY = 'test-media-signing-key-0123456789abcdef0123';

export class TestClock implements Clock {
  private ms: number;
  constructor(startIso = '2026-10-26T09:00:00.000Z') {
    this.ms = Date.parse(startIso);
  }
  now(): Date { return new Date(this.ms); }
  advance(ms: number): void { this.ms += ms; }
}

export function testConfig(overrides: Partial<Config> = {}): Config {
  return {
    host: '127.0.0.1', port: 0, databasePath: ':memory:', blobDir: '',
    blobKey: Buffer.alloc(32, 7), mediaKey: Buffer.from(MEDIA_KEY),
    adminToken: ADMIN_TOKEN, corsOrigins: [],
    provider: 'none', murekaApiKey: null, murekaBaseUrl: 'https://api.mureka.ai',
    mureka: { model: 'auto', vocalClonePath: null, songCostMicros: 45_000, enrollCostMicros: 5_000_000, audioHosts: [] },
    experimentalLanguages: [],
    maxVoiceBytes: 2 * 1024 * 1024, maxLyricsChars: 3000,
    sessionTtlMs: 30 * 86_400_000, jobDeadlineMs: 20 * 60_000, leaseMs: 60_000,
    credits: { perSong: 1 },
    ...overrides,
  };
}

export interface Env {
  deps: Deps;
  db: Db;
  app: FastifyInstance;
  worker: JobWorker;
  clock: TestClock;
  provider: ScriptedProvider;
  config: Config;
  blobDir: string;
  logs: string[];
  /** Runs the worker until nothing is left to do, advancing the clock between rounds. */
  drain(opts?: { stepMs?: number; maxRounds?: number }): Promise<void>;
  /** Simulates a process restart: a new app + worker over the same database and blob store. */
  restart(provider?: MusicProvider): Env;
  close(): Promise<void>;
}

export interface EnvOptions {
  provider?: MusicProvider;
  config?: Partial<Config>;
  timeouts?: Partial<WorkerTimeouts>;
  /** Reuse an existing database, blob directory and clock (restart simulation). */
  reuse?: { db: Db; blobDir: string; clock: TestClock; logs: string[] };
}

export function makeEnv(options: EnvOptions = {}): Env {
  const clock = options.reuse?.clock ?? new TestClock();
  const blobDir = options.reuse?.blobDir ?? mkdtempSync(join(tmpdir(), 'deenvoice-test-'));
  const db = options.reuse?.db ?? openDb(':memory:');
  if (!options.reuse) runMigrations(db, MIGRATIONS_DIR, () => clock.now());
  const logs = options.reuse?.logs ?? [];
  const capture = (level: string) => (o: Record<string, unknown>, m?: string) => { logs.push(JSON.stringify({ level, msg: m, ...o })); };
  const log: Logger = { info: capture('info'), warn: capture('warn'), error: capture('error') };

  const provider = (options.provider ?? new ScriptedProvider()) as ScriptedProvider;
  const config = testConfig({ blobDir, ...options.config });
  const deps: Deps = {
    db, clock, config, log, provider, health: new ProviderHealth(),
    blobs: new FileBlobStore(blobDir, config.blobKey),
  };
  const app = buildApp(deps);
  const worker = new JobWorker(deps, { submitMs: 200, pollMs: 200, downloadMs: 200, enrollMs: 200, ...options.timeouts });

  const env: Env = {
    deps, db, app, worker, clock, provider, config, blobDir, logs,
    async drain({ stepMs = 6000, maxRounds = 60 } = {}) {
      for (let i = 0; i < maxRounds; i++) {
        await worker.tick();
        const pending = one(db,
          `SELECT (SELECT COUNT(*) FROM jobs WHERE status IN ('queued','submitting','processing','downloading')) +
                  (SELECT COUNT(*) FROM voices WHERE status = 'enrolling') AS n`);
        if (Number(pending?.['n'] ?? 0) === 0) return;
        clock.advance(stepMs);
      }
      throw new Error('drain: work still pending after max rounds');
    },
    restart(next) {
      // Same provider object by default: a restarted server talks to the same provider, and call counts carry over.
      return makeEnv({ ...options, provider: next ?? provider, reuse: { db, blobDir, clock, logs } });
    },
    async close() {
      worker.stop();
      await app.close();
      if (!options.reuse) {
        db.close();
        rmSync(blobDir, { recursive: true, force: true });
      }
    },
  };
  return env;
}

// ------------------------------------------------------------------ HTTP helpers

export const auth = (token: string) => ({ authorization: `Bearer ${token}` });

export async function register(env: Env, email = 'amina@example.com', password = 'correct horse battery') {
  const res = await env.app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password } });
  if (res.statusCode !== 201) throw new Error(`register failed: ${res.statusCode} ${res.body}`);
  const body = res.json() as { userId: string; token: string };
  return { userId: body.userId, token: body.token, email, password };
}

export async function grantCredits(env: Env, email: string, amount: number) {
  const res = await env.app.inject({
    method: 'POST', url: '/v1/admin/credits/grant', headers: { authorization: `Bearer ${ADMIN_TOKEN}` },
    payload: { email, amount, note: 'test grant' },
  });
  if (res.statusCode !== 200) throw new Error(`grant failed: ${res.statusCode} ${res.body}`);
  return res.json() as { available: number; held: number };
}

export async function createVoiceRecord(env: Env, token: string, over: Record<string, unknown> = {}) {
  return env.app.inject({
    method: 'POST', url: '/v1/voices', headers: auth(token),
    payload: {
      displayName: 'Test participant', ownership: 'own', authorizedBy: null,
      consent: { accepted: true, version: 'v1' }, ...over,
    },
  });
}

export async function uploadVoice(env: Env, token: string, voiceId: string, audio: Buffer = wav(10), mime = 'audio/wav') {
  return env.app.inject({
    method: 'PUT', url: `/v1/voices/${voiceId}/audio`,
    headers: { ...auth(token), 'content-type': mime }, payload: audio,
  });
}

/** Creates a voice, uploads a sample and runs the worker so the voice is `ready`. */
export async function readyVoice(env: Env, token: string, over: Record<string, unknown> = {}): Promise<string> {
  const created = await createVoiceRecord(env, token, over);
  if (created.statusCode !== 201) throw new Error(`voice create failed: ${created.body}`);
  const id = (created.json() as { voice: { id: string } }).voice.id;
  const up = await uploadVoice(env, token, id);
  if (up.statusCode !== 200) throw new Error(`voice upload failed: ${up.statusCode} ${up.body}`);
  await env.drain();
  return id;
}

let keyCounter = 0;
export const newKey = () => `test-key-${Date.now()}-${++keyCounter}-abcdefgh`;

export function jobPayload(over: Record<string, unknown> = {}) {
  return {
    idempotencyKey: newKey(), title: 'Test song', lyrics: 'Original lyrics line one\nOriginal lyrics line two',
    language: 'english', songType: 'full_song', voiceId: null,
    style: { genre: 'english_nasheed', mood: 'peaceful', tempo: 'normal', intensity: 'balanced', instruments: 'acoustic' },
    advanced: {}, ...over,
  };
}

export async function submitJob(env: Env, token: string, over: Record<string, unknown> = {}) {
  return env.app.inject({ method: 'POST', url: '/v1/generation/jobs', headers: auth(token), payload: jobPayload(over) });
}

export async function getJob(env: Env, token: string, id: string) {
  const res = await env.app.inject({ method: 'GET', url: `/v1/generation/jobs/${id}`, headers: auth(token) });
  return (res.json() as { job: Record<string, unknown> }).job;
}

export async function balanceOf(env: Env, token: string) {
  const res = await env.app.inject({ method: 'GET', url: '/v1/credits', headers: auth(token) });
  return res.json() as { available: number; held: number };
}

/** Asserts the credit ledger is internally consistent for every job. Returns nothing; throws on a violation. */
export function assertLedgerInvariants(db: Db): void {
  const jobs = all(db, `SELECT id, status FROM jobs`);
  for (const j of jobs) {
    const entries = all(db, `SELECT kind FROM credit_ledger WHERE job_id = ? ORDER BY id`, String(j['id'])).map((r) => String(r['kind']));
    const status = String(j['status']);
    const reserves = entries.filter((k) => k === 'reserve').length;
    const finals = entries.filter((k) => k === 'capture' || k === 'release');
    if (reserves !== 1) throw new Error(`job ${j['id']} has ${reserves} reserves`);
    if (finals.length > 1) throw new Error(`job ${j['id']} finalised ${finals.length} times: ${entries.join(',')}`);
    if (status === 'completed' && finals[0] !== 'capture') throw new Error(`completed job ${j['id']} was not captured: ${entries.join(',')}`);
    if ((status === 'failed' || status === 'cancelled') && finals[0] !== 'release') {
      throw new Error(`${status} job ${j['id']} was not released: ${entries.join(',')}`);
    }
    if (['queued', 'submitting', 'processing', 'downloading'].includes(status) && finals.length !== 0) {
      throw new Error(`active job ${j['id']} already finalised`);
    }
  }
}
