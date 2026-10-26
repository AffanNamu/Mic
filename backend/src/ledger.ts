import type { Db } from './db.ts';
import { all, one, run, tx } from './db.ts';
import type { Clock } from './clock.ts';
import { iso } from './clock.ts';
import { AppError } from './errors.ts';

export interface Balance {
  /** Spendable now. */
  available: number;
  /** Reserved for jobs that have not finished. */
  held: number;
}

export function balance(db: Db, userId: string): Balance {
  const row = one(
    db,
    `SELECT
       COALESCE(SUM(CASE kind WHEN 'grant' THEN amount WHEN 'adjust' THEN amount
                              WHEN 'reserve' THEN -amount WHEN 'release' THEN amount ELSE 0 END), 0) AS available,
       COALESCE(SUM(CASE kind WHEN 'reserve' THEN amount WHEN 'release' THEN -amount
                              WHEN 'capture' THEN -amount ELSE 0 END), 0) AS held
     FROM credit_ledger WHERE user_id = ?`,
    userId,
  );
  return { available: Number(row?.['available'] ?? 0), held: Number(row?.['held'] ?? 0) };
}

export function grant(db: Db, clock: Clock, userId: string, amount: number, note: string): void {
  if (!Number.isInteger(amount) || amount <= 0) throw new AppError(400, 'invalid_amount', 'Amount must be a positive integer.');
  run(db, `INSERT INTO credit_ledger (user_id, kind, amount, note, created_at) VALUES (?, 'grant', ?, ?, ?)`,
    userId, amount, note, iso(clock.now()));
}

/** Holds credits for a job. Fails with 402 if the available balance is too low. */
export function reserve(db: Db, clock: Clock, userId: string, jobId: string, amount: number): void {
  tx(db, () => {
    if (balance(db, userId).available < amount) {
      throw new AppError(402, 'insufficient_credits', 'You do not have enough credits for this song.', {
        required: amount, available: balance(db, userId).available,
      });
    }
    run(db, `INSERT INTO credit_ledger (user_id, kind, amount, job_id, created_at) VALUES (?, 'reserve', ?, ?, ?)`,
      userId, amount, jobId, iso(clock.now()));
  });
}

/** Spends the hold. Idempotent: a job is finalised at most once (enforced by a unique index). */
export function capture(db: Db, clock: Clock, jobId: string): 'captured' | 'already_final' | 'no_hold' {
  return finalise(db, clock, jobId, 'capture', 'Song delivered');
}

/** Returns the hold to the user. Idempotent, same as `capture`. */
export function release(db: Db, clock: Clock, jobId: string, reason: string): 'released' | 'already_final' | 'no_hold' {
  const r = finalise(db, clock, jobId, 'release', reason);
  return r === 'captured' ? 'released' : r;
}

function finalise(db: Db, clock: Clock, jobId: string, kind: 'capture' | 'release', note: string) {
  return tx(db, () => {
    const hold = one(db, `SELECT user_id, amount FROM credit_ledger WHERE job_id = ? AND kind = 'reserve'`, jobId);
    if (!hold) return 'no_hold' as const;
    const done = one(db, `SELECT kind FROM credit_ledger WHERE job_id = ? AND kind IN ('capture','release')`, jobId);
    if (done) return 'already_final' as const;
    run(db, `INSERT INTO credit_ledger (user_id, kind, amount, job_id, note, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
      String(hold['user_id']), kind, Number(hold['amount']), jobId, note, iso(clock.now()));
    return 'captured' as const;
  });
}

export interface LedgerEntry {
  id: number;
  kind: string;
  amount: number;
  jobId: string | null;
  note: string | null;
  createdAt: string;
}

export function transactions(db: Db, userId: string, limit = 50): LedgerEntry[] {
  return all(db, `SELECT * FROM credit_ledger WHERE user_id = ? ORDER BY id DESC LIMIT ?`, userId, limit).map((r) => ({
    id: Number(r['id']), kind: String(r['kind']), amount: Number(r['amount']),
    jobId: (r['job_id'] as string | null) ?? null, note: (r['note'] as string | null) ?? null,
    createdAt: String(r['created_at']),
  }));
}
