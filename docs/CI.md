# CI/CD

Four GitHub Actions workflows in `.github/workflows/`, adapted from the eSportlyic samples
(Android, iOS, web deploy). They are **linted** (actionlint + shellcheck) but **have not yet
run on GitHub** — the first run is the real test. See "What is and is not verified".

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `ci.yml` | every push and PR | Flutter: format, analyze, test, release web compile. Backend: typecheck + tests. On `main` / manual: the browser journey (Chromium against a local backend that uses the **labelled test double**) |
| `android.yml` | `main`, PRs and manual, when app/Android files change | Release APK; with a keystore also a signed AAB for Play. Refuses to call a debug-signed build a release |
| `ios.yml` | `main` and manual | Without signing secrets: compile check (`--no-codesign`). With them: signed App Store IPA. TestFlight upload only when you ask for it |
| `web.yml` | `main`, PRs and manual, when app/web files change | Release web build against the real backend URL, kept as an artifact. **No deploy yet** |

## One-time setup

**Repository variable** (Settings → Secrets and variables → Actions → *Variables*):

| Name | Value |
| --- | --- |
| `API_BASE_URL` | Public `https://` URL of the DeenVoice backend. Not a secret. The backend's `CORS_ORIGINS` must include the origin the web app is served from |

Signed Android and iOS builds **fail** if this is missing or not `https://`, so you cannot
publish an app that says "not connected". Provider keys (e.g. Mureka) never go in any workflow
or in the app; they live only in the backend's environment.

**Android secrets** (for a signed release / Play AAB):

| Secret | How to get it |
| --- | --- |
| `KEYSTORE_B64` | `keytool -genkeypair -v -keystore release.keystore -alias deenvoice -keyalg RSA -keysize 2048 -validity 10000`, then `base64 -w0 release.keystore` |
| `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` | From that command |

Keep the keystore backed up somewhere safe: losing it means you cannot update the app (unless
you use Play App Signing and an upload key). Locally, put the same values in
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`; git-ignored).

**iOS secrets** (for a signed IPA; the bundle ID is `app.deenvoice.deenvoice`, change it in the
Xcode project and in `ios.yml` if you want another):

| Secret | How to get it |
| --- | --- |
| `IOS_DIST_CERT_P12_B64`, `IOS_DIST_CERT_PASSWORD` | Apple Distribution certificate exported as `.p12`; `base64 -i cert.p12` |
| `IOS_PROVISION_PROFILE_B64` | App Store provisioning profile for the bundle ID; `base64 -i profile.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Any throwaway string for the temporary CI keychain |
| `ASC_API_KEY_ID`, `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8_B64` | Only for TestFlight upload: App Store Connect → Users and Access → Keys; `base64 -i AuthKey_XXXX.p8` |

Unlike the sample, the team ID and profile name are read from the profile itself, so they are not
separate secrets. The workflow fails early, with a clear message, if the profile's App ID does not
match the bundle ID.

## How it differs from the samples (and why)

- **Tests run on every push/PR.** The samples only build on `main`; there was no analyze/test gate.
- **Debug-signed builds are never mistaken for releases.** The project's Gradle config now reads
  `KEYSTORE_PATH`/`STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD` (or `android/key.properties`) and
  otherwise falls back to the debug key; the workflow verifies the signer and fails if a keystore was
  provided but the APK/AAB carries the debug key. The AAB is only built when real signing material exists.
- **iOS never publishes by itself.** A push to `main` builds (and signs if secrets exist); uploading to
  TestFlight is a manual run with `upload_to_testflight`. The sample uploaded automatically.
- **Signing material is removed** from the runner at the end (`if: always()`).
- **Plain `actions/checkout`**, built-in caches (`setup-java cache: gradle`, `flutter-action cache`,
  `setup-node cache: npm`) instead of hand-rolled checkout-with-retries and cache steps; PRs trigger
  the cheap (Linux) workflows.
- **No web deploy yet.** The sample deployed to Firebase Hosting; DeenVoice's hosting target has not
  been chosen. Tell me where it should go and I will add the deploy job.
- Flutter is pinned to **3.47.8**, the version this repo was developed and tested on.

Things in the samples that do **not** apply here and were left out: Cloudinary, Flutterwave, Supabase,
Firebase/AdMob/Google Sign-In plist and Info.plist patching, the hand-written Podfile (Swift Package
Manager stays enabled), the custom `HighlightCompressionEngine.swift`, `flutter_launcher_icons`
(DeenVoice's launcher icons are not generated yet; see STATUS.md), and `--no-tree-shake-icons`.
If you reuse the web sample elsewhere: `--web-renderer html` no longer exists in current Flutter
(`flutter build web --web-renderer` fails with "Could not find an option named --web-renderer" on 3.47.8).

## What is and is not verified

Verified here:
- All four files pass `actionlint` with `shellcheck` enabled.
- The commands the workflows run for Flutter and the backend (format, analyze, test, `flutter build web`,
  `npm ci`/typecheck/test, the browser journey) were run in this repository's container with the same
  flags and passed.
- `tool/check_16kb_alignment.sh` was tested on libraries built with 4 KB and 16 KB alignment (detects
  both, ignores 32-bit, `--strict` exits 1).
- The iOS profile-specifier patch was run against the real `project.pbxproj`: it changes exactly the three
  Runner configurations and not `RunnerTests`, and survives a profile name containing quotes and slashes.

**Not verified** (no Android SDK, no macOS, no GitHub run available here):
- The Gradle signing change (`android/app/build.gradle.kts`) has not been built. It is the standard
  `key.properties`/env pattern, but the first Android CI run is its first test.
- The iOS signing flow, the `macos-26` runner label and its Xcode version, `PlistBuddy` parsing of the
  profile, and `altool` upload. These follow the fixes in your working sample but have not run for DeenVoice.
- `GITHUB_ENV`-passing of secrets-derived values and the `secrets.X != ''` flags only behave as intended
  on GitHub.

If any workflow fails on its first run, send me the log; the likely suspects are listed above.

## Not included

Deploying the backend (it needs a host, a managed database/object storage and its own secrets: see
BACKEND.md), store submission (Play/App Store listing), and the real-provider proof of concept
(docs/poc/README.md). None of these workflows can reach or hold a music-provider key.
