# Verification report

> Sections run in the order the work was done: Milestone 1 (Create Song), Phase 2 (backend and
> client wiring), then the **UI milestone** (introduction, welcome, Home, tabs, recording, account
> deletion) at the end of this file, which has the latest numbers.

Everything below was run in this repository's cloud container. Numbers are from
the final runs.

## Environment

| | |
| --- | --- |
| Flutter / Dart | 3.47.8 (stable) / 3.13.7 |
| OS | Ubuntu 24.04 (cloud container) |
| Browser used | Playwright Chromium (software GL) |
| Android SDK | **not installed** |
| Xcode | **not available** (not macOS) |

## Commands run and results

| Command | Result |
| --- | --- |
| `dart format --output=none --set-exit-if-changed lib test tool` | 55 files, 0 changed, exit 0 |
| `flutter analyze` | No issues found (strict-casts, strict-raw-types, extra lints) |
| `flutter test --coverage` | **152 passed, 0 failed**; `lib/` line coverage **96.4%** (1649/1710) |
| `flutter build web --release --no-web-resources-cdn` | Built (~27 s) |
| `flutter build web … -t tool/preview/preview_main.dart -o build/web_preview` | Built (preview with fixtures, for visual comparison only) |
| `node tool/web_flow_check.mjs build/web …` | **12/12** real-browser flow checks passed, no page errors |
| `flutter build apk --debug` | **Failed: "No Android SDK found."** No Android result is claimed. |
| `flutter doctor` | Android toolchain ✗ (no SDK), Chrome ✗ (not at `google-chrome`; Chromium used via Playwright), Linux desktop ✗ (GTK dev libs) |

### Test suite (152 tests)

- **Domain (22):** validation rules, step progress, draft equality/copy, voice
  profile states, text-direction detection.
- **Application (40):** voice default selection, draft notifier, and the
  **generation boundary** (26): unconfigured defaults, validation before any
  backend call, no engine → refused, credit checks (insufficient / exact / read
  failure), accepted request contents, the client never debits, balance refresh,
  failure messages, idempotency (retry keeps key, edit or success changes it),
  state transitions, double-tap protection.
- **Data (10):** UTF-8 + BOM decoding, size limits, accepted audio formats, voice
  profile value semantics.
- **Widgets (79):** every interactive element (see below), the shipped
  "no backend" behaviour, no overflow at six screen sizes and 1.3x text, text
  scale capping, semantics (labels, buttons, selected state, headers),
  contrast ≥ 4.5:1 for text colours, the stepper's real progression and
  scroll-to-section, back navigation.
- **Render (1):** writes a screenshot used by the comparison tool.

**Mutation check.** To confirm the tests can fail, five behaviours were broken on
purpose and the relevant tests confirmed to fail by assertion (then restored):
engine pretending to be available, credit check skipped, idempotency key never
reused, title validation removed, double-submit guard removed.

### Real-browser flows (production build, no fixtures)

Driven through the browser's accessibility tree: load; credit pill honest when
billing is unavailable; no fictional voices; Generate on an empty form lists the
missing items; typing title and lyrics; song type selection; **Generate with no
engine is refused with "no generation engine is connected" and no receipt**;
credits entry point reports the missing billing service; Write with AI reports
the assistant as not connected; Add New Voice shows the consent requirement;
Manage Voices shows an honest empty state; Advanced Options are disabled with a
reason. Screenshots: `docs/verification/flows/`.

## Interactive element audit

| Element | Verified behaviour |
| --- | --- |
| Back | Pops to the previous screen; harmless on the root (no Home screen exists yet). |
| Credits pill and "+" | Show the real balance (or "–" when unavailable); open the credits sheet; refresh re-reads. Purchase is explicitly "not available in this build". |
| Song type cards | Select; Nasheed Style applies template; Instrumental removes voice/lyrics requirement; unsupported types disabled with the engine named. |
| Voice cards | Select real profiles; not-ready and speech-only voices explain why they can't be chosen; row scrolls with many voices. |
| Manage Voices | Lists voices; delete needs confirmation and calls the repository; system voices not deletable; empty state. |
| Add New Voice | Needs consent and a name; records ownership + UTC time; validates file; shows service errors; "Record now" opens the in-app recorder. |
| Record your voice | Idle → recording (time, level, minimum-length hint) → review (listen back) → use or record again. Too-short and silent takes are refused with the reason; a refused microphone is explained and can be retried; leaving mid-recording discards the audio; every control is its own labelled semantics node (checked in the semantics tree after a real browser showed them merged). |
| Lyrics | Input, counter, 3000 cap, RTL for Arabic, mixed text preserved. |
| Import Text | Replaces after confirmation; truncation notice; empty/invalid file messages; cancel is a no-op. |
| Write with AI / AI Improve | Reviewable suggestion, nothing applied until accepted; "not connected" shown when unconfigured; user's text untouched on failure. |
| Language and six setting pickers | Open a sheet, write the choice to the draft. |
| Advanced Options | Expand/collapse; only engine-supported options editable; others labelled with why. |
| Generate Song | Validates inline (scrolls to first problem); busy state; refused with a truthful message if no engine; receipt sheet only on a real (test-double) acceptance. |

