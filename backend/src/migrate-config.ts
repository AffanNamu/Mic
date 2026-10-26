import { resolve } from 'node:path';

/** Migrations only need the database path, not the secrets the server requires. */
export function loadConfigForMigrate(env: Record<string, string | undefined> = process.env): string {
  return resolve(env['DATABASE_PATH'] ?? './data/deenvoice.sqlite');
}
