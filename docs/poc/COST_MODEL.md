# Cost model

Rate-card figures are from Mureka's pricing page as summarised by search on 2026-10-26 (see
`PROVIDER_EVALUATION.md`). **They are estimates until reconciled with an invoice.** The backend records an
estimate per job (`jobs.provider_cost_micros`, in millionths of a USD) and per voice enrollment; replace with
provider-reported figures if the API returns them.

| Item | Rate card | Where it is counted |
| --- | --- | --- |
| Voice enrollment (Vocal ID) | $5.00 each | `voices.provider_cost_micros` |
| Lyrics → song | $0.045 (O2 / V8 / V9) – $0.15 (V9.5) | `jobs.provider_cost_micros`, set once the provider has accepted the job |
| Failed after acceptance | **billed** (assumed until proven otherwise) | included in "cost per successful song" |
| Refused before acceptance (4xx, 429, network) | not billed | not counted |

**Cost per successful song** = (all songs the provider accepted, including ones that later failed) ÷
(completed songs). One enrolled voice amortises over its songs; the fixed $5 is reported separately
(`voiceEnrollmentMicros`) so it is not hidden in the per-song figure.

Illustration (arithmetic, not a measurement): 1 voice + 10 songs on the $0.045 tier with 2 failures after
acceptance = $5 + 10 × $0.045 = $5.45 for 8 successes → $0.056 per song excluding the voice, $0.68 including it.

## HeartMuLa via WaveSpeedAI (rate card read 2026-10-31; not yet billed)

| Item | Rate card | Where it is counted |
| --- | --- | --- |
| Voice enrolment | not offered (no personal voice) | n/a |
| Lyrics → song | $0.10 per song | `jobs.provider_cost_micros` (`WAVESPEED_SONG_COST_MICROS`, default 100000) |

**Observed 2026-11-01:** three songs (25 s, 44 s and 63 s of audio) each cost exactly $0.10; no fixed voice fee. Whether a
task that fails after acceptance is billed is still unknown (none failed).

If a personal voice were added with the hosted chain (measured on 2026-11-01, see PROVIDER_EVALUATION.md): vocal isolation is
priced per second of audio (about $0.001/s, $0.064 for a 63 s song) and voice conversion is $0.02 per call of at most
about 40 s of audio, so a 3-minute song would cost roughly $0.10 + $0.18 + $0.10 = **$0.38** (arithmetic, not a bill).

## Unit economics still unknown

- Real completion rate and retry rate for Mureka.
- Whether failures after acceptance are billed.
- The credit price DeenVoice would need (1 credit = 1 song today) once voice fees, failures, storage,
  support and payment fees are included.
- Concurrency limits by top-up level (1 concurrent task at $10).

Measure these in the live PoC; the metrics endpoint (`GET /v1/admin/metrics`) and `docs/poc/results/*.json`
carry the raw numbers.
