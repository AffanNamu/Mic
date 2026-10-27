# Capability status

Legend: **Real** = works end to end in this repository. **Real (test double)** =
works end to end, but the music provider behind it was a labelled test double
(a synthetic tone), so it proves the plumbing and says nothing about any AI
provider. **Boundary** = the client side is built and tested against an interface;
the real service behind it is not connected. **Missing** = not started.

Nothing in this document is marked Real unless it was run.

> **Phase 2 headline.** The product plumbing for voice → song exists and is verified
> end to end in a real browser against a real local backend: accounts, consent,
> encrypted storage, credits, persistent jobs, playback, library. **No real AI
> provider has produced a song or a voice profile.** The build environment's network
> policy denies `api.mureka.ai` and `platform.mureka.ai`, and there is no API key,
> authorized participant or Hausa listener. See
> [ACCEPTANCE_PHASE2.md](ACCEPTANCE_PHASE2.md).

## Launch flow, navigation and the other screens (new)

The app now has every screen the references and the brief call for. Where a reference element
promises something that does not exist, the screen shows what is true instead (listed in the
Notes).

| Screen | State | Notes |
| --- | --- | --- |
| Introduction (first launch, 3 pages) | **Real** | Shown once, remembered on the device. It says what the app does and its limits (an AI music engine makes the song; the provider may keep its own copy of a recording; what can be sung depends on the engine). Skip and Get started both record it. |
| Welcome / sign-in (`login.png`) | **Real** | Email sign-in and account creation in the card. **Google and Apple are drawn as designed but disabled and labelled "not available yet"** (not built). The Terms/Privacy sentence appears only when the build supplies both URLs (`--dart-define=TERMS_URL=… PRIVACY_URL=…`); otherwise it says they are not published. The language pill opens a sheet saying English is the only language. **Forgot password?** says plainly that reset is not available (the service cannot send email yet); a real reset is **Missing**. The system Back button steps back (email form → choices; other tab → Home). |
| Home (`home.png`) | **Real (test double)** | Recent songs, songs in progress and Continue Your Work come from the backend and the on-device draft; with no backend each section says so. **Differences from the reference:** "Watch Demo" is "How it works" (written steps; there is no video); "Write Lyrics" says "Write or import your lyrics" (the lyrics assistant is not connected); no "Popular" badge (the app does not know what is popular); the three cover pictures are generic art picked by a hash of the song id (a song has no cover of its own); the avatar is the email's initial (there is no photo). |
| Quick Start templates | **Real** | Set only language and style on the draft, never the user's words. A template whose language the connected engine cannot sing is disabled and says so. |
| Continue Your Work | **Real** | The draft is kept on this device (for its owner only), restored after a restart, and erased on sign-out. It stays until the user discards it. |
| Bell and Activity | **Real (test double)** | The count and the list come from the server's job states (finished and failed songs since the last visit); voices that are processing or failed are listed too. |
| Bottom bar (Home, Create, +, My Voice, Library) | **Real** | Create and + open Create Song over the bar. |
| My Voice tab, Library tab | **Real (test double)** | The same data as before, in tabs. |
| Profile | **Real (test double)** | Account, credits, the engine (named, with why it is unavailable if it is), language, Terms/Privacy (disabled and marked "Not published yet" unless supplied), sign out, delete account. |
| Delete account | **Real (test double)** | Says what is deleted, what is kept and what the provider may keep; asks for the password again; shows the server's own account of what happened; then wipes the session, draft and activity marker from the device. Backend: `DELETE /v1/me`. |

## Create Song screen

