// Live proof-of-concept runner: one REAL voice-to-song generation through the real backend code paths.
//
//   Voice sample + consent → enroll with the real provider → persistent job → real generation →
//   store → retrieve → write the audio to a private folder for listening → write a results file.
//
// It uses the same modules the server uses (voices.ts, jobs.ts, worker.ts, ledger.ts), against a real
// provider. No test double is reachable from here: createProvider() returns the configured real provider
// or the fail-closed "unconfigured" one, and this script refuses to continue with the latter.
//
// IT SPENDS MONEY (Mureka: $5 per voice, about $0.045-$0.15 per song) AND SENDS A PERSON'S VOICE TO A
// THIRD PARTY. It will not run unless you pass --spend and --consent-accepted, and the second flag is
// your statement that the participant gave written consent before you started (see docs/poc/README.md).
//
//   node --disable-warning=ExperimentalWarning scripts/live-poc.ts \
//     --participant "Full Name" --voice-sample sample.wav --lyrics lyrics.txt \
//     [--language english] [--title "..."] [--genre english_nasheed] [--mood peaceful] [--tempo normal] \
//     [--ownership own|authorized] [--reuse-voice <voiceId>] --consent-accepted --spend
//
// Required environment: see backend/.env.example. DATABASE_PATH and BLOB_DIR default to ./data (git-ignored).

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../src/config.ts';
import { openDb, runMigrations, one, all } from '../src/db.ts';
import { systemClock } from '../src/clock.ts';
import { FileBlobStore } from '../src/blobstore.ts';
import { createProvider } from '../src/provider/index.ts';
import { ProviderHealth } from '../src/deps.ts';
import type { Deps, Logger } from '../src/deps.ts';
import { JobWorker } from '../src/worker.ts';
import { register, login } from '../src/auth.ts';
import * as ledger from '../src/ledger.ts';
import * as voices from '../src/voices.ts';
import * as jobs from '../src/jobs.ts';
import * as songs from '../src/songs.ts';
import { metrics } from '../src/metrics.ts';
import { CONSENT_VERSION, consentStatement } from '../src/consent.ts';
import { sha256Hex } from '../src/crypto.ts';
import { sniffAudio, wavDurationMs } from '../src/audio.ts';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const flag = (n: string) => args.includes(n);
const opt = (n: string, d?: string) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const fail = (msg: string): never => { console.error(`\nREFUSING TO RUN: ${msg}\n`); process.exit(2); };

if (!flag('--spend')) fail('this run spends money and uploads a voice to a third party. Re-run with --spend to confirm.');
if (!flag('--consent-accepted')) fail('pass --consent-accepted only after the participant has given written consent (docs/poc/consent-record-template.md).');
const participant = opt('--participant') ?? fail('--participant "Full Name" is required (the person whose voice this is).');
const samplePath = opt('--voice-sample') ?? fail('--voice-sample <file> is required.');
const lyricsPath = opt('--lyrics') ?? fail('--lyrics <file> is required (original lyrics you have the right to use).');
const ownership = (opt('--ownership', 'authorized') as 'own' | 'authorized');
const language = opt('--language', 'english')!;
const title = opt('--title', `PoC ${new Date().toISOString().slice(0, 10)}`)!;

const config = loadConfig();
const provider = createProvider(config);
if (!provider.configured) fail('no provider configured. Set PROVIDER=mureka and MUREKA_API_KEY (see .env.example).');
const caps = provider.capabilities();
if (!caps.voiceConditioning) {
  fail(`${caps.engineName} is not configured to sing in an enrolled voice (for Mureka: set MUREKA_VOCAL_CLONE_PATH after reading the official Vocal cloning operation; run scripts/mureka-probe.mjs --discover).`);
}
if (!caps.languages.includes(language)) {
  fail(`${caps.engineName} does not declare "${language}" lyrics as supported (supported: ${caps.languages.join(', ') || 'none'}). ` +
    'To TEST an undeclared language, set EXPERIMENTAL_LANGUAGES=' + language + ' — the result must then be recorded as an experiment, not a capability.');
}

const log: Logger = {
  info: (o, m) => console.log(JSON.stringify({ level: 'info', msg: m, ...o })),
  warn: (o, m) => console.warn(JSON.stringify({ level: 'warn', msg: m, ...o })),
  error: (o, m) => console.error(JSON.stringify({ level: 'error', msg: m, ...o })),
};
const db = openDb(config.databasePath);
runMigrations(db, join(here, '..', 'migrations'));
const deps: Deps = { db, clock: systemClock, config, log, blobs: new FileBlobStore(config.blobDir, config.blobKey), provider, health: new ProviderHealth() };
const worker = new JobWorker(deps);