## Generation boundary: what is and is not proven

- **Proven:** with the shipped services the app cannot produce a receipt, fake
  completion, or success message; validation, balance check, idempotent key
  handling and double-submit protection behave as described in
  [ARCHITECTURE.md](ARCHITECTURE.md).
- **Not proven (no backend):** that credits are charged only on acceptance, that
  the server honours the idempotency key, and any real job-state transition. The
  client never debits; it only checks the balance and refreshes it after
  acceptance. These must be verified against the real backend.
- Test doubles (`test/support/fakes.dart`) are the only source of receipts, and
  they are test-only.

## Visual comparison with the reference

Method: the real Flutter app (web release build) in Chromium at 426 × 923 CSS px
@2x = **852 × 1846**, the reference's exact size, compared with
`tool/compare_render.py`. The preview build injects fixtures (120 credits, three
voices, two avatar photos cropped from the reference) so the same state can be
compared. Images: `docs/verification/create_song_reference_vs_app.png`.

| Region (reference px) | SSIM | Mean abs. error (0–255) |
| --- | --- | --- |
| Whole image | **0.756** | 12.2 |
| Header 0–415 | 0.785 | 11.3 |
| Song type 415–690 | 0.705 | 14.4 |
| Voice 690–940 | 0.694 | 15.0 |
| Lyrics 940–1220 | 0.792 | 8.5 |
| Details 1220–1600 | 0.744 | 12.3 |
| Advanced + generate 1600–1846 | 0.783 | 12.6 |

SSIM is limited by anti-aliasing and font-rendering differences even when
layout matches, so it is evidence, not a pass mark. Better evidence is
geometric. Horizontal border lines in the middle of the screen (px):

| Edge | Reference | App |
| --- | --- | --- |
| Panel top | 416 | 416 |
| Type cards top / bottom | 486 / 654 | 486 / 653 |
| Section divider | 680 | 680 |
| Voice cards top / bottom | 748 / 917 | 748 / 917 |
| Lyrics box top / bottom | 1006 / 1198 | 1007 / 1199 |
| Title field top / bottom | 1283 / 1358 | 1283 / 1358 |
| Advanced Options top | 1617 | 1618 |

Text elements measured (title, subtitle, wordmark, tagline, step labels,
section headings, hints, Song Lyrics, counter, Song Details, field labels,
Advanced Options): within **±2 px** of the reference, with widths within
1–3.5%. (A few measurements, such as "Full Song" title, "Manage Voices" text and
the Generate label, overlap icons/borders in the tool's search window and are
not reliable; they were checked visually instead.)

### Remaining differences from the reference

1. **Fonts are approximations.** The serif is Playfair Display and the sans is
   Inter (both OFL, bundled), sized to match measured text widths. The
   reference's faces are not identical; the Generate Song label in particular
   looks lighter and slightly smaller than the reference's.
