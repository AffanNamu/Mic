import { fileURLToPath } from 'node:url';
import { loadConfigForMigrate } from './migrate-config.ts';
import { openDb, runMigrations } from './db.ts';

const dir = fileURLToPath(new URL('../migrations', import.meta.url));
const databasePath = loadConfigForMigrate();
const db = openDb(databasePath);
const applied = runMigrations(db, dir);
console.log(applied.length ? `Applied: ${applied.join(', ')}` : 'Database is up to date.');