const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const events: Array<{ at: string; event: string; detail?: unknown }> = [];
const note = (event: string, detail?: unknown) => { events.push({ at: new Date().toISOString(), event, detail }); console.log(`[${new Date().toISOString()}] ${event}${detail ? ` ${JSON.stringify(detail)}` : ''}`); };

// A throwaway operator account for this run. Re-running reuses it.
const email = 'poc-operator@deenvoice.invalid';
const password = process.env.POC_ACCOUNT_PASSWORD ?? fail('POC_ACCOUNT_PASSWORD is required (any 10+ character secret; the account exists only in the local PoC database).');
let userId: string;
try { userId = (await register(db, systemClock, config.sessionTtlMs, email, password)).userId; }
catch { userId = (await login(db, systemClock, config.sessionTtlMs, email, password)).userId; }

const sample = readFileSync(samplePath);
const sniffed = sniffAudio(sample);
if (!sniffed) fail(`${samplePath} is not a recognisable audio file.`);
const wavMs = sniffed!.kind === 'wav' ? wavDurationMs(sample) : null;

console.log('\n=== PLAN ===');
console.log(`Provider:      ${caps.engineName} (${provider.name})`);
console.log(`Participant:   ${participant} (${ownership})`);
console.log(`Voice sample:  ${samplePath} — ${sample.length} bytes, ${sniffed!.mime}${wavMs ? `, ${(wavMs / 1000).toFixed(1)} s` : ''}`);
console.log(`Language:      ${language}${caps.documentedLanguages.includes(language) ? '' : '   ** NOT a documented language for this provider: this is an experiment **'}`);
const estimate = (caps.estimatedEnrollCostMicros ?? 0) + (caps.estimatedSongCostMicros ?? 0);
console.log(`Expected cost: about $${(estimate / 1e6).toFixed(3)} (rate card, estimate) — $${((caps.estimatedEnrollCostMicros ?? 0) / 1e6).toFixed(2)} voice + $${((caps.estimatedSongCostMicros ?? 0) / 1e6).toFixed(3)} song`);
console.log(`Consent text (${CONSENT_VERSION}, sha256 ${consentStatement(CONSENT_VERSION, ownership)?.sha256.slice(0, 16)}…):\n  ${consentStatement(CONSENT_VERSION, ownership)?.text}\n`);

// --- credits for the throwaway account (this is the local ledger, not the provider's balance)
if (ledger.balance(db, userId).available < 1) ledger.grant(db, systemClock, userId, 5, 'live PoC run');

// --- 1. voice
const t0 = Date.now();
let voiceId = opt('--reuse-voice');
if (!voiceId) {
  const v = voices.createVoice(deps, userId, {
    displayName: participant, ownership, authorizedBy: ownership === 'authorized' ? `${participant} (written consent held by the operator)` : null,
    consent: { accepted: true, version: CONSENT_VERSION },
  }, { ip: null, userAgent: 'live-poc.ts' });
  voiceId = v.id;
  note('voice.consent_recorded', { voiceId });
  await voices.uploadVoiceAudio(deps, userId, voiceId, sample);
  note('voice.audio_stored_encrypted', { bytes: sample.length });
}
const enrollStart = Date.now();
for (;;) {
  await worker.tick();
  const v = voices.getVoice(deps, userId, voiceId);
  if (v.status === 'ready') break;
  if (v.status === 'failed') { note('voice.enrollment_failed', { code: v.failureCode, message: v.failureMessage }); await finish(false); }
  if (Date.now() - enrollStart > 5 * 60_000) { note('voice.enrollment_timeout'); await finish(false); }
  await new Promise((r) => setTimeout(r, 2000));
}
const enrollMs = Date.now() - enrollStart;
note('voice.ready', { voiceId, enrollMs, supportsSinging: voices.getVoice(deps, userId, voiceId).supportsSinging });

// --- 2. song
const lyrics = readFileSync(lyricsPath, 'utf8');
const idempotencyKey = `poc-${stamp}`.replace(/[^A-Za-z0-9_-]/g, '-');
const created = jobs.createJob(deps, userId, {
  idempotencyKey, title, lyrics, language, songType: 'full_song', voiceId,
  style: { genre: opt('--genre', 'english_nasheed')!, mood: opt('--mood', 'peaceful')!, tempo: opt('--tempo', 'normal')!, intensity: 'balanced', instruments: opt('--instruments', 'acoustic')! },
  advanced: {},
});
note('job.created', { jobId: created.job.id });
const jobStart = Date.now();
let job = created.job;
while (!['completed', 'failed', 'cancelled'].includes(job.status)) {
  await worker.tick();
  job = jobs.getJob(deps, userId, job.id);
  process.stdout.write(`\r  ${job.stage.padEnd(28)} ${Math.round((Date.now() - jobStart) / 1000)} s`);
  await new Promise((r) => setTimeout(r, 2000));
}
process.stdout.write('\n');
const latencyMs = Date.now() - jobStart;
note('job.finished', { status: job.status, failureCode: job.failureCode, latencyMs });

