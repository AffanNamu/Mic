-- DeenVoice backend schema, version 1.
-- Timestamps are UTC ISO-8601 strings. Money-like values are integers.

CREATE TABLE users (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  disabled_at   TEXT
);

CREATE TABLE sessions (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id),
  token_hash TEXT NOT NULL UNIQUE,      -- sha256 of the bearer token; the token itself is never stored
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  revoked_at TEXT
);
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE voices (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id),
  display_name      TEXT NOT NULL,
  ownership         TEXT NOT NULL CHECK (ownership IN ('own', 'authorized')),
  authorized_by     TEXT,               -- name of the speaker when ownership = 'authorized'
  status            TEXT NOT NULL CHECK (status IN
                      ('awaiting_audio', 'enrolling', 'ready', 'failed', 'revoked', 'deleted')),
  audio_blob_key    TEXT,
  audio_sha256      TEXT,
  audio_mime        TEXT,
  audio_bytes       INTEGER,
  provider          TEXT,
  provider_voice_id TEXT,
  supports_singing  INTEGER NOT NULL DEFAULT 0,
  provider_cost_micros INTEGER,          -- what the provider charged to enroll, in millionths of a USD
  failure_code      TEXT,
  failure_message   TEXT,
  enroll_attempts   INTEGER NOT NULL DEFAULT 0,
  lease_until       TEXT,
  provider_deletion TEXT CHECK (provider_deletion IN ('not_applicable', 'requested', 'deleted', 'unsupported', 'failed')),
  created_at        TEXT NOT NULL,
  updated_at        TEXT NOT NULL,
  deleted_at        TEXT
);
CREATE INDEX voices_user ON voices(user_id);
CREATE INDEX voices_status ON voices(status);

-- Immutable record of what the user agreed to. Never updated except for revocation.
CREATE TABLE consents (
  id               TEXT PRIMARY KEY,
  voice_id         TEXT NOT NULL REFERENCES voices(id),
  user_id          TEXT NOT NULL REFERENCES users(id),
  ownership        TEXT NOT NULL,
  authorized_by    TEXT,
  statement_version TEXT NOT NULL,
  statement_sha256 TEXT NOT NULL,       -- hash of the exact text shown
  accepted_at      TEXT NOT NULL,
  ip               TEXT,
  user_agent       TEXT,
  revoked_at       TEXT
);
CREATE INDEX consents_voice ON consents(voice_id);

-- Append-only. Available balance = grants + adjusts + reserves(negative) + releases.
-- A `capture` consumes a hold and does not change the available balance.
CREATE TABLE credit_ledger (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id    TEXT NOT NULL REFERENCES users(id),
  kind       TEXT NOT NULL CHECK (kind IN ('grant', 'reserve', 'capture', 'release', 'adjust')),
  amount     INTEGER NOT NULL,
  job_id     TEXT,
  note       TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX ledger_user ON credit_ledger(user_id);
-- One reserve, and at most one terminal entry, per job: finalisation is idempotent.
CREATE UNIQUE INDEX ledger_job_reserve ON credit_ledger(job_id) WHERE kind = 'reserve';
CREATE UNIQUE INDEX ledger_job_terminal ON credit_ledger(job_id) WHERE kind IN ('capture', 'release');

CREATE TABLE jobs (
  id               TEXT PRIMARY KEY,
  user_id          TEXT NOT NULL REFERENCES users(id),
  idempotency_key  TEXT NOT NULL,
  request_hash     TEXT NOT NULL,
  status           TEXT NOT NULL CHECK (status IN
                     ('queued', 'submitting', 'processing', 'downloading', 'completed', 'failed', 'cancelled')),
  voice_id         TEXT REFERENCES voices(id),
  title            TEXT NOT NULL,
  lyrics           TEXT NOT NULL,
  language         TEXT NOT NULL,
  settings_json    TEXT NOT NULL,
  credits          INTEGER NOT NULL,
  provider         TEXT NOT NULL,
  provider_task_id TEXT,
  provider_cost_micros INTEGER,
  attempts         INTEGER NOT NULL DEFAULT 0,   -- consecutive failed attempts of the current step
  lease_until      TEXT,
  next_run_at      TEXT NOT NULL,
  deadline_at      TEXT NOT NULL,
  submit_started_at TEXT,
  result_json      TEXT,                          -- provider result (audio URL, duration) kept so a crash can resume the download
  failure_code     TEXT,
  failure_message  TEXT,
  song_id          TEXT,
  created_at       TEXT NOT NULL,
  updated_at       TEXT NOT NULL,
  completed_at     TEXT,
  UNIQUE (user_id, idempotency_key)
);
CREATE INDEX jobs_active ON jobs(status, next_run_at);

CREATE TABLE songs (
  id             TEXT PRIMARY KEY,
  user_id        TEXT NOT NULL REFERENCES users(id),
  job_id         TEXT NOT NULL UNIQUE REFERENCES jobs(id),
  title          TEXT NOT NULL,
  lyrics         TEXT NOT NULL,
  language       TEXT NOT NULL,
  settings_json  TEXT NOT NULL,
  voice_id       TEXT,
  voice_name     TEXT,
  provider       TEXT NOT NULL,
  duration_ms    INTEGER,
  audio_blob_key TEXT NOT NULL,
  audio_mime     TEXT NOT NULL,
  audio_bytes    INTEGER NOT NULL,
  audio_sha256   TEXT NOT NULL,
  created_at     TEXT NOT NULL,
  deleted_at     TEXT
);
CREATE INDEX songs_user ON songs(user_id, created_at);

CREATE TABLE audit_events (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  at           TEXT NOT NULL,
  user_id      TEXT,
  kind         TEXT NOT NULL,
  subject_type TEXT NOT NULL,
  subject_id   TEXT NOT NULL,
  detail_json  TEXT NOT NULL DEFAULT '{}'
);
CREATE INDEX audit_subject ON audit_events(subject_type, subject_id);
