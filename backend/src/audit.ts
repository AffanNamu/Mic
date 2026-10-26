import type { Db } from './db.ts';
import type { Clock } from './clock.ts';
import { iso } from './clock.ts';

export interface AuditEvent {
  userId?: string | null;
  kind: string;
  subjectType: string;
  subjectId: string;
  /** Never put secrets, tokens, passwords, lyrics or audio in here. */
  detail?: Record<string, unknown>;
}

export function audit(db: Db, clock: Clock, e: AuditEvent): void {
  db.prepare(
    `INSERT INTO audit_events (at, user_id, kind, subject_type, subject_id, detail_json)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).run(iso(clock.now()), e.userId ?? null, e.kind, e.subjectType, e.subjectId, JSON.stringify(e.detail ?? {}));
}
