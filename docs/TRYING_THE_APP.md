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

## Verified on 2026-11-02: a real song, made and played inside the app (in a browser)
`tool/web_e2e_real_engine.mjs` ran the web build in Chromium against a real local backend using the **real** engine (HeartMuLa
through WaveSpeedAI): sign up, credits, Create Song (the app says the engine sings in its own voice and asks for none),
English, Generate, a real job followed to "Your song is ready", Play, and the audio really played (position 0:05 / 1:03, served as
`audio/mpeg`); the saved file is a 63-second, 2.5 MB MP3, and the song is on Home after a reload. 8 of 8 steps, no page errors,
about $0.10. Screenshots: `docs/verification/real_engine/`. **This proves the plumbing, not the sound.** Only a person can judge
the song; it is in the file sent to the owner. Not run on a phone, and not run against a hosted server.

## Known rough edges seen in that run
- Create Song still offers "Duration 3 - 4 minutes", but HeartMuLa's length follows the lyrics (the test song was 63 s). The setting
  is not honoured and not yet marked as such.
- The player says "english · Made with heartmula" in lower case.
- Language: only English is offered by this engine (Hausa and Arabic are undocumented for it and were judged very bad).

## What would make a real end-to-end test
1. ~~A stock-singer mode~~ (done, see point 3 above).
2. The backend hosted somewhere (`render.yaml` is a free-plan test blueprint, **untried on Render**; see its comments for what the free plan loses) with https, a persistent disk, and the provider key as a server secret.
3. The repository variable `API_BASE_URL` set to that address, then a rebuild of the Android app.
Hausa and Arabic: the owner judged HeartMuLa's output very bad on 2026-11-01; English has not been judged.
