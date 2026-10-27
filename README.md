# DeenVoice

AI nasheeds for a brighter Ummah. A Flutter app for creating Islamic devotional
songs with AI, including singing in a user's own authorized voice.

> **Status: Phase 2 — the voice → song plumbing exists and is verified; no real AI provider
> has produced a song yet.** A backend (`backend/`) owns accounts, voice consent, encrypted
> storage, credits, persistent generation jobs and all provider credentials. The Flutter app
> can sign in, add a voice with server-owned consent, create a song, follow the job, play it
> and reopen it from My Songs — **verified in Chromium against a real local backend, with a
> labelled test double standing in for the music provider** (a synthetic tone). A real
> provider (Mureka) has an adapter that fails closed and has **never been run**: the build
> environment blocks its hosts. Acceptance requires a real authorized voice and a real
> provider; see [docs/ACCEPTANCE_PHASE2.md](docs/ACCEPTANCE_PHASE2.md) for exactly what is
> proven, what is blocked and how to unblock it, and [docs/STATUS.md](docs/STATUS.md) for
> the capability matrix.

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
- Automated tests for the app (see [docs/VERIFICATION.md](docs/VERIFICATION.md)) and 173 for the
  backend, plus real-browser checks.

- **Backend** (`backend/`, [docs/BACKEND.md](docs/BACKEND.md)): auth, consent records, encrypted
  private storage, append-only credit ledger, idempotent persistent jobs with crash recovery,
  signed audio links, operator metrics; a fail-closed Mureka adapter; scripts and a runbook
  ([docs/poc/](docs/poc/README.md)) for the live proof of concept.
- Sign-in, **My Songs** library, job progress and a song player in the app (only when a
  backend is configured).
- [docs/PROVIDER_EVALUATION.md](docs/PROVIDER_EVALUATION.md): evidence-tagged comparison of
  seven providers and a one-provider recommendation.

## What does not exist yet

A verified real provider integration (the Mureka contract and voice-cloning path are
unconfirmed), any Hausa or Arabic singing result, a lyrics assistant, payments/buying
credits, in-app recording, webhooks, Google/Apple sign-in, and Android/iOS verification.
See [docs/ACCEPTANCE_PHASE2.md](docs/ACCEPTANCE_PHASE2.md) and
[docs/ASSESSMENT.md](docs/ASSESSMENT.md).

## Run it

Requires the Flutter SDK (developed on 3.47.8 / Dart 3.13.7).

```sh
flutter pub get
flutter run -d chrome          # or any connected device
flutter test
flutter analyze
```

`lib/main.dart` is the shipped entry point and shows only real data. With no backend
configured that means: no voices, credits unavailable, generation unavailable. To connect a
backend, build with `--dart-define=API_BASE_URL=http://localhost:8080` (and run `backend/`,
see [docs/BACKEND.md](docs/BACKEND.md); the backend's `CORS_ORIGINS` must include the web
origin).

### Backend and full-journey checks

```sh
cd backend && npm ci && npm test      # 173 tests
cd .. && flutter build web --release --no-web-resources-cdn \
    --dart-define=API_BASE_URL=http://127.0.0.1:18080 -o build/web_e2e
node tool/web_e2e_backend.mjs build/web_e2e docs/verification/backend_e2e
```

The last command starts a local backend **with the labelled test double** and drives the app
in Chromium. It proves the plumbing, not any provider.

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

## CI/CD

GitHub Actions workflows for tests, Android, iOS and web builds are in `.github/workflows/`;
setup, required secrets and what is and is not verified are in [docs/CI.md](docs/CI.md).

## Layout

```
lib/
  main.dart            shipped entry point
  app/                 MaterialApp, theme, text-scale policy
  core/                design tokens, shared widgets, icons
  domain/              entities, validation, service interfaces (no Flutter UI)
  data/                Unconfigured* services, api/ (HTTP client + services), audio/, file pickers
  application/         Riverpod providers, session, draft + generation controllers
  presentation/        screens, sheets, widgets
test/                  unit, application, widget and render tests (+ fakes)
backend/               the server: API, jobs, ledger, storage, provider adapters, its own tests
tool/                  verification scripts (not part of the app)
design/reference/      the supplied design images (the visual specification)
assets/                masjid artwork, fonts (OFL), brand icon source
docs/                  status, architecture, backend, provider evaluation, PoC runbook,
                       Phase 2 acceptance, assessment, verification
```

## Documents

- [docs/STATUS.md](docs/STATUS.md) — capability matrix: real vs boundary vs missing
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — layers, boundaries, backend contract
- [docs/ASSESSMENT.md](docs/ASSESSMENT.md) — repository assessment, provider feasibility, risks, next milestone
- [docs/VERIFICATION.md](docs/VERIFICATION.md) — what was run, results, remaining differences
- [assets/README.md](assets/README.md) — provenance and limits of the artwork and fonts
