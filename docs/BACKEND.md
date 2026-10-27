# Backend

`backend/` is the server the app talks to. It owns accounts, voice consent, private
storage, the credit ledger, generation jobs, and **every provider credential**. The
Flutter app contains no provider key and no provider URL.

Stack: Node ≥ 22.18 running TypeScript directly (type stripping, no build step),
Fastify 5, SQLite via `node:sqlite`. Two runtime dependencies (`fastify`,
`@fastify/cors`). Chosen to be the smallest thing that is secure and testable here;
see "Production gaps" for what must change before real traffic.

```sh
cd backend
npm ci
npm test            # 173 tests, ~30 s
npm run typecheck
cp .env.example .env   # fill in; there are no default secrets
set -a; . ./.env; set +a
npm start
```

With `PROVIDER=none` (the default) the server runs, but nothing can be generated and
every endpoint says so. `PROVIDER=mureka` needs `MUREKA_API_KEY`.

## Layout

| Path | Purpose |
| --- | --- |
| `src/http.ts` | Routes, strict schema validation, error shape, auth hooks |
| `src/auth.ts`, `crypto.ts` | scrypt password hashing; opaque session tokens stored only as SHA-256 |
| `src/voices.ts`, `consent.ts` | Voice records, server-owned consent text, upload validation, revoke, delete |
| `src/ledger.ts` | Append-only credit ledger: reserve / capture / release |
| `src/jobs.ts`, `worker.ts` | Idempotent submission and the persistent job state machine |
| `src/provider/` | `MusicProvider` port, `UnconfiguredProvider`, `MurekaProvider` |
| `src/blobstore.ts` | Encrypted private file storage behind a small interface |
| `src/songs.ts` | Library, signed audio links |
| `src/metrics.ts` | Operator metrics: completion, latency, cost per successful song |
| `migrations/` | Append-only SQL migrations with checksum guard |
| `scripts/` | `mureka-probe.mjs`, `live-poc.ts`, `summarize-listening.ts` |
| `test/` | Tests; `test/support/` holds the **test double**, never imported by `src/` |

## API (all JSON; `Authorization: Bearer <token>` except where noted)

| Method & path | Notes |
| --- | --- |
| `GET /healthz` (no auth) | Provider name, whether configured, whether currently available |
| `GET /v1/consent-statements` (no auth) | The exact consent wording and its version |
| `POST /v1/auth/register`, `/v1/auth/login` (no auth) | Rate-limited; same error for wrong password and unknown email |
| `POST /v1/auth/logout` | Revokes the session |
| `GET /v1/me`, `/v1/credits`, `/v1/credits/transactions` | Balance is `{available, held}` |
| `GET /v1/generation/capabilities` | What the engine verifiably supports, and whether it is available now |
| `GET /v1/generation/quote` | Credits and the provider's expected cost |
| `POST /v1/generation/jobs` | Idempotent (`idempotencyKey`). `202` new, `200` duplicate, `402` no credits, `422` unsupported |
| `GET /v1/generation/jobs[/:id]`, `POST …/:id/cancel` | Cancel only before the provider has the job |
| `GET/POST /v1/voices`, `PUT /v1/voices/:id/audio`, `POST …/retry`, `…/revoke`, `DELETE /v1/voices/:id` | Consent first, then audio; delete reports what was and was not removed |
| `GET /v1/songs[/:id]`, `PATCH`, `DELETE`, `POST /v1/songs/:id/audio-url` | The audio URL is a signed, 5-minute link |
| `GET /media/songs/:id?exp&sig` | Signed link, `Range` supported, `Cache-Control: private, no-store` |
| `POST /v1/admin/credits/grant`, `GET /v1/admin/metrics`, `POST /v1/admin/provider/reset-health` | `ADMIN_TOKEN` only; disabled if unset |

Errors are `{ "error": { "code", "message" } }`. Messages are written for users;
provider text is never passed through.

## Job state machine

```
queued → submitting → processing → downloading → completed
   │          │             │            │
   └──────────┴─────────────┴────────────┴──→ failed        (credits released)
queued ──→ cancelled                                         (credits released)
```

