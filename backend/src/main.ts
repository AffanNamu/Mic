import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.ts';
import { openDb, runMigrations } from './db.ts';
import { systemClock } from './clock.ts';
import { FileBlobStore } from './blobstore.ts';
import { createProvider } from './provider/index.ts';
import { ProviderHealth } from './deps.ts';
import type { Deps, Logger } from './deps.ts';
import { buildApp } from './http.ts';
import { JobWorker } from './worker.ts';

const config = loadConfig();
const log: Logger = {
  info: (o, m) => console.log(JSON.stringify({ level: 'info', msg: m, ...o })),
  warn: (o, m) => console.warn(JSON.stringify({ level: 'warn', msg: m, ...o })),
  error: (o, m) => console.error(JSON.stringify({ level: 'error', msg: m, ...o })),
};

const db = openDb(config.databasePath);
const applied = runMigrations(db, fileURLToPath(new URL('../migrations', import.meta.url)));
if (applied.length) log.info({ applied }, 'migrations applied');

const deps: Deps = {
  db, clock: systemClock, config, log,
  blobs: new FileBlobStore(config.blobDir, config.blobKey),
  provider: createProvider(config),
  health: new ProviderHealth(),
};

const app = buildApp(deps);
const worker = new JobWorker(deps);
worker.start();

await app.listen({ host: config.host, port: config.port });
log.info({ host: config.host, port: config.port, provider: deps.provider.name, configured: deps.provider.configured }, 'listening');

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.on(signal, () => {
    worker.stop();
    void app.close().then(() => { db.close(); process.exit(0); });
  });
}