2. **Icons.** Lucide icons plus three custom painters (dome, oud, bars). Stroke
   weight, glow and the finer details (e.g. grill lines on the microphone, the
   oud's ornament, the sparkle beside the Generate star) differ.
3. **Masjid artwork is a raster extracted from the reference** at its native
   412 × 300 px (shown at 2x). It is the real illuminated scene including the
   golden arch frame, but it is low-resolution for 3x devices, and a small
   region behind the credits pill was inpainted (hidden by the live pill). The
   original high-resolution artwork was not available; supplying it is a
   drop-in replacement (`assets/art/masjid_header.webp`).
4. **Header texture and glows are approximations**: a generated khatam-style
   lattice, simplified card/button glows, and a gradient fill instead of the
   reference's exact lighting.
5. **Lyrics placeholder** is about 3 pt (6 px) higher on web than in the
   reference; on the mobile text engine it matched within 1 px.
6. **Avatars.** The reference's photos appear only in test/preview fixtures.
   The real app shows profile photos when a voice has one, otherwise initials
   (or a microphone for system voices), never invented people.
7. **Field-height inconsistencies in the reference** (Title and Language boxes
   differ in the mock) were normalised to one height.
8. **Sheets, dialogs and the Manage Voices screen** are not in the reference;
   they follow the same palette and type but are original.

## Platform verification still required

- **Android:** install the Android SDK (`ANDROID_HOME`), then
  `flutter build apk --debug` and run on an emulator and a physical phone,
  checking the status-bar inset, keyboard behaviour, text scaling and
  performance. Not done.
- **iOS:** needs macOS + Xcode; same checks. Not done.
- **Web:** verified only in Chromium (software GL). Safari and Firefox were not
  tested.
- **Real device text rendering and the 3x artwork softness** can only be judged
  on hardware.


---

# Phase 2 verification (backend, client wiring, full journey)

Everything below was run in this container. **The music provider in every end-to-end run was a
labelled test double** (a synthetic tone); none of it is evidence about a real AI provider. See
[ACCEPTANCE_PHASE2.md](ACCEPTANCE_PHASE2.md).

| Command | Result |
| --- | --- |
| `cd backend && npm test` | 173 passed, 0 failed |
| `cd backend && npm run typecheck` | clean |
| `dart format --output=none --set-exit-if-changed lib test tool` | 0 changed |
| `flutter analyze` | No issues found |
| `flutter test --coverage` | 220 passed, 0 failed; `lib/` line coverage 91.5% |
| `flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:18080 -o build/web_e2e` | Built |
| `node tool/web_e2e_backend.mjs build/web_e2e docs/verification/backend_e2e` | **15/15** checks, no page errors (test-double provider); includes recording from a Chromium fake microphone and enrolling it |

## Mutation checks

Confidence that the tests can fail: the source was deliberately broken, one behaviour at a time, and the
whole suite run each time.

- Backend, 20 breakages: no balance check on reserve; idempotency lookup skipped; request-hash check
  removed; unknown-outcome submit retried; crashed `submitting` job resubmitted; any bytes accepted as a
  song; no refund on failure; no capture on success; bad credentials do not block the provider; job
  deadline ignored; consent not required; recording kept on voice delete; provider "unsupported" deletion
  reported as deleted; media signature unchecked; song ownership unchecked; auth hook removed; 5xx on a
  write treated as safe to retry; download URL unvalidated; sessions never expire; default job lease shorter than a provider step → **20/20 caught**, each by a named test (the last one only after a config test was added: it survived at first).
- Flutter, 14 breakages: submit without the idempotency key; 401 not signing out; expired stored session
  trusted; previous user's draft kept after sign-out; failed job shown as ready; enrollment without the server's
  consent version; unavailable engine reported available; add-voice sheet ignoring the server consent text;
  enrolling voices never re-checked; failed jobs hidden from the library; delete disclosure dropped; lost
  connection hiding that the outcome is unknown; lyrics invisible to assistive technology; Arabic lyrics laid out
  left-to-right → **14/14 caught**, each by the test written for it.

  *How this was made trustworthy.* The first run of this check was **invalid**: the baseline suite was already
  failing (a test still referred to a widget I had replaced), so every mutation "failed" and looked caught. The
  harness now refuses to run unless the baseline is green and reports the specific failing test. The corrected run
  found one mutation that **survived** — nothing tested that the lyrics are exposed to screen readers, the very
  defect found earlier in the browser — and one that did not compile. A semantics test was added (and confirmed
  to fail on the old code), and the other mutation was redone.

Defects found by the new tests and fixed during this phase (kept here because they show what the tests are for):
numeric config values were validated after the "any problems?" check, so a bad `PORT` slipped through;
validation ran before authentication, so anonymous callers got schema errors and the server parsed their
bodies; Fastify's default validator silently dropped unknown fields and coerced types; a refused connection
was not recognised as "nothing was sent"; an oversized provider response was swallowed into a generic
"bad response"; the rename dialog disposed its text controller while still animating closed; the lyrics on the
player and the "song is ready" message were invisible to assistive technology (found by dumping the
accessibility tree in Chromium, not by looking at screenshots).

## Real-browser journey against the local backend

`tool/web_e2e_backend.mjs` starts `backend/test/support/e2e-server.ts` (the backend with the test double, on a
fixed port) and a static server for the web build, then drives Chromium through the accessibility tree:

sign-in screen when signed out → create account (client-side password rule) → operator grants credits → **reload:
session persisted, real balance** → Create Song (no voices) → Add New Voice shows the **server's** consent text →
upload a 10 s WAV (file chooser) → "Processing…" → "Personal voice" → Generate with the default language (Hausa)
refused as unsupported by the engine → choose English → Generate → job followed through real stages → "Your song
is ready" → Play → "Made with test-double", lyrics shown, `<audio>` fetched the signed URL with `Range`
(`206 audio/wav`), position advanced → unsigned media URL is 403 → **reload → song still in My Songs → plays
again** → credits 3 → 2 (reserved, then captured) → sign out → a second account sees no songs.

*(Superseded by the UI-milestone journey below, which has 19 checks.)*

Limits: Chromium with software GL only; web only; the audio is a tone; no Android/iOS run.

---

# UI milestone verification (introduction, welcome, Home, shell, recording, deletion)

Everything here was run in this container. The music provider in every end-to-end run was the labelled
test double, so none of it says anything about a real AI provider; the microphone in the browser run was
Chromium's fake device playing a tone, so no human voice was recorded; no Android or iOS build was made.

| Command | Result |
| --- | --- |
| `cd backend && npm test` | 189 passed, 0 failed |
| `cd backend && npm run typecheck` | clean |
| `dart format --output=none --set-exit-if-changed lib test tool` | 0 changed |
| `flutter analyze` | No issues found |
| `flutter test --coverage` | **514 passed, 0 failed**; `lib/` line coverage 93.7% (4310/4601) |
| `flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:18080 -o build/web_e2e` | Built |
| `node tool/web_e2e_backend.mjs build/web_e2e docs/verification/backend_e2e` | **19/19** checks, no page errors (test-double provider) |
| `node tool/web_flow_check.mjs build/web …` (production build, no backend) | **16/16** checks, no page errors |

## What the new tests cover

- **Launch flow** (`launch_flow_test.dart`, 24): the introduction page by page, what it says (no promise of a
  result; the provider-copy limit), Skip and Get started record it, it is not shown twice, a device that cannot
  say whether it was seen still opens the app; which screen opens with and without a backend; on the welcome
  screen Google and Apple are disabled and say so, email is the way in, the Terms sentence appears only when
  both pages exist, links open them or say they could not, the language sheet, the form above the keyboard.
- **Home and the bottom bar** (`home_test.dart`, 31): every shortcut goes where it says; no demo video; real songs,
  songs in progress and failures; a template changes only language and style and is disabled when the engine
  cannot sing its language; the draft is offered, restored, discarded (after asking), never shown to another
  user; the bell; tab switching with the right selected state; Create and + over the bar.
- **Activity** (13): every state worded from the server's report, what was new stays marked while the bell clears,
  per account; the unseen count (counts only songs that finished or failed since the last visit).
- **Profile and deletion** (11 + 10): the account, credits, the engine's real state, the legal links, sign-out
  (asks first, erases the draft), and deletion (says what is deleted, kept and held by the provider; a wrong password
  is explained and signs nobody out; locked while running; on success the server's disclosure is shown, then the
  device is wiped and every screen closed).
- **Tabs** (10): voices and Library, including a voice deleted in one tab being gone from Create Song.
- **Layout** (120): nine screens × six screen sizes × two text scales, none overflowing.
- **On-device state**: draft codec (5), preference stores (7), draft persistence (15): debounce, owner scoping,
  a slow restore never overwriting what was typed, sign-out erasing everything.
- **Recording** (`record_voice_test.dart` and friends): see the in-app recording rows in STATUS.md. A real browser
  showed that the timer, hint and Stop control were merged into one accessibility node; the test that now guards
  it fails without the fix.

## Visual comparison with the references

Widget-test renders at the reference size (426 × 923 @2x) against `design/reference/login.png` and `home.png`
(`tool/compare_render.py`, side-by-sides in `docs/verification/screens/`). The status bar and home indicator are
drawn by the operating system, so the renders include insets rather than the references' pictures of them.

| | Result |
| --- | --- |
| Welcome, hero (arch and mosque) | SSIM 0.93 |
| Welcome, whole image | SSIM 0.78; text widths within 1–2 % and rows within 0–8 px of the reference |
| Home, header / tiles | text widths 99–101 %, rows within 2–5 px |
| Home, whole image | SSIM 0.60 |

Home's number is low for stated reasons, not hidden ones: the reference shows a photo avatar and a different
order of cover pictures, "Watch Demo" is "How it works", "Write Lyrics" has a different second line, there is no
"Popular" badge, and the reference's song titles and languages are invented. Element positions and widths are the
better measure. Remaining differences: the Welcome arch is hand-drawn in code and not identical; Google and Apple
are dimmed because they are disabled; the cover pictures are screenshot resolution (soft on 3x displays).

## Defects the checks found (kept because they show what the checks are for)

- In a **real browser** the recorder's Stop control could not be found by assistive technology: Flutter had merged
  the timer, the hint and the control into one node. Widget tests that tapped by text had passed. Fixed; a semantics
  test now fails without the fix.
- A **scan of the whole database** after account deletion found the voice's display name still stored on songs.
  Fixed in account, song and voice deletion.
- Activity changed a provider while the screen was being built (caught by the render test, not by looking).
- The hero card overflowed at 1.3× text and at 320 px wide.
- The production flow script (and the preview entry point) assumed the app opens on Create Song; both were
  updated for the launch flow.

## Mutation checks on the new logic

**Flutter, 20 deliberate breakages of the new logic: 20/20 caught**, each by a named test: another user's saved draft
restored; a slow restore overwriting what was typed; an empty draft saved as "work"; discard leaving the draft on the
device; a draft saved while nobody is signed in; sign-out keeping the draft, and keeping the activity marker; songs still
being made counted as unseen; the last visit ignored; a visit never remembered; the introduction not remembered, and never
shown; the welcome screen claiming agreement to a Terms page that does not exist; Quick Start offering a language the
engine cannot sing; a default draft shown as work to continue; the device not wiped after deleting the account; open
screens staying over the welcome screen after the session ends; the draft codec accepting any version; the account DELETE
sent without the password; Google sign-in looking available; "yesterday" computed wrongly. The run was made in two parts
(the first was too slow, so it was interrupted after three results and finished against the test files that cover each
breakage; any breakage those files missed would have been re-run against the whole suite, and none needed to be).

**Backend, 15 breakages of the account-deletion code: 15/15 caught.** One survived the first time: scrubbing the voice
name from songs was redundant with `deleteSong` doing it already, so no test could tell. A test using a row from before
the fix was added, and the breakage is now caught.


## Real-browser journey, UI milestone (19 checks)

`tool/web_e2e_backend.mjs`, same set-up as above, now: the introduction on first launch → Welcome (Google/Apple shown
disabled with their note) → create an account → reload (session persists, introduction does not return) → Profile shows
the real balance and "Not published yet" for Terms and Privacy → Create Song → consent text from the server → upload a
sample → **record from a Chromium fake microphone** and enroll it (the server sees one more voice) → Hausa refused →
**reload: the draft is in the browser's storage, Home offers it, Continue brings the words back (the counter reads
40/3000)** → English → generate, follow, play (Range, position advances) → unsigned media link 403 → reload: the song is on
Home and the bell says "Activity, 1 new" → Activity lists it and opening it clears the bell and stores the time → Library
and My Voice show the real data → credits 3 → 2 → **sign-out asks first and erases the draft, activity marker and
session from local storage** → sign in again → **delete the account: a wrong password is explained and deletes nothing; the
right one shows the server's disclosure, empties private storage, wipes the device and the old credentials no longer sign
in**. 19/19, no page errors. The production build with no backend: 16/16 (`tool/web_flow_check.mjs`).

Limits: Chromium with software GL only; web only; the audio is a tone and the microphone a fake device; no Android or iOS
run of the app itself (the GitHub build workflows below only compile it).

## What the GitHub workflows have shown

See [CI.md](CI.md#what-is-and-is-not-verified): the Android release APK, the unsigned iOS build and the web build compiled on
GitHub before in-app recording was added; they are re-run on the current head and the result recorded there.
