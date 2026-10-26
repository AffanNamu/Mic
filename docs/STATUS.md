# Capability status

Legend: **Real** = works end to end in this repository. **Boundary** = the
client side is built and tested against an interface; the real service behind it
does not exist yet, and the shipped app reports that honestly. **Missing** = not
started.

Nothing in this document is marked Real unless it was run.

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
| Voice selection | **Boundary** | Shows only voices returned by the voice service (none today). Not-ready and speech-only voices cannot be chosen, with an explanation. |
| Manage Voices | **Boundary** | List and delete with confirmation, against the voice service interface. Empty state today. |
| Add New Voice (upload) | **Boundary** | Consent capture (own voice vs authorized), file validation, then `enrollVoice`. Fails with "not connected" today. |
| Add New Voice (record in app) | **Missing** | Shown as unavailable. Needs microphone capture and permissions. |
| Credits balance / credits entry point | **Boundary** | Pill and sheet read the credits service; today they show "–" and "not connected". Buying credits is **Missing**. |
| Write with AI | **Boundary** | Sheet, topic input, reviewable suggestion, confirm-before-replace. Today: "The lyrics assistant is not connected in this build yet." |
| AI Improve | **Boundary** | Review sheet (suggestion vs yours) before anything changes. Same "not connected" today. |
| Generate Song | **Boundary** | See below. |
| Back navigation | **Real** | Pops when there is a previous screen; no-op on the root (there is no Home screen yet). |

## Generation boundary (what is proven)

| Behaviour | State | Evidence |
| --- | --- | --- |
| Input validation (title, lyrics, voice, engine support) | **Real** | Unit + widget tests; shown inline and by scrolling to the field. |
| No engine connected → refused, never a fake result | **Real** | `test/application/generation_controller_test.dart`; confirmed in Chromium on the production build. |
| Balance checked before submit; insufficient / unreadable balance blocks | **Real (client)** | Tests. The client only *checks*; it never debits. |
| Credits are charged only on an accepted job | **Missing (server)** | Charging belongs to the backend, which must do it only on acceptance. The client invalidates the cached balance after acceptance. |
| Idempotent submit: same request reuses its key; edits or success mint a new one | **Real (client)** | Tests. **The server must honour the key** (see ARCHITECTURE.md); not verifiable until it exists. |
| Double-tap protection (guard engages before the first await) | **Real** | Test: two taps produce one request. |
| Job states returned on accept (queued / processing) | **Boundary** | Receipt only. |
| Persistent job lifecycle, progress, retries, webhooks, cancel | **Missing** | Phase 3. |
| Song result, playback, library, versions, export | **Missing** | Phase 3. |

## Providers and AI

| Capability | State |
| --- | --- |
| Voice enrollment / cloning provider | **Missing.** Not researched or integrated. |
| Voice-conditioned singing / full-song provider | **Missing.** Not researched or integrated. |
| Lyrics model | **Missing.** |
| Provider capability matrix, routing, fallback, cost accounting | **Missing.** |
| Hausa / Arabic pronunciation evaluation | **Missing.** |
| Proprietary models | **Missing.** None exist; none are claimed. |

No provider claim in this repository has been verified against documentation or
an API, because no provider work has been done.

## Platform and infrastructure

| Item | State |
| --- | --- |
| Backend, database, auth, private audio storage, webhooks, billing | **Missing** |
| Web build (release) | **Real**; built and driven in Chromium. |
| Android build / device test | **Not run.** The container has no Android SDK (`flutter build apk` → "No Android SDK found"). |
| iOS build / device test | **Not run.** Requires macOS and Xcode. |
| Launcher icons (Android/iOS) | **Missing.** Platform projects still use the Flutter default icon; the source art is `assets/brand/deenvoice_icon.png` (web icons are generated from it). |
| Microphone permissions (Android/iOS) | **Not added**, because recording is not implemented. |

## Known deviations from the reference

See [VERIFICATION.md](VERIFICATION.md#remaining-differences-from-the-reference).
