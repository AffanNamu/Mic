# Repository assessment and plan (Phase 0)

## Repository state found

The repository (`affannamu/mic`) was **empty**: no commits, no files, no default
branch. The directive describes an existing "AI Studio" codebase with a static
studio and screens to inspect; none exists here. There was therefore nothing to
preserve, migrate or replace. The work started from a fresh Flutter project
created in the repository root (no new repository was created).

Consequences:

- No backend, integrations, credentials, assets, tests, or prior screens existed.
- "Existing functionality worth retaining" and "static screens to replace" are
  empty sets.
- No secrets were found or handled.

## What was built

See [STATUS.md](STATUS.md). In short: Flutter project (Android, iOS, web
targets), design system, typed domain, Riverpod state, honest integration
boundaries, and the complete Create Song screen from the design reference, with
152 tests and real-browser verification.

## Recommended architecture

See [ARCHITECTURE.md](ARCHITECTURE.md). Flutter client over a server that owns
authentication, relational data, private object storage, a job queue with
webhook handling, usage/credit metering, and **all provider credentials**.
Provider access sits behind adapters exposing stable capability interfaces
(lyrics, voice enrollment, voice-conditioned singing, full song, instrumental,
audio transform, quality evaluation); a provider implements only what it
verifiably supports, and routing consults declared capabilities.

## Voice-to-song provider feasibility

**Not assessed.** No provider documentation was read, no API called, no price,
language, licensing, consent policy or quality claim verified. Nothing in the
code or docs asserts that any provider can sing in a cloned voice, speak Hausa,
or run commercially.

What must be established before choosing (from the directive), per candidate:

1. Does it offer a production API for *voice-conditioned singing* or voice
   conversion, as opposed to speech-only cloning? (These are different.)
2. Hausa, Arabic and English singing support, pronunciation quality, accent.
3. Enrollment requirements, consent/verification rules, retention and deletion.
4. Commercial-use terms, rate limits, latency, price per generation.
5. Output formats and whether stems/instrumental-only/extension are available.
6. A real end-to-end test: enroll an authorized test voice → sing lyrics → mix →
   play, with measured similarity and pronunciation by human review.

## Credentials and infrastructure required

- A hosting target and database for the backend; object storage; a queue/worker.
- Authentication provider (the login design shows Google, Apple and email).
- At least one voice-conditioned singing provider account and API key, plus a
  lyrics-model key, held server-side.
- A payment provider if credits are sold.
- For Android: Android SDK; for iOS: macOS + Xcode and signing; launcher icons.
- Native microphone permissions once in-app recording is built.

## Highest-priority risks

1. **Voice-to-song feasibility.** The core promise depends on a provider that
   genuinely supports consented singing in a user's voice for Hausa/Arabic. This
   is unverified and should be proven first, before building more UI.
2. **Language quality.** Hausa and Arabic singing pronunciation may be poor in
   general-purpose models; needs human evaluation and a fallback story.
3. **Consent and misuse.** Voice cloning needs enforceable consent, revocation,
   deletion and abuse reporting, including provider-side limits.
4. **Cost control.** Generation is expensive; needs server-side quotes, limits,
   idempotency and charge-on-accept before any real traffic.
5. **Religious-text integrity.** Qur'anic text and supplications must come from
   verified sources and never be silently rewritten; the lyrics assistant needs
   guardrails and a review step (the UI already requires review).
6. **Accessibility vs fidelity.** The reference's small type and small targets
   conflict with common mobile guidance (see ARCHITECTURE.md).

## Next milestone

**Phase 2 feasibility, one real end-to-end path** (before more screens):

1. Pick a candidate and read its current official documentation; record verified
   capabilities, terms and costs.
2. Stand up the minimal backend: auth, voice enrollment with consent, submit
   with an idempotency key, webhook/poll for completion, private storage.
3. Implement `VoiceRepository`, `SongGenerationService` (including
   `capabilities()`) and `CreditsRepository` against it, replacing the
   `Unconfigured*` services via provider overrides.
4. Enroll an authorized test voice, generate a real song, play it back, and
   record quality and cost. Only then widen to routing and more providers.

Then Phase 3: persistent jobs and progress, playback and library, in-app
recording, lyrics assistant.
