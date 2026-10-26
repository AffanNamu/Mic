import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { sha256Hex } from './crypto.ts';

export type Db = DatabaseSync;

export function openDb(path: string): Db {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');
  return db;
}

/**
 * Applies `NNNN_name.sql` files in order, once each. Each file runs in a
 * transaction and its checksum is recorded; if an applied file is later edited
 * the process refuses to start, because schema history must be append-only.
 */
export function runMigrations(db: Db, dir: string, now: () => Date = () => new Date()): string[] {
  db.exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY, checksum TEXT NOT NULL, applied_at TEXT NOT NULL)`);
  const applied = new Map<string, string>();
  for (const row of db.prepare('SELECT version, checksum FROM schema_migrations').all()) {
    applied.set(String(row['version']), String(row['checksum']));
  }

  const newlyApplied: string[] = [];
  const files = readdirSync(dir).filter((f) => /^\d{4}_.+\.sql$/.test(f)).sort();
  for (const file of files) {
    const version = file.replace(/\.sql$/, '');
    const sql = readFileSync(join(dir, file), 'utf8');
    const checksum = sha256Hex(sql);
    const known = applied.get(version);
    if (known !== undefined) {
      if (known !== checksum) {
        throw new Error(`Migration ${version} was modified after it was applied. Add a new migration instead.`);
      }
      continue;
    }
    tx(db, () => {
      db.exec(sql);
      db.prepare('INSERT INTO schema_migrations (version, checksum, applied_at) VALUES (?, ?, ?)')
        .run(version, checksum, now().toISOString());
    });
    newlyApplied.push(version);
  }
  return newlyApplied;
}

const depth = new WeakMap<Db, number>();

/** Runs `fn` in a transaction (a savepoint when nested); rolls back if it throws. */
export function tx<T>(db: Db, fn: () => T): T {
  const level = depth.get(db) ?? 0;
  const name = `sp_${level}`;
  db.exec(level === 0 ? 'BEGIN IMMEDIATE' : `SAVEPOINT ${name}`);
  depth.set(db, level + 1);
  try {
    const result = fn();
    depth.set(db, level);
    db.exec(level === 0 ? 'COMMIT' : `RELEASE ${name}`);
    return result;
  } catch (err) {
    depth.set(db, level);
    db.exec(level === 0 ? 'ROLLBACK' : `ROLLBACK TO ${name}; RELEASE ${name}`);
    throw err;
  }
}

export type Row = Record<string, unknown>;
export const one = (db: Db, sql: string, ...params: SQLParam[]): Row | undefined =>
  db.prepare(sql).get(...params) as Row | undefined;
export const all = (db: Db, sql: string, ...params: SQLParam[]): Row[] =>
  db.prepare(sql).all(...params) as Row[];
export const run = (db: Db, sql: string, ...params: SQLParam[]) => db.prepare(sql).run(...params);

type SQLParam = string | number | bigint | Buffer | null;