// --- 3. retrieve + persist check + export for listening
let exportPath: string | null = null;
let audioInfo: Record<string, unknown> | null = null;
let reopened = false;
if (job.status === 'completed' && job.songId) {
  const row = one(db, 'SELECT * FROM songs WHERE id = ?', job.songId)!;
  const bytes = await deps.blobs.get(String(row['audio_blob_key']));
  const kind = sniffAudio(bytes);
  audioInfo = { bytes: bytes.length, mime: kind?.mime ?? null, sha256: sha256Hex(bytes), durationMs: row['duration_ms'] };
  const dir = join(config.blobDir, '..', 'poc-exports');
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  exportPath = join(dir, `${stamp}-${job.songId}.${kind?.kind === 'm4a' ? 'm4a' : kind?.kind ?? 'bin'}`);
  writeFileSync(exportPath, bytes, { mode: 0o600 });
  // "Reopen from the library": a fresh read through the same code the API uses, including a signed link.
  const link = songs.signAudioUrl(deps, userId, job.songId);
  const exp = Number(new URL(link.path, 'http://x').searchParams.get('exp'));
  const sig = new URL(link.path, 'http://x').searchParams.get('sig')!;
  const served = await songs.readSongAudio(deps, job.songId, exp, sig);
  reopened = sha256Hex(served.data) === sha256Hex(bytes) && songs.listSongs(deps, userId).some((s) => s.id === job.songId);
  note('song.retrieved', { ...audioInfo, reopenedFromLibrary: reopened });
}

await finish(job.status === 'completed');

async function finish(ok: boolean): Promise<never> {
  const m = metrics(deps, new Date(t0 - 1000).toISOString());
  const checks = [
    ['Voice enrolled with the real provider and marked able to sing', voices.getVoice(deps, userId, voiceId!).status === 'ready'],
    ['Persistent job created and tracked to a terminal state', Boolean(job?.status)],
    ['Real provider call completed', job?.status === 'completed'],
    ['Result is recognisable audio of plausible size', Boolean(audioInfo && Number(audioInfo['bytes']) >= 4096 && audioInfo['mime'])],
    ['Song persisted and reopens from the library by signed link', reopened],
    ['Credits: reserved then captured exactly once (or released on failure)', ledgerOk()],
  ] as const;
  console.log('\n=== AUTOMATED CHECKS (these do NOT establish quality) ===');
  for (const [name, pass] of checks) console.log(`  ${pass ? 'PASS' : 'FAIL'}  ${name}`);
  console.log('  OPEN  Human listening evaluation: voice similarity, pronunciation, naturalness, arrangement (docs/poc/README.md)');
  console.log('  OPEN  Hausa / Arabic listeners — required before any claim of language support');
  if (exportPath) console.log(`\nAudio for listening (private, contains the participant's voice): ${exportPath}`);

  const result = {
    stamp, provider: provider.name, engine: caps.engineName, language, documentedLanguage: caps.documentedLanguages.includes(language),
    participantRecorded: participant, ownership, consentVersion: CONSENT_VERSION,
    voiceId, enrollMs, job: { id: job?.id, status: job?.status, failureCode: job?.failureCode ?? null, latencyMs },
    audio: audioInfo, exportPath, metrics: m, events, automatedChecks: Object.fromEntries(checks.map(([n, p]) => [n, p])),
    humanEvaluation: 'NOT DONE',
    note: 'Cost figures are rate-card estimates until reconciled against the provider invoice.',
  };
  const outDir = process.env['POC_OUT_DIR'] ?? join(here, '..', '..', 'docs', 'poc', 'results');
  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${stamp}-result.json`);
  // The result file is safe to commit: it holds no audio, no lyrics, no keys. Participant name is the operator's call.
  writeFileSync(file, JSON.stringify(result, null, 2));
  console.log(`Results written to ${file}`);
  db.close();
  process.exit(ok && checks.every(([, p]) => p) ? 0 : 1);
}

function ledgerOk(): boolean {
  const rows = all(db, `SELECT kind FROM credit_ledger WHERE job_id = ?`, job?.id ?? '').map((r) => String(r['kind']));
  if (rows.filter((k) => k === 'reserve').length !== 1) return false;
  const finals = rows.filter((k) => k === 'capture' || k === 'release');
  return finals.length === 1 && (job?.status === 'completed' ? finals[0] === 'capture' : finals[0] === 'release');
}
