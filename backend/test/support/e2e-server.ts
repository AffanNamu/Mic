// A local backend for driving the Flutter web build in a real browser.
//
// !! The music provider here is the labelled TEST DOUBLE (it returns a synthetic tone). !!
// It exists to check that the app, the HTTP API, the job pipeline, storage and playback fit together.
// It is started only by this file, which is not part of the server (src/), is not importable from it,
// and is not selectable through any environment variable. Songs it makes say "test-double" in the app.
//
//   node --disable-warning=ExperimentalWarning test/support/e2e-server.ts <port> <corsOrigin>
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { buildApp } from '../../src/http.ts';
import { JobWorker } from '../../src/worker.ts';
import { ProviderHealth } from '../../src/deps.ts';
import type { Deps } from '../../src/deps.ts';
import { FileBlobStore } from '../../src/blobstore.ts';
import { openDb, runMigrations } from '../../src/db.ts';
import { systemClock } from '../../src/clock.ts';
import { ADMIN_TOKEN, MIGRATIONS_DIR, testConfig } from './harness.ts';
import { ScriptedProvider } from './scripted-provider.ts';
import { wav } from './wav.ts';

const port = Number(process.argv[2] ?? 18080);
const origin = process.argv[3] ?? 'http://127.0.0.1:18081';

const dir = mkdtempSync(join(tmpdir(), 'deenvoice-e2e-'));
const config = testConfig({ port, corsOrigins: [origin], blobDir: join(dir, 'blobs'), maxVoiceBytes: 5 * 1024 * 1024 });
const db = openDb(join(dir, 'e2e.sqlite'));
runMigrations(db, MIGRATIONS_DIR);

const provider = new ScriptedProvider();
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let polls = 0;
provider.onEnroll = async (n) => { await sleep(1500); return { providerVoiceId: `test-double-voice-${n}`, costMicros: 5_000_000 }; };
provider.onPoll = async () => (++polls % 2 === 1
  ? { state: 'running' as const }
  : { state: 'succeeded' as const, audioUrl: 'https://test-double.invalid/song.wav', durationMs: 8000, costMicros: null });
provider.onDownload = async () => wav(8, { sampleRate: 16000, hz: 330 }); // an 8-second tone

const deps: Deps = {
  db, clock: systemClock, config, provider, health: new ProviderHealth(),
  blobs: new FileBlobStore(config.blobDir, config.blobKey),
  log: { info() {}, warn: (o, m) => console.error(JSON.stringify({ m, ...o })), error: (o, m) => console.error(JSON.stringify({ m, ...o })) },
};
const app = buildApp(deps);
const worker = new JobWorker(deps);
worker.start(500);
await app.listen({ host: '127.0.0.1', port });
console.log(JSON.stringify({ ready: true, port, adminToken: ADMIN_TOKEN, provider: provider.name }));
for (const sig of ['SIGINT', 'SIGTERM'] as const) process.on(sig, () => { worker.stop(); void app.close().then(() => process.exit(0)); });
