import type { Clock } from './clock.ts';

/** Fixed-window limiter, in memory. A single-process guard; put a real limiter at the gateway in production. */
export class RateLimiter {
  private readonly windows = new Map<string, { start: number; count: number }>();
  private readonly clock: Clock;
  private readonly limit: number;
  private readonly windowMs: number;

  constructor(clock: Clock, limit: number, windowMs: number) {
    this.clock = clock;
    this.limit = limit;
    this.windowMs = windowMs;
  }

  /** Returns false when the caller is over the limit. */
  allow(key: string): boolean {
    const now = this.clock.now().getTime();
    const w = this.windows.get(key);
    if (!w || now - w.start >= this.windowMs) {
      this.windows.set(key, { start: now, count: 1 });
      if (this.windows.size > 10_000) this.prune(now);
      return true;
    }
    w.count += 1;
    return w.count <= this.limit;
  }

  private prune(now: number): void {
    for (const [k, w] of this.windows) if (now - w.start >= this.windowMs) this.windows.delete(k);
  }
}