| Capability | State | Notes |
| --- | --- | --- |
| Screen UI (header, steps, cards, fields, buttons) | **Real** | Flutter widgets; the only bundled image is the masjid artwork. Tested at six screen sizes and at 1.3x text. |
| Step indicator | **Real** | Advances from the real draft (details → lyrics → voice & style → generate); tapping scrolls to the section. |
| Song type selection | **Real** | Writes to the draft; Nasheed Style applies its template defaults; Instrumental drops lyrics/voice requirements; types an engine cannot do are disabled. |
| Song settings (language, genre, mood, tempo, duration, intensity, instruments) | **Real (local)** | Update the draft. Whether a given engine honours them is decided by its reported capabilities (none connected yet). |
| Lyrics editor | **Real** | 3000-character cap, counter, Arabic right-to-left, mixed Hausa/Arabic/English kept intact. |
| Text import (.txt) | **Real** | Picker, UTF-8 + BOM handling, size limit, confirm-before-replace, truncation notice. |
| Advanced options | **Real UI / Boundary** | Expand/collapse works. Options are enabled only if the connected engine declares support; none is connected, so all show "Unavailable". |
| Voice selection | **Real (test double)** | Shows only voices the backend returns. Not-ready and speech-only voices cannot be chosen, with an explanation. Enrolling voices refresh until ready. |
| Manage Voices | **Real (test double)** | List and delete with confirmation; after deletion the app shows what the provider could *not* remove. Without a backend: empty state. |
| Add New Voice (upload) | **Real (test double)** | The consent wording is the **server's**, shown verbatim; its version is recorded server-side. "Someone who allowed me" requires the speaker's name. Recording is validated server-side (type, size, 5–15 s). Without a backend: "not connected". |
| Add New Voice (record in app) | **Real (verified on web only)** | Records 16-bit mono WAV through the `record` package, shows time and a live level, enforces the engine's stated length (5–15 s here; 5–30 s if none is stated), lets you listen back, and refuses a too-short or silent take with the reason. Nothing leaves the device until you choose Use this recording and the consent boxes are ticked. Driven in real Chromium with a **fake microphone** (a tone): captured, accepted by the backend, enrolled. **Not run on an Android or iOS device**; no human voice has been recorded in a browser here. |
| Credits balance / credits entry point | **Real (test double)** | Pill, sheet and library show the server's ledger balance. Credits are granted by an operator. Buying credits is **Missing**. |
| Write with AI | **Boundary** | Sheet, topic input, reviewable suggestion, confirm-before-replace. Today: "The lyrics assistant is not connected in this build yet." |
| AI Improve | **Boundary** | Review sheet (suggestion vs yours) before anything changes. Same "not connected" today. |
| Generate Song | **Real (test double)** | Creates a persistent server job and follows it. See below. |
| Back navigation | **Real** | Returns to My Songs when a backend is connected; no-op on the root otherwise. |

## Account, library and playback (new in Phase 2; need `--dart-define=API_BASE_URL=…`)

| Capability | State | Notes |
| --- | --- | --- |
| Sign in / create account (email + password) | **Real** | Session survives a reload; expired or rejected sessions return to the welcome screen and close every open screen; sign-out erases the draft and the activity marker from the device. Google/Apple sign-in is **Missing**. Password reset, email verification and MFA are **Missing** (see BACKEND.md). |
| My Library (tab) | **Real (test double)** | Saved songs, songs in progress, and failed attempts with the server's reason. Reopens after reload. |
| Job progress | **Real (test double)** | Shows only the states the server reports; no invented percentage or time estimate. Cancel only while queued. |
| Song player | **Real (test double)** | Streams through a short-lived signed link with Range; shows who made the song ("Made with …"), lyrics (Arabic right-to-left), rename, delete. |
| Without `API_BASE_URL` | **Real** | Exactly the previous unconnected app: every service says it is not connected. |

## Generation boundary (what is proven)

