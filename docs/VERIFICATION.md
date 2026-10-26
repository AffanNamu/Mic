# Verification report

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
| Add New Voice | Needs consent and a name; records ownership + UTC time; validates file; shows service errors; "Record now" shown unavailable. |
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
