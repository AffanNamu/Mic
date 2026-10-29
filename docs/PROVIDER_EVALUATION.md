# Provider evaluation (Phase 2, Step 2)

Date of research: 2026-10-26.

## How to read this, and its limits

**No provider documentation could be fetched directly, and no provider API could
be called.** The build environment's network policy denies every provider host
that was tried (`elevenlabs.io`, `platform.minimax.io`, `platform.mureka.ai`,
`api.mureka.ai`, `kits.ai`, `suno.com`, `ai.google.dev`, `replicate.com`,
`huggingface.co`, and others). The evidence below therefore comes from a search
tool that returns summaries of pages, restricted where possible to each
provider's own domain. That is weaker than reading the documents. Every claim is
tagged:

| Tag | Meaning |
| --- | --- |
| **[O]** | Reported from a page on the provider's own domain (still a search summary, not read verbatim by me). |
| **[T]** | Third-party reseller, review or marketing text. Not evidence. |
| **[M]** | Provider marketing copy on its own domain. Treat as a claim, not a guarantee. |
| **[?]** | Not found, or contradictory. Unverified. |
| **[inf]** | My inference from a surrounding fact. |

Nothing here was verified by running anything. Prices, model names, language
lists and terms change; each must be re-confirmed in the provider's console and
legal documents before spending money or onboarding a real person's voice.

## What DeenVoice needs from a provider

1. Full song with vocals and instrumentation from lyrics.
2. Singing in a **persistent, enrolled voice** of an authorized person.
3. Hausa lyrics and pronunciation; Arabic and English.
4. Enrollment with consent, plus **deletion**.
5. Commercial rights to the output; usable API, price, limits, latency.
6. Acceptable data retention and privacy for voice recordings.

Speech cloning is not singing, and full-song generation does not imply a custom
singer, so each requirement is checked separately.

## Comparison

| | Mureka API | ElevenLabs Music | Google Lyria 3 | MiniMax Music | Suno | Kits.ai | ACE-Step 1.5 (self-host) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Public API for full songs | **Yes [O]** (`api.mureka.ai`, `/v1/song/generate`, async + query) | **Yes [O]** (`/v1/music`, `/v1/music/detailed`, 3 s–10 min) | **Yes, paid preview [O]** (Gemini API / Vertex) | Yes [O] **but closed to new users after 2026-08-20 [O]** | **None found [O]** (enterprise via sales) | No (voice conversion only) | n/a (you run it) |
| Vocals + instrumentation | Yes [O] | Yes [O] | Yes [O] | Yes [O] | Yes (consumer) | No | Yes [M/T] |
| **Persistent enrolled voice used for singing** | **Yes [O]**: Vocal cloning → `vocal_id` used with song generation | **No evidence [?]** (voice IDs documented for speech/voice changer only) | **No evidence [?]**; an output "vocal likeness" filter exists [O/inf] | Cover from reference audio, not a persistent voice [O] | Voices (consumer app; verification phrase; private) [O], no API | Trains a voice model from user audio via API [O] (conversion, not generation) | No custom voice [?] |
| Hausa singing | **No** [O: 10 documented languages exclude it] | Hausa **speech** exists [O]; singing [?] | No [O: 8 languages] | [?] | [?] | Preserves the *source* performance's pronunciation [inf] | "50+ languages" claim [T/M]; Hausa [?] |
| Arabic singing | Not in documented 10 [O] | Not named; "59 languages" is marketing [M] | No [O: 8 languages] | [?] | [?] | n/a | Not named [?] |
| English | Yes [O] | Yes [O] | Yes [O] | Yes | Yes | n/a | Yes |
| Consent / verification for voice | Developer must obtain end-user consent [O: API agreement]; no verification step found [?] | n/a | n/a | n/a | Spoken phrase must match the sample [O] | Uploader warrants consent [O: terms] | n/a |
| Voice deletion | Contact the company for personal data [O]; a UI mention of deleting saved Voice IDs [O/T]; **no self-service API found [?]** | n/a | n/a | n/a | n/a | n/a | You control it |
| Output rights | Output assigned to the customer [O: API agreement] | Tier-dependent [O/M] | [?] | [?] | Terms apply | Terms apply [O] | MIT licence claimed [T]; training-data claim unverified |
| Price | Prepaid. $5 per Vocal ID; lyrics→song $0.03–0.15 depending on model; prompt→song $0.3–0.5 [O: pricing page] | Usage/tiers [?] | Preview pricing [?] | $0.03–0.15 per song [T, conflicting] | n/a | Plans $10–$60/month; API pricing [?] | GPU cost |
| Rate limits / latency | Concurrency by top-up: 1 at $10, 5 at $1,000, … [O]; latency [?] | [?] | [?] | 120 RPM [O] | n/a | [?] | your hardware |
| Retention / privacy | **Output retained up to 1 month** [O: API privacy policy]; uploaded voice may be used to improve algorithms and to make music that "may contain your unique vocal characteristics" [O] | [?] | [?] | [?] | Voices private to creator [O] | Uploads may be used to train for accounts since 2024-10-02; opt-out by email [O] | yours |

