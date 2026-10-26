import type { Db } from './db.ts';
import type { Clock } from './clock.ts';
import type { Config } from './config.ts';
import type { BlobStore } from './blobstore.ts';
import type { MusicProvider } from './provider/types.ts';

/** Tracks whether the provider has told us our credentials are bad, so new jobs fail fast and free. */
export class ProviderHealth {
  private blockedUntilMs = 0;
  reason: string | null = null;

  block(clock: Clock, forMs: number, reason: string): void {
    this.blockedUntilMs = clock.now().getTime() + forMs;
    this.reason = reason;
  }
  clear(): void {
    this.blockedUntilMs = 0;
    this.reason = null;
  }
  isBlocked(clock: Clock): boolean {
    return clock.now().getTime() < this.blockedUntilMs;
  }
}

export interface Logger {
  info(obj: Record<string, unknown>, msg?: string): void;
  warn(obj: Record<string, unknown>, msg?: string): void;
  error(obj: Record<string, unknown>, msg?: string): void;
}

export const silentLogger: Logger = { info() {}, warn() {}, error() {} };

export interface Deps {
  db: Db;
  clock: Clock;
  config: Config;
  blobs: BlobStore;
  provider: MusicProvider;
  health: ProviderHealth;
  log: Logger;
}
