# DeenVoice

AI nasheeds for a brighter Ummah. A Flutter app for creating Islamic devotional
songs with AI, including singing in a user's own authorized voice.

> **Status: foundation + Create Song screen.** The Create Song screen is built,
> wired to real application state, and verified. **No backend, AI provider,
> authentication or billing is connected yet**, so nothing can be generated.
> The app says so plainly instead of pretending. See [docs/STATUS.md](docs/STATUS.md)
> for exactly what is real, what is only a boundary, and what is missing.

## What exists

- The **Create Song** screen, built from the supplied design reference
  (`design/reference/create_song.png`): masjid-artwork header, four-step progress
  indicator, song-type cards, voice selection, lyrics editor, song details,
  advanced options, and the Generate Song action.
- A typed domain model (song draft, voice profiles, generation capabilities,
  validation) and Riverpod application state behind it.
- Honest integration boundaries for voices, credits, the lyrics assistant and
  song generation. In this build they are `Unconfigured*` services that return
  empty data or fail with a clear "not connected" message.
- Voice upload entry with explicit consent capture, voice management, text
  import, and all pickers/sheets the screen needs.
- 152 automated tests (96% line coverage of `lib/`) plus real-browser checks.

## What does not exist yet

Authentication, backend, voice enrollment and singing/music providers, lyrics
assistant, credits and billing, in-app recording, generation progress, the song
library, and Android/iOS verification. See [docs/ASSESSMENT.md](docs/ASSESSMENT.md)
for the plan and risks.

## Run it

Requires the Flutter SDK (developed on 3.47.8 / Dart 3.13.7).

```sh
flutter pub get
flutter run -d chrome          # or any connected device
flutter test                   # 152 tests
flutter analyze
```

`lib/main.dart` is the shipped entry point and shows only real data, which today
means: no voices, credits unavailable, generation unavailable.

### Visual verification (design reference vs the real app)

```sh
# 1. Build the real app, with fixture data matching the reference state.
#    tool/preview/preview_main.dart is NOT shipped; it injects test doubles.
flutter build web --release --no-web-resources-cdn \
    -t tool/preview/preview_main.dart -o build/web_preview
cp -r test/fixtures/avatars build/web_preview/preview_avatars

# 2. Screenshot it in Chromium at the reference size (852x1846 = 426x923 @2x).
node tool/web_capture.mjs build/web_preview build/renders/web_preview.png

# 3. Measure element positions/sizes and similarity against the reference.
python3 tool/compare_render.py build/renders/web_preview.png

# Real-browser user flows against the production build (no fixtures):
flutter build web --release --no-web-resources-cdn
node tool/web_flow_check.mjs build/web build/renders/flows
```

Needs Node with `playwright` and Pillow/NumPy for the Python tool. Results are in
[docs/VERIFICATION.md](docs/VERIFICATION.md).

## Layout

```
lib/
  main.dart            shipped entry point
  app/                 MaterialApp, theme, text-scale policy
  core/                design tokens, shared widgets, icons
  domain/              entities, validation, service interfaces (no Flutter UI)
  data/                Unconfigured* services, file pickers
  application/         Riverpod providers, draft + generation controllers
  presentation/        screens, sheets, widgets
test/                  unit, application, widget and render tests (+ fakes)
tool/                  verification scripts (not part of the app)
design/reference/      the supplied design images (the visual specification)
assets/                masjid artwork, fonts (OFL), brand icon source
docs/                  status, architecture, assessment, verification
```

## Documents

- [docs/STATUS.md](docs/STATUS.md) — capability matrix: real vs boundary vs missing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers, boundaries, backend contract
- [docs/ASSESSMENT.md](docs/ASSESSMENT.md) — repository assessment, provider feasibility, risks, next milestone
- [docs/VERIFICATION.md](docs/VERIFICATION.md) — what was run, results, remaining differences
- [assets/README.md](assets/README.md) — provenance and limits of the artwork and fonts
