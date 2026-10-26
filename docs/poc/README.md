# Live proof-of-concept runbook

Goal (Phase 2 acceptance): **one real authorized voice → one real song from a real provider**, played
back in DeenVoice and reopened from the library, with measured latency, cost and quality.

This build environment could not do that (see [../ACCEPTANCE_PHASE2.md](../ACCEPTANCE_PHASE2.md)). This
runbook is how you do it on a machine that can. Nothing here has been run against a live provider yet.

## What you need

| Need | Notes |
| --- | --- |
| Network access to `api.mureka.ai` and `platform.mureka.ai` | These were denied in the build environment. |
| A Mureka API account with prepaid balance | Expect about **$5 for the voice + $0.045–$0.15 per song** (rate card, 2026-10-26; confirm in the console). The $10 minimum top-up gives 1 concurrent task. |
| One authorized participant | Adult, willing, informed. Written consent **before** anything is uploaded: [consent-record-template.md](consent-record-template.md). |
| A clean solo vocal sample | 10–15 s, single voice, no music, no reverb, no noise. Mureka's documented range is 5–15 s. WAV preferred. |
| Original lyrics | Written by or for the participant. Never copyrighted lyrics. Keep English first. |
| Hausa and Arabic lyrics + native listeners | For the language probes. Without native listeners the language result is "unknown", not "works". |
| Node ≥ 22.18 | `cd backend && npm ci` |

## Steps

1. **Read the contract; don't trust the adapter yet.**
   ```bash
   cd backend
   node scripts/mureka-probe.mjs --discover
   ```
   Find the *Vocal cloning* operation, read its page, and set `MUREKA_VOCAL_CLONE_PATH`. Check that the
   multipart field names in `enrollVoice()` (`src/provider/mureka.ts`) match; fix the adapter if not.
   Record what you found in `docs/PROVIDER_EVALUATION.md`.
2. **Check the key without spending.**
   ```bash
   MUREKA_API_KEY=… node scripts/mureka-probe.mjs --billing
   ```
3. **Check the song contract with one cheap song and no voice** (~$0.05):
   ```bash
   MUREKA_API_KEY=… node scripts/mureka-probe.mjs --generate --lyrics lyrics-en.txt --spend
   ```
   This confirms the field names and status values the adapter assumes (`id`, `status`, `choices[].url`).
   Any FAIL line means the adapter needs fixing before step 4.
4. **Run the real voice-to-song flow** (spends the voice fee):
   ```bash
   cp .env.example .env   # fill in BLOB_ENCRYPTION_KEY, MEDIA_SIGNING_KEY, PROVIDER=mureka, MUREKA_*, POC_ACCOUNT_PASSWORD
   set -a; . ./.env; set +a
   node --disable-warning=ExperimentalWarning scripts/live-poc.ts \
     --participant "Full Name" --ownership own --voice-sample sample.wav --lyrics lyrics-en.txt \
     --title "PoC English 1" --consent-accepted --spend
   ```
   It enrolls the voice, creates a persistent job through the same code the API uses, waits for the real
   provider, stores the audio encrypted, re-reads it from the library via a signed link, writes the audio to
   `backend/data/poc-exports/` (private; it contains the participant's voice), and writes
   `docs/poc/results/<stamp>-result.json` (no audio, lyrics or keys; safe to commit).
5. **Language probes** — repeat step 4 with `--reuse-voice <voiceId>` (no second $5) and a short Hausa and a
   short Arabic lyric, with `EXPERIMENTAL_LANGUAGES=hausa,arabic`. Expect failure or poor results (Mureka does
   not document either). Record the outcome as an *experiment*.
6. **Listening evaluation** with the template below.
7. **Play it in DeenVoice**: run the backend (`npm start`), point the Flutter app at it
   (`--dart-define=API_BASE_URL=…`), sign in, and open the song from the library. See
   [../STATUS.md](../STATUS.md) for how the client is wired.
8. **Reconcile the cost** against the provider's invoice and update [COST_MODEL.md](COST_MODEL.md).
9. **Delete the participant's data when the trial ends** (voice, exports, DB rows) and ask Mureka to delete
   the Vocal ID and sample, since there is no self-service deletion API we could find
   (`DELETE /v1/voices/:id` reports exactly what was and wasn't removed).

## Listening evaluation

Use [listening-test-template.csv](listening-test-template.csv). One row per rater per song.

- Play the participant's **reference sample first**, then the song. Record `heard_reference_first`.
- Raters score 1–5: `similarity` (does it sound like the participant?), `pronunciation` (is each word
  said correctly? **native speakers of the lyrics' language only**), `naturalness` (singing, not
  robotic/glitchy), `arrangement` (music supports the vocal), `intelligibility` (could you write the lyrics
  down?), `overall`. Also `would_share` (y/n) and notes (e.g. any wrong or disrespectful religious wording).
- **Pre-registered bar** (decided before listening; change it only before a round):
  mean `similarity` ≥ 4.0, `pronunciation` ≥ 4.0, `naturalness` ≥ 3.5, `intelligibility` ≥ 3.5, with **at
  least 3 native raters** of the lyrics' language. Fewer native raters ⇒ "insufficient evidence", never a pass.
- Aggregate: `node --disable-warning=ExperimentalWarning scripts/summarize-listening.ts ratings.csv`.

Completion rate, latency and cost per successful song come from the results files and
`GET /v1/admin/metrics` (failed-but-billed attempts are included in cost per successful song).

## What would make this a pass, and what would not

A pass needs *all* of: real enrolled voice, real provider song, audible playback in DeenVoice, song persisted
and reopened, measured cost/latency, **and** a listening result that meets the bar for the language claimed.
An HTTP 200, an MP3, or green automated checks is not a pass. If the provider cannot sing in the participant's
voice, stop, report that, and evaluate the next candidate (see `PROVIDER_EVALUATION.md`); do not simulate.
