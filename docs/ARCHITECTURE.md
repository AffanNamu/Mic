# Architecture

## Layers

```
presentation  →  application  →  domain  ←  data
(widgets)        (Riverpod)      (entities,   (service implementations,
                                  validation,  file pickers)
                                  interfaces)
```

- **domain/** has no UI and no I/O. It holds the song draft, options, voice
  profiles, generation capabilities/request/receipt, `validateDraft`, step
  progress, pricing estimate, failures, and the **service interfaces**
  (`VoiceRepository`, `CreditsRepository`, `LyricsAssistant`,
  `SongGenerationService`, `TextFilePicker`, `AudioFilePicker`).
- **data/** implements those interfaces: `Unconfigured*` stand-ins (empty data /
  `ServiceNotConfigured`), `data/api/` (an HTTP client and the `Http*` services
  that talk to the DeenVoice backend), `data/audio/` (a `just_audio` adapter behind
  `AudioPlayerPort`) and the platform file pickers with their validation.
- **application/** is Riverpod state: `songDraftProvider`, async providers for
  voices/credits/capabilities, derived providers (selected voice, issues, step
  progress), and `GenerationController`.
- **presentation/** is the screens, sheets and widgets. Widgets read providers;
  they contain no business rules beyond layout.
- **core/** is the design system (tokens, shared widgets, icons) and small
  utilities (text direction detection).

Providers for every integration boundary are overridable in `ProviderScope`. With no
`API_BASE_URL` every boundary resolves to its `Unconfigured*` stand-in, so the
shipped default is the honest "not connected" app. With `--dart-define=API_BASE_URL=…`
they resolve to the `Http*` services, which share one `ApiClient` carrying the signed-in
user's token; signing in or out rebuilds them, so no data survives a change of user.
Tests override the providers with fakes under `test/support/`.

## Design rules that shaped the code

- **No invented data.** Voices, credits, capabilities and generations come only
  from services. Fixtures live under `test/` and `tool/preview/` and are never
  imported by `lib/`.
- **Capability-aware UI.** `GenerationCapabilities` (what the connected engine
  verifiably supports) gates song types, languages, voice conditioning and
  advanced options. With no engine, nothing is claimed to work.
- **Truthful failure.** Every unconfigured path throws `ServiceNotConfigured`
  with a user-safe message; the UI shows it. Unexpected errors show a generic
  message and are logged, never leaked.
- **Review before replace.** AI and imported text never overwrite the user's
  lyrics without a visible confirmation or review step.
- **Consent first.** Voice upload requires an explicit consent choice
  (own voice vs authorized by the owner), recorded with a UTC timestamp in
  `VoiceConsent`.

## The generation flow

`GenerationController.submit()`:

1. Ignore if already submitting (guard set before any `await`).
2. Await voices and re-fetch engine capabilities (a stale answer would submit an
   unsupported job; a not-yet-loaded voice list would blame the user).
3. `validateDraft` against the draft, voices and capabilities → `InvalidDraft`.
4. No engine → `EngineUnavailable`.
5. Read the balance; unreadable → `CreditsUnverified`; too low →
   `InsufficientCredits`.
6. Submit a `GenerationRequest` with an **idempotency key**. The key is reused
   for retries of an identical request and replaced when the draft changes or a
   job is accepted.
7. `GenerationAccepted(receipt)` or `SubmitFailed(message)`.

## Backend contract this client requires

Implemented by `backend/` (see [BACKEND.md](BACKEND.md) for the API and how each point is
verified). The list below is the contract the client relies on; the "requires" wording is
kept because the app is only correct against a backend that honours it.

1. **Authentication and authorization on every call.** A user may only see and
   use their own voices, songs and balance. Client-side hiding is not a boundary.
2. **Secrets stay server-side.** Provider credentials never ship in the app.
3. **Idempotent submit.** The job's identity is `idempotencyKey`. A retry with
   the same key must return the same job and must not start or charge a second
   one, even if the first response was lost.
4. **Charge on acceptance only.** Credits are debited (or reserved) by the
   server when it accepts a job, never by the client, and are released if the
   job is rejected or fails before work is done. The client's price is an
   estimate (`estimateCredits` = 1 per generation, from the reference design);
   the server's quote is authoritative and should replace it.
5. **Capability discovery.** `capabilities()` must report only what the routed
   provider verifiably supports (song types, languages, voice conditioning,
   advanced option ids). Speech-only voice cloning must not be reported as
   singing support.
6. **Voice lifecycle.** Enrollment returns a profile in `enrolling`; only
   `ready` + `supportsSinging` profiles are selectable. Revocation and deletion
   must be real, and provider-side deletion limits must be disclosed.
7. **Private audio.** Voice recordings and generated audio in access-controlled
   storage with short-lived URLs; size/format validation server-side as well as
   in the client (25 MB, wav/mp3/m4a/aac/ogg/flac/webm).
8. **Audit.** Consent records, enrollment, deletion and generation requests are
   auditable.

## Accessibility and typography notes

- Semantics labels, selected state and header roles are set on all controls
  (tested). System text scaling is honoured up to 1.3x, then capped.
- Contrast of the text colours against the panel and input fills is asserted at
  ≥ 4.5:1 in tests.
- **The reference's body text is small** (about 7–10 pt on a 426 pt frame) and
  several controls are smaller than 44–48 pt (pills 20.5 pt, back button 35 pt).
  These were matched to the reference. If the design is relaxed, change the sizes
  in `lib/core/theme/deen_theme.dart` (`DeenText.boost` scales all text) and the
  pill/back-button sizes; layouts already grow with text.

## Web caveat

On web, `TextField(minLines)` sizes itself from the font's natural line height.
The lyrics editor therefore states its minimum height explicitly (and forces its
line height with a strut) so it is the same on every platform. The lyrics
placeholder still sits about 3 pt higher on web than on the mobile engine.

## Phase 2 additions

- **Session**: `SessionController` restores a stored session (discarding an expired one),
  signs in/out, and resets per-user state. The API client signs the user out when the
  server rejects the token.
- **Consent**: the server owns the consent wording (`GET /v1/consent-statements`). The add-voice
  sheet shows it verbatim and sends only the version; if it cannot be loaded no voice can be
  added. Without a backend the sheet falls back to local wording and cannot submit.
- **Jobs**: `jobWatchProvider` polls one job and yields only server-reported states; transient
  network errors are retried, a rejected session or repeated failure ends the stream with an
  error. Nothing is estimated.
- **Provider honesty in the UI**: a song shows "Made with <provider>" from the server's record,
  so a song made by a test double says so.
- **Playback**: the player asks the backend for a signed 5-minute link and plays it; the player
  sits behind `AudioPlayerPort` so screens are tested without a device.

## Launch flow, shell and on-device state

```
DeenVoiceApp ── _SessionGuard (above the navigator) ── MaterialApp ── _Root
_Root:  onboarding not seen            → OnboardingScreen
        no backend (API_BASE_URL empty) → AppShell            (no account exists)
        backend, nobody signed in       → WelcomeScreen
        backend, signed in              → AppShell
AppShell: Home | My Voice | Library behind a bottom bar; Create and + push CreateSongScreen
```

- **One tab is built at a time** (no `IndexedStack`). A Riverpod 3 listener under a covered route is
  paused, and a provider invalidated meanwhile is flushed when the route is revealed, which asserts
  in debug if it happens during a build. Building only the visible tab avoids the situation; the
  widget tests pop back from Create, Manage Voices and the recorder to check.
- **The session guard** closes every open screen when the signed-in user is signed out, however that
  happened (sign-out, the server ending the session, account deletion). It lives above the navigator
  because a screen that is covered stops listening. Without it a screen such as Create would stay on
  top of the welcome screen.
- **Job polling lives in the shell**, not in a tab, so the bell and the lists stay current wherever
  the user is.
- **On-device state** sits behind three small ports in `domain/local/` with `shared_preferences`
  implementations in `data/local/` and in-memory ones for tests: whether the introduction was seen,
  the song draft, and when Activity was last opened (per account). The draft is stored with its
  owner's id and is only restored for that owner; a draft that belongs to someone else, or that is found
  while nobody is signed in, is erased rather than shown. It is saved 0.6 s after the last edit (a crash in
  that window loses at most that edit). Sign-out and account deletion erase all of it.
- **Widgets read providers; they do not call services.** The bell count is a derived provider
  (`unseenActivityProvider`) over the server's job list and the last-seen time.
- **Truthful art.** `tool/extract_art.py` cuts the artwork out of the references; where the app draws
  an element itself (status bar, language pill, app icon, Popular badge, Watch Demo, a song card's
  play button and title) the pixels under it were filled in by diffusion. See `assets/README.md`.
