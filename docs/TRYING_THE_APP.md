# Trying the app (state on 2026-11-02)

**Short answer:** you can install it and click through every screen, but you cannot sign in, create a song or hear one yet.
Three separate reasons, all verified:

1. **The downloadable builds have no server address.** The Android build log says `vars.API_BASE_URL is not set: the app will say
   it is not connected`. In that mode the app opens straight to Home with no sign-in; Create Song says no engine is connected.
2. **No server is running anywhere.** The backend only ever ran inside temporary build containers. The app needs it on a public
   **https** address (Android blocks plain http).
3. **(Fixed 2026-11-02)** The engine tested live (HeartMuLa) cannot sing in a saved personal voice, and the app and server used
   to refuse every vocal song for that reason. Now an engine that sings only in its own built-in voice makes a vocal song with
   no voice chosen: the app shows "<engine> sings in its own built-in voice", sends no voice, and the server refuses a named
   voice rather than ignoring it. Add New Voice is switched off with the reason while such an engine is connected.

## What you can try today (no server)
- Install on Android, open it: onboarding, Home, the five tabs, Create Song (forms, lyrics, language, validation messages), My Voice,
  Library, Activity, Profile and the Terms/Privacy notice. Features that need a server say so instead of pretending.
- Record your voice on the Add Voice screen: recording, level meter, play back, and the too-short / silent checks work on the device.
  Nothing is uploaded without a server. **Never run on a real phone by us**: only compiled in CI and driven in Chromium.

## Where to download
- GitHub, repository `AffanNamu/Mic`, tab **Actions**. You must be signed in to GitHub to download artifacts.
- **Android:** workflow "Android release build", latest green run, artifact `app-DEBUG-SIGNED-apk-do-not-publish`
  (a zip containing the APK; signed with a debug key, so it installs for testing but cannot go to the Play Store). Artifacts are
  kept 7 days; the 2026-10-27 one expires on 2026-11-03. Re-run the workflow (Run workflow) for a fresh one.
  Install: unzip, copy the APK to the phone, allow "install unknown apps" for your file manager.
- **Web:** workflow "Web build", artifact `web-release` (kept 30 days). Unzip and serve the folder (for example
  `python3 -m http.server` inside it); opening `index.html` directly will not work.
- **iPhone:** none. The iOS job only checks that the code compiles; installing needs Apple signing, which does not exist.

## What would make a real end-to-end test
1. ~~A stock-singer mode~~ (done, see point 3 above).
2. The backend hosted somewhere with https, a persistent disk, and the provider key as a server secret.
3. The repository variable `API_BASE_URL` set to that address, then a rebuild of the Android app.
Hausa and Arabic: the owner judged HeartMuLa's output very bad on 2026-11-01; English has not been judged.
