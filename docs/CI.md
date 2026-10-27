# CI/CD

Four GitHub Actions workflows in `.github/workflows/`, adapted from the eSportlyic samples
(Android, iOS, web deploy). All four have run on GitHub and passed on the current head (`128cfed`);
only the browser-journey job of `ci.yml` and every signed or published path have not run there. See
"What is and is not verified".

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
| `TERMS_URL`, `PRIVACY_URL` | Public pages for the Terms of Service and Privacy Policy. Set **both** or neither: the sign-in screen says "By continuing, you agree to…" only when both exist (otherwise it says the documents are not published), and Profile links each page that exists. Store review will expect real ones |

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

Ran on GitHub, branch `ccr-936b65c0-6lt7lb`, head commit `128cfed` (all `success`):

| Workflow (run id) | Runner | Result |
| --- | --- | --- |
| `ci.yml` #5 (40461742457) | `ubuntu-latest` | **Flutter app** passed in 172 s: format 1 s, analyze 12 s, all tests 71 s, release web compile. **Backend** passed in 57 s: typecheck and the full suite on Node 22 (34 s). **Browser journey: skipped, as designed** (it runs on `main` and on manual dispatch only). |
| `android.yml` (40461750507) | `ubuntu-latest` | Release APK built in 220 s (the Gradle build step 154 s); APK signature verified; the 16 KB page-size alignment check passed. Uploaded as **"debug-signed APK (not publishable)"** because the repository has no keystore secret. The signed AAB and Play steps were skipped. |
| `ios.yml` (40461753382) | `macos-26` | Release app compiled **without code signing** in 205 s (the build step 116 s). The signed IPA and TestFlight steps were skipped because no signing secrets exist. |
| `web.yml` (40461756053) | `ubuntu-latest` | Release web build in 76 s (the build step 43 s) against the configured backend URL; uploaded as an artifact. No deploy step. |

Earlier runs also passed: `ci.yml` #4 (commit `b9b5af3`, run 40460863445) and, dispatched by hand on commit
`874b259`, Android (40447743438), iOS (40447797921) and web (40447822398).

So on GitHub: the app, including the in-app recorder, the onboarding, the five-tab shell and account deletion,
**compiles** for Android (release), iOS (release, unsigned) and web (release), and the Flutter and backend test
suites pass on a clean machine.

Verified here, in this repository's container:
- All four files pass `actionlint` with `shellcheck` enabled.
- The commands the workflows run for Flutter and the backend (format, analyze, test, `flutter build web`,
  `npm ci`/typecheck/test, the browser journey) were run with the same flags and passed.
- `tool/check_16kb_alignment.sh` was tested on libraries built with 4 KB and 16 KB alignment (detects
  both, ignores 32-bit, `--strict` exits 1), and it passed on the real APK on GitHub.
- The iOS profile-specifier patch was run against the real `project.pbxproj`: it changes exactly the three
  Runner configurations and not `RunnerTests`, and survives a profile name containing quotes and slashes.

**Not verified:**
- **Nothing has run on a phone.** A compiled APK or app bundle says the code builds, not that the recorder, the
  microphone permission prompt, audio playback or the screens behave on a device. Recording was driven only in
  Chromium with a fake microphone (a tone).
- **The browser-journey job** of `ci.yml` has not run on GitHub (it needs `main` or a manual dispatch); it passed
  in this container.
- **Signed builds.** The Android build is debug-signed and the iOS build unsigned. The signing paths (Gradle
  `key.properties`/environment keystore, the signed AAB, the iOS provisioning-profile patch, `PlistBuddy`
  parsing of the profile, the signed IPA and `altool` upload to TestFlight) were skipped for lack of secrets and
  have not run for DeenVoice. They follow the fixes in your working sample.
- **No web deploy**, and no deploy of the backend.
- `GITHUB_ENV`-passing of secrets-derived values and the `secrets.X != ''` flags were exercised only on their
  "no secret" side.

If a signed run fails once the secrets are added, send me the log; the likely suspects are listed above.

## Not included

Deploying the backend (it needs a host, a managed database/object storage and its own secrets: see
BACKEND.md), store submission (Play/App Store listing), and the real-provider proof of concept
(docs/poc/README.md). None of these workflows can reach or hold a music-provider key.
