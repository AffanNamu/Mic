import type { Db } from './db.ts';
import { one, run } from './db.ts';
import type { Clock } from './clock.ts';
import { addMs, iso } from './clock.ts';
import { AppError, unauthorized } from './errors.ts';
import { hashPassword, randomToken, sha256Hex, verifyPassword } from './crypto.ts';
import { audit } from './audit.ts';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export interface AuthedUser {
  userId: string;
  sessionId: string;
}

export function normalizeEmail(raw: string): string {
  const email = raw.trim().toLowerCase();
  if (email.length > 254 || !EMAIL.test(email)) throw new AppError(400, 'invalid_email', 'Enter a valid email address.');
  return email;
}

function checkPassword(password: string): void {
  if (password.length < 10) throw new AppError(400, 'weak_password', 'Use at least 10 characters.');
  if (password.length > 200) throw new AppError(400, 'invalid_password', 'Password is too long.');
}

async function openSession(db: Db, clock: Clock, userId: string, ttlMs: number) {
  const token = randomToken(32);
  const id = crypto.randomUUID();
  const now = clock.now();
  run(db, `INSERT INTO sessions (id, user_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?, ?)`,
    id, userId, sha256Hex(token), iso(now), iso(addMs(now, ttlMs)));
  return { token, expiresAt: iso(addMs(now, ttlMs)) };
}

export async function register(db: Db, clock: Clock, ttlMs: number, emailRaw: string, password: string) {
  const email = normalizeEmail(emailRaw);
  checkPassword(password);
  if (one(db, 'SELECT 1 AS x FROM users WHERE email = ?', email)) {
    throw new AppError(409, 'email_taken', 'An account with this email already exists.');
  }
  const id = crypto.randomUUID();
  run(db, `INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)`,
    id, email, await hashPassword(password), iso(clock.now()));
  audit(db, clock, { userId: id, kind: 'user.registered', subjectType: 'user', subjectId: id });
  return { userId: id, email, ...(await openSession(db, clock, id, ttlMs)) };
}

// A real hash of a throwaway password, so unknown emails cost the same as wrong passwords.
const DUMMY_HASH = await hashPassword('timing-equalisation-only');

export async function login(db: Db, clock: Clock, ttlMs: number, emailRaw: string, password: string) {
  const email = emailRaw.trim().toLowerCase();
  const user = one(db, 'SELECT id, password_hash, disabled_at FROM users WHERE email = ?', email);
  const ok = await verifyPassword(password, user ? String(user['password_hash']) : DUMMY_HASH);
  if (!user || !ok || user['disabled_at']) {
    audit(db, clock, { kind: 'auth.login_failed', subjectType: 'user', subjectId: user ? String(user['id']) : 'unknown' });
    throw new AppError(401, 'invalid_credentials', 'Email or password is incorrect.');
  }
  const userId = String(user['id']);
  audit(db, clock, { userId, kind: 'auth.login', subjectType: 'user', subjectId: userId });
  return { userId, email, ...(await openSession(db, clock, userId, ttlMs)) };
}

export function authenticate(db: Db, clock: Clock, token: string | null): AuthedUser {
  if (!token) throw unauthorized();
  const row = one(
    db,
    `SELECT s.id AS sid, s.user_id, s.expires_at, s.revoked_at, u.disabled_at
       FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?`,
    sha256Hex(token),
  );
  if (!row || row['revoked_at'] || row['disabled_at'] || String(row['expires_at']) <= iso(clock.now())) {
    throw unauthorized('Your session has expired. Sign in again.');
  }
  return { userId: String(row['user_id']), sessionId: String(row['sid']) };
}

export function logout(db: Db, clock: Clock, sessionId: string): void {
  run(db, `UPDATE sessions SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL`, iso(clock.now()), sessionId);
}