### Sources

- Mureka: [pricing](https://platform.mureka.ai/pricing),
  [changelog](https://platform.mureka.ai/docs/en/changelog.html),
  [quickstart](https://platform.mureka.ai/docs/en/quickstart.html),
  [lyrics to song](https://platform.mureka.ai/docs/api/operations/post-v1-song-generate.html),
  [file upload](https://platform.mureka.ai/docs/api/operations/post-v1-files-upload.html),
  [API FAQ](https://platform.mureka.ai/docs/en/faq.html),
  [API service agreement (2025-12-03)](https://platform.mureka.ai/service_terms.pdf),
  [API privacy policy](https://platform.mureka.ai/privacy_policy.pdf),
  [consumer terms (2026-05-13)](https://www.mureka.ai/static/terms-20260513.pdf),
  [FAQ](https://www.mureka.ai/knowledge_en.html).
- ElevenLabs: [Music API](https://elevenlabs.io/eleven-music-api),
  [compose detailed](https://elevenlabs.io/docs/api-reference/music/compose-detailed),
  [composition plans](https://elevenlabs.io/docs/eleven-api/guides/how-to/music/composition-plans),
  [Hausa TTS](https://elevenlabs.io/fr/text-to-speech/hausa).
- Google: [Gemini API music generation](https://ai.google.dev/gemini-api/docs/interactions/music-generation),
  [Lyria 3 for developers](https://blog.google/innovation-and-ai/technology/developers-tools/lyria-3-developers/).
- MiniMax: [Music Generation API](https://platform.minimax.io/docs/api-reference/music-generation),
  [Music Cover Preprocess](https://platform.minimax.io/docs/api-reference/music-cover-preprocess).
- Suno: [Voices](https://help.suno.com/en/articles/11362369),
  [Voices FAQ](https://help.suno.com/en/articles/11362433),
  [Terms](https://suno.com/terms-of-service).
- Kits: [API](https://www.kits.ai/api), [pricing](https://www.kits.ai/pricing),
  [terms](https://www.kits.ai/terms-of-service).
- ACE-Step 1.5: [Diffusers docs](https://huggingface.co/docs/diffusers/v0.39.0/api/pipelines/ace_step),
  [AMD note on licence](https://www.amd.com/en/blogs/2026/commercial-grade-ai-music-generation-on-amd-ryzen-ai-and-radeon-ace-step-1-5.html).

## Findings against the requirements

1. **Full song in a persistent enrolled voice through an API: only Mureka showed
   evidence.** Its documentation lists a "Vocal cloning" operation that returns a
   reusable `vocal_id`, and its changelog says `vocal_id` and `prompt` can be
   used together in song generation. The clone uses mainly vocal *timbre* and
   does not determine range, melody or genre; harmonies, backing vocals and
   humming are unsupported [O]. A sample of 5–15 s is required by the upload
   operation [O].
2. **Hausa singing: no provider has evidence of supporting it.** Mureka's
   documented vocal-clone languages are English, Chinese, Japanese, Korean,
   Portuguese, Spanish, German, Italian, French and Russian [O]; Lyria's eight
   exclude Hausa and Arabic [O]. ElevenLabs offers Hausa *speech* only. So the
   Hausa requirement is **currently unmet by every researched provider**, and
   nothing may be advertised as supporting it until a listening test says so.
3. **Arabic singing: unverified everywhere.** Not in Mureka's list; marketing
   claims elsewhere are not evidence.
4. **Consent and deletion are gaps on the provider side.** Mureka puts consent
   on the developer and offers no self-service deletion API that I found, so
   DeenVoice must do the consent capture, record it, and honestly report that
   provider-side deletion is by request.
5. **Retention drives architecture.** Output is kept by the provider for at most
   a month, so the backend must download and store generated audio itself.
6. **Voice data licensing needs legal review before real users.** The API
   agreement grants Mureka a non-exclusive, sub-licensable licence to use
   personal data and allows processing to improve its algorithms; the consumer
   terms are broader still. A product built on identity-bearing voice data
   should not accept that without counsel and explicit user disclosure.
7. **Commercial rights: Output is assigned to the customer under the API
   agreement [O]**, with caveats (not unique, no copyright-registration
   guarantee, a prohibition on using outputs to train competing models).
8. **Cost is small compared to the voice fee**: $5 per enrolled voice, then
   about $0.045 (O2/V8/V9) to $0.15 (V9.5) per lyrics-to-song [O], with
   concurrency tied to the top-up (1 concurrent at $10).

## Recommendation: one controlled proof of concept

**Mureka API, with English lyrics first.**

- It is the only researched option with documented evidence for the core
  mechanism (enrolled `vocal_id` + lyrics → complete song) behind a public API.
- Pre-register the expected outcome: English works; **Hausa and Arabic probably
  do not**. The proof of concept must still test Hausa and Arabic (a short
  lyric each) and record the result honestly, because that is the product's
  differentiator.
- Run it with **one authorized participant**, written consent, a 10–15 s clean
  solo vocal sample, and original lyrics.
- Prepare, but do not integrate, the fallback for Hausa: record the
  participant singing the Hausa lines themselves (a guide vocal) and evaluate
  singing voice conversion; or a self-hosted open model. Neither is verified.

Not recommended for the proof of concept: Suno (no API), MiniMax (closed to new
users), Lyria and ElevenLabs Music (no evidence of custom-voice singing), Kits
(conversion only, and default training-data use).

## Live contract check (2026-10-29)

Mureka became reachable from the build environment (the host allow-list was changed) and an API key was
supplied as an environment secret. No money was spent: the one call that could have been billed was refused for lack of credit.
Transcripts with the Authorization header removed are in `docs/poc/transcripts/`.

| Step | Result |
| --- | --- |
| `--discover` (public docs, no key) | 28 operation pages read. The vocal-cloning operation exists at **`POST /v1/song/vocal-clone`**. |
| `--billing` (key check, free) | **HTTP 200** `{"account_id", "concurrent_request_limit": 1, "trace_id"}`. The key is valid. There is **no balance field**, so a balance cannot be read from the API. |
| `POST /v1/song/generate`, one short English song, no voice | **HTTP 429** `{"error":{"message":"You exceeded your current quota, please check your plan and billing details"},"trace_id":...}`. The account has **no credit**, so no song was generated and no money was spent. |

What this settles, and what it does not:
- **Settled:** the host, the bearer auth, and the key work. HTTP 429 is how Mureka says the account is out of credit
  (the official *Error codes* page lists two different 429s: "rate limit reached" and "you exceeded your current
  quota ... you have run out of credits").
- **Not settled:** the song-generation response, the poll response and its status values, the result URL field, the
  vocal-clone response, audio quality, latency, real cost, and any Hausa or Arabic behaviour. **No song and no Vocal ID
  has been produced.** The Phase 2 verdict (not accepted) is unchanged.

Differences between the adapter and the official pages, and what was changed:

| Topic | Before | Official page | Change |
| --- | --- | --- | --- |
| HTTP 429 | always "rate limited, retry" | two meanings; "exceeded your current quota" = out of credits | The adapter reads the error message. Out of credit is now **terminal and flagged as a funds problem** (the job fails, its reserved credits are released, the provider is marked unavailable) instead of being retried; "rate limit" is still retried. Found by the live call; tested, mutation-checked. |
| Vocal-clone path | unknown | `POST /v1/song/vocal-clone` | Documented in `.env.example` and the runbook. Still **off until an operator sets `MUREKA_VOCAL_CLONE_PATH`**, because it has never been run. |
| Vocal-clone fields | `purpose=voice` + `file` | `file` (required), `description` (optional, up to 1024 characters) | `purpose` removed. |
| Sample length | 5-15 s | **15-30 s** (excess trimmed) on the vocal-clone page; the generic file-upload page says 5-15 s for its `voice` purpose | Set to 15-30 s. The app asks for what the connected engine states, so recording now asks for 15-30 s. |
| Sample format | WAV (assumed) | **mp3, m4a**, under 10 MB. WAV is not listed. | **Not changed, and unresolved.** The app records WAV. Whether Mureka accepts it is unknown; if it does not, the server must transcode (ffmpeg, or an encoder) or the app must record AAC. Settle this with a free-of-charge probe once there is credit. |
| HTTP 403 | "credentials rejected" | "accessing from an unsupported region" | **Not changed.** A 403 is still reported as a credentials problem; the user-facing reason would be wrong for a region block. |
| Languages | English only | Chinese, English, Japanese, Korean, Portuguese, Spanish, German, Italian, French, Russian (FAQ, changelog) | Unchanged: no Hausa, no Arabic. |
| Concurrency | assumed 1 on the minimum top-up | `concurrent_request_limit: 1` on this account | Matches. |

Other facts from the FAQ: API credits are separate from website membership credits; credits are valid for 12 months
from the last top-up and are non-refundable; downloading songs is free; the multitrack (stems) feature costs extra.

## Still unverified, to check before and during the proof of concept

| Item | How |
| --- | --- |
| Response of Vocal cloning; whether a WAV sample is accepted (only mp3 and m4a are documented); whether a verification step exists | Needs credit. The request fields and path are now read from the official page (see "Live contract check") |
| Status values and result fields of `song/query` | Needs credit: the probe's `--generate` step. Not yet observed |
| Whether `vocal_id` songs in English meet the quality bar | Listening test (see `docs/poc/`) |
| Arabic and Hausa behaviour | Listening test with native speakers |
| Latency per song | Measured by the live PoC script |
| Real cost per *successful* song including failures | Measured by the live PoC script |
| Deletion of a Vocal ID and of the uploaded sample | Ask Mureka; test the console feature |
| Data licence acceptability | Legal review |

## What was not possible here

- (Updated 2026-10-29.) Mureka is now reachable and the key works, but the account has **no credit**, so no
  Vocal ID has been created and no song has been generated. There is still no authorized voice sample.
- Evaluation with Hausa-speaking listeners.