- Credits are **reserved in the same transaction** that creates the job (no credit, no
  job), **captured** in the same transaction that stores the song, and **released** on any
  failure or cancellation. A unique index allows one reserve and one terminal entry per
  job, so finalisation is idempotent.
- `submitting` is written **before** the provider is called. A job found in `submitting`
  after a crash is failed as `submit_outcome_unknown`; it is never resubmitted, because
  the provider may already be generating and billing it.
- Errors are classified by cost, not by HTTP code: **not started** (429, refused
  connection) is retried with backoff; **unknown** (timeout, 5xx or unreadable 2xx on a
  write) is not retried; **terminal** (4xx, bad credentials, no funds) is not retried.
- A provider "success" is not trusted: the audio is downloaded, must be at least 4 KB and
  must be recognisable audio (magic bytes), otherwise the job fails and the credit returns.
- Leases and a 20-minute deadline bound every step; polling continues across restarts.
- Credentials rejected by the provider fail the job, return the credit, and block new jobs
  for 5 minutes (health `available: false`) so users are not charged into a broken service.

## Security model

- Authentication on every non-public route, checked **before** the body is read or
  validated. Authorisation: every query is scoped by user; another user's id yields 404.
- Passwords: scrypt (N=2¹⁵). Tokens: 256-bit random, stored as SHA-256 only, 30-day expiry,
  revocable. Login is rate-limited and constant-effort for unknown emails.
- Stored audio (voice samples and songs) is AES-256-GCM encrypted, bound to its storage key,
  written `0600`. Storage keys never leave the server.
- Audio is served only through short-lived HMAC-signed links (the audio element cannot send
  headers); a link is bound to one song and expires in 5 minutes.
- Request bodies are strictly validated (unknown fields rejected, no coercion). CORS is off
  unless origins are configured. The provider's download URL is untrusted: https only, no IP
  literals/localhost, optional host allow-list, size cap, no API key sent.
- Logs and the audit table never contain passwords, tokens, keys, lyrics or audio
  (asserted by a test).
- **Consent**: the server owns the wording; the app displays it verbatim and the server
  stores the version, its SHA-256, time, IP and user-agent. Audio is refused until consent
  is recorded.
- **Deletion**: removes the stored recording and, if asked, the songs made with the voice
  (text wiped, audio removed). A tombstone and the consent record are kept for
  accountability. It states plainly what the provider keeps (Mureka has no deletion API we
  could find, so `providerDeletion` is `unsupported` and the user is told).

## What is verified and what is not

Verified by the test suite (173 backend tests) with a labelled **test double** and a
local mock HTTP server: all of the above behaviour, including failures, empty responses,
timeouts, duplicate submissions, expired credentials, insufficient credits, crash
recovery, secret non-leakage. Twenty deliberate breakages of the source were each caught.

**Not verified against any real provider**: the Mureka request/response field names and
status values (written without being able to reach the API), the vocal-cloning operation
(its path is deliberately unset, so enrollment fails closed), and everything about audio
quality. See [PROVIDER_EVALUATION.md](PROVIDER_EVALUATION.md) and
[ACCEPTANCE_PHASE2.md](ACCEPTANCE_PHASE2.md).

## Production gaps

- SQLite on one node and in-memory rate limits: use a managed database and a gateway/shared
  limiter before running more than one instance. Behind a reverse proxy set Fastify's
  `trustProxy` so rate limits key on the client address rather than the proxy's.
- Registration is open. That is safe only while credits are granted by an operator; add email
  verification and abuse controls before credits can be bought.
- Blob keys come from an environment variable: use a KMS-managed key with rotation, and
  object storage with lifecycle rules.
- Sessions are long-lived opaque tokens in browser storage on web: add short-lived access
  tokens with refresh or httpOnly cookies, email verification, password reset, MFA.
- No payments: credits are granted by an operator.
- No abuse tooling (reporting, voice-misuse review), no content moderation of lyrics.
- No webhooks (Mureka's webhook support is unverified); the worker polls.
- Single-process worker with leases; a queue service is the next step at scale.
- Retention, privacy notice and data-processing terms need legal review, especially the
  provider's licence over uploaded voice data.
- Observability: structured logs exist; metrics export, alerting and tracing do not.