| Behaviour | State | Evidence |
| --- | --- | --- |
| Input validation (title, lyrics, voice, engine support) | **Real** | Unit + widget tests; shown inline and by scrolling to the field. |
| No engine connected → refused, never a fake result | **Real** | `test/application/generation_controller_test.dart`; confirmed in Chromium on the production build. |
| Balance checked before submit; insufficient / unreadable balance blocks | **Real (client)** | Tests. The client only *checks*; it never debits. |
| Credits are reserved only on an accepted job, captured on delivery, released on failure | **Real (server)** | `backend/test/ledger-and-jobs.test.ts`, `worker.test.ts`; the schema itself forbids a second reserve or finalisation per job. |
| Idempotent submit: same request reuses its key; edits or success mint a new one | **Real (client + server)** | Client tests; server: same key and request → same job and one charge, same key with a different request → 422, six concurrent duplicates → one job. |
| Double-tap protection (guard engages before the first await) | **Real** | Test: two taps produce one request. |
| Job states returned on accept (queued / processing) | **Real (server)** | From the backend's own job row. |
| Persistent job lifecycle, retries, recovery, cancel | **Real (server)** | State machine with leases and a deadline; crash recovery tested; an outcome-unknown billable submit is never retried. |
| Webhooks | **Missing** | The worker polls; Mureka webhook support is unverified. |
| Song result, playback, library | **Real (test double)** | Verified in Chromium against the local backend. Versions and export are **Missing**. |

## Providers and AI

| Capability | State |
| --- | --- |
| Provider research | **Real (evidence-tagged).** [PROVIDER_EVALUATION.md](PROVIDER_EVALUATION.md). Done from search summaries because provider hosts are blocked; every claim is tagged by source quality. |
| Voice enrollment / cloning provider | **Adapter written, fails closed.** `MurekaProvider.enrollVoice` refuses until `MUREKA_VOCAL_CLONE_PATH` is set from the official reference. Never run against Mureka. |
| Voice-conditioned singing / full-song provider | **Adapter written, contract unverified.** `POST /v1/song/generate` with `vocal_id` is documented; field names and status values are from memory and must be confirmed with `backend/scripts/mureka-probe.mjs`. Never run against Mureka. |
| A real voice → real song generation | **Not done.** Blocked: network policy, no API key, no authorized participant. |
| Lyrics model | **Missing.** (Write with AI still says "not connected".) |
| Provider routing, fallback | **Missing.** Deliberately one provider until one flow works. |
| Cost accounting | **Real (estimates).** Rate-card estimates per job; reconcile with an invoice. |
| Hausa / Arabic singing | **Unsupported by every researched provider on the evidence found;** untested. The app does not offer Hausa when the engine does not declare it. |
| Proprietary models | **Missing.** None exist; none are claimed.

## Platform and infrastructure

| Item | State |
| --- | --- |
| Backend: auth, database, migrations, encrypted private storage, jobs, ledger, account deletion | **Real** ([BACKEND.md](BACKEND.md)); 189 tests. Single-node SQLite. |
| Webhooks, payments | **Missing** |
| Web build (release) | **Real**; built and driven in Chromium. |
| Android build / device test | **Not run.** The container has no Android SDK (`flutter build apk` → "No Android SDK found"). The release manifest now declares `INTERNET` (needed to reach the backend); cleartext `http://` backends need `usesCleartextTraffic` and are for development only. |
| iOS build / device test | **Not run.** Requires macOS and Xcode. |
| Store compliance | **Partly.** Account deletion in the app and on the server exists (an app-store requirement). **Not done:** published Terms of Service and Privacy Policy pages (the app links to them only if the build supplies URLs), a data-safety / privacy-label declaration, and age rating. |
| Launcher icons (Android/iOS) | **Missing.** Platform projects still use the Flutter default icon; the source art is `assets/brand/deenvoice_icon.png` (web icons are generated from it). |
| Microphone permissions (Android/iOS) | **Declared** (`RECORD_AUDIO`, `NSMicrophoneUsageDescription`), never exercised on a device. A refusal is shown to the user with a retry. |

## Known deviations from the reference

See [VERIFICATION.md](VERIFICATION.md#remaining-differences-from-the-reference).
