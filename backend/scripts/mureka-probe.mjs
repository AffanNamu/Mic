#!/usr/bin/env node
// Mureka contract probe. Run this on a machine that can reach Mureka, BEFORE trusting the adapter.
//
// The adapter in src/provider/mureka.ts was written without being able to reach Mureka (the build
// environment's network policy blocked it). Several of its field names and status values come from
// memory. This tool turns each assumption into an observed fact, and records the evidence.
//
//   node scripts/mureka-probe.mjs --discover
//       No key. Fetches Mureka's public API pages and lists the /v1/... operations they mention,
//       so you can find the voice-cloning operation and read its fields. Costs nothing.
//
//   MUREKA_API_KEY=... node scripts/mureka-probe.mjs --billing
//       Key check. Reads your account/billing endpoint (path is itself an assumption). Costs nothing.
//
//   MUREKA_API_KEY=... node scripts/mureka-probe.mjs --generate --lyrics lyrics.txt --spend [--vocal-id ID]
//       SPENDS MONEY (about $0.045-$0.15). Generates one lyrics-to-song, polls, downloads, and checks
//       that the bytes are audio. Compares each response against what the adapter assumes.
//
// Every request/response is written to docs/poc/transcripts/ with the Authorization header removed.
// Nothing here runs unless you ask for it, and nothing spends without --spend.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', 'docs', 'poc', 'transcripts');
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };

const base = process.env.MUREKA_BASE_URL ?? 'https://api.mureka.ai';
const key = process.env.MUREKA_API_KEY;
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const transcript = [];

const DOC_PAGES = [
  'https://platform.mureka.ai/docs/en/quickstart.html',
  'https://platform.mureka.ai/docs/en/changelog.html',
  'https://platform.mureka.ai/docs/en/faq.html',
  'https://platform.mureka.ai/docs/api/operations/post-v1-song-generate.html',
  'https://platform.mureka.ai/docs/api/operations/post-v1-files-upload.html',
];

function save(name) {
  mkdirSync(outDir, { recursive: true });
  const file = join(outDir, `${stamp}-${name}.json`);
  writeFileSync(file, JSON.stringify(transcript, null, 2));
  console.log(`\nTranscript written to ${file}`);
}

async function call(label, method, url, { headers = {}, body, binary = false } = {}) {
  const started = Date.now();
  const entry = { label, method, url, requestHeaders: redact(headers), requestBody: typeof body === 'string' ? clip(body) : undefined };
  try {
    const res = await fetch(url, { method, headers, body });
    const buf = Buffer.from(await res.arrayBuffer());
    entry.status = res.status;
    entry.ms = Date.now() - started;
    entry.responseHeaders = Object.fromEntries([...res.headers].filter(([k]) => ['content-type', 'content-length', 'retry-after', 'x-request-id'].includes(k)));
    if (binary) {
      entry.responseBytes = buf.length;
      entry.responseSha256 = createHash('sha256').update(buf).digest('hex');
      entry.responseHead = buf.subarray(0, 16).toString('hex');
    } else {
      entry.responseBody = clip(buf.toString('utf8'));
    }
    transcript.push(entry);
    return { res, buf };
  } catch (err) {
    entry.error = String(err?.cause?.code ?? err?.message ?? err);
    entry.ms = Date.now() - started;
    transcript.push(entry);
    return { res: null, buf: Buffer.alloc(0), error: entry.error };
  }
}

const clip = (s) => (s.length > 6000 ? `${s.slice(0, 6000)}…[${s.length - 6000} more chars]` : s);
function redact(h) {
  return Object.fromEntries(Object.entries(h).map(([k, v]) => [k, k.toLowerCase() === 'authorization' ? 'Bearer [redacted]' : v]));
}
const auth = () => {
  if (!key) { console.error('MUREKA_API_KEY is not set.'); process.exit(2); }
  return { Authorization: `Bearer ${key}`, Accept: 'application/json' };
};

// ------------------------------------------------------------------ --discover
async function discover() {
  console.log('Fetching public Mureka API pages (no key)…\n');
  const found = new Map();
  let reached = 0;
  for (const url of DOC_PAGES) {
    const { res, buf, error } = await call(`docs ${url}`, 'GET', url);
    if (!res) { console.log(`  unreachable  ${url}  (${error})`); continue; }
    console.log(`  ${res.status}  ${url}`);
    if (!res.ok) continue;
    reached++;
    const text = buf.toString('utf8');
    for (const m of text.matchAll(/\/v1\/[a-z0-9_\-/{}]+/gi)) {
      const p = m[0].replace(/[.,;)]+$/, '');
      (found.get(p) ?? found.set(p, new Set()).get(p)).add(url.split('/').pop());
    }
    for (const m of text.matchAll(/href="([^"]*operations\/[^"]+)"/gi)) {
      const link = new URL(m[1], url).toString();
      if (!DOC_PAGES.includes(link) && DOC_PAGES.length < 40) DOC_PAGES.push(link); // follow operation links one level
    }
  }
  if (reached === 0) {
    console.log('\nNo page could be fetched from this machine. Check network access to platform.mureka.ai.');
  } else {
    console.log('\n/v1 operations mentioned (look for the voice / vocal operation and read its page):');
    for (const [p, pages] of [...found].sort()) console.log(`  ${p}   [${[...pages].join(', ')}]`);
    console.log('\nThen set MUREKA_VOCAL_CLONE_PATH to the operation path, check the multipart field names against');
    console.log('src/provider/mureka.ts (enrollVoice), and record what you found in docs/PROVIDER_EVALUATION.md.');
  }
  save('discover');
}

// ------------------------------------------------------------------ --billing
async function billing() {
  const path = opt('--path') ?? '/v1/account/billing'; // ASSUMED path
  console.log(`GET ${base}${path}  (assumed path; pass --path to try another)`);
  const { res, buf, error } = await call('billing', 'GET', `${base}${path}`, { headers: auth() });
  if (!res) console.log(`Network error: ${error}`);
  else {
    console.log(`HTTP ${res.status}`);
    console.log(buf.toString('utf8').slice(0, 800));
    if (res.status === 401 || res.status === 403) console.log('\nThe key was rejected. Do not continue until this is fixed.');
  }
  save('billing');
}

// ------------------------------------------------------------------ --generate
async function generate() {
  if (!flag('--spend')) {
    console.error('Refusing to run: --generate spends money (about $0.045-$0.15). Re-run with --spend to confirm.');
    process.exit(2);
  }
  const lyricsFile = opt('--lyrics');
  if (!lyricsFile) { console.error('--lyrics <file> is required (use ORIGINAL lyrics you have the right to use).'); process.exit(2); }
  const lyrics = readFileSync(lyricsFile, 'utf8').trim();
  const payload = { lyrics, model: opt('--model') ?? process.env.MUREKA_MODEL ?? 'auto', prompt: opt('--prompt') ?? 'English nasheed, peaceful, acoustic' };
  if (opt('--vocal-id')) payload.vocal_id = opt('--vocal-id');

  const checks = [];
  const check = (name, ok, detail = '') => { checks.push({ name, ok, detail }); console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };

  const t0 = Date.now();
  const sub = await call('generate', 'POST', `${base}/v1/song/generate`, { headers: { ...auth(), 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  console.log(`\nsubmit → HTTP ${sub.res?.status ?? 'network error'}`);
  let body = null;
  try { body = JSON.parse(sub.buf.toString('utf8')); } catch { /* reported below */ }
  check('submit returned 2xx', Boolean(sub.res?.ok), sub.res ? `HTTP ${sub.res.status}` : sub.error);
  const taskId = body && (body.id ?? body.task_id);
  check('submit response has a task id in `id` or `task_id` (adapter assumption)', Boolean(taskId), body ? `keys: ${Object.keys(body).join(', ')}` : 'unparseable');
  if (!taskId) { summary(checks); return save('generate'); }

  let final = null;
  const seenStatuses = new Set();
  for (let i = 0; i < 120; i++) {
    await new Promise((r) => setTimeout(r, 5000));
    const q = await call(`query #${i + 1}`, 'GET', `${base}/v1/song/query/${encodeURIComponent(String(taskId))}`, { headers: auth() });
    let qb = null;
    try { qb = JSON.parse(q.buf.toString('utf8')); } catch { /* ignore */ }
    const status = qb?.status;
    if (status) seenStatuses.add(String(status));
    process.stdout.write(`  poll ${i + 1}: HTTP ${q.res?.status ?? 'err'} status=${status ?? '?'}\n`);
    if (qb && !['preparing', 'queued', 'running', 'streaming', 'pending', 'processing'].includes(String(status).toLowerCase())) { final = qb; break; }
  }
  const latencyMs = Date.now() - t0;
  console.log(`\nStatus values observed: ${[...seenStatuses].join(', ') || '(none)'}`);
  console.log('Adapter treats these as success: succeeded/success/completed; failure: failed/timeouted/timed_out/cancelled/canceled/error.');
  check('generation reached a terminal status within 10 minutes', Boolean(final), `${Math.round(latencyMs / 1000)} s`);
  const ok = final && ['succeeded', 'success', 'completed'].includes(String(final.status).toLowerCase());
  check('terminal status is one the adapter recognises as success', Boolean(ok), `status=${final?.status}`);
  const first = Array.isArray(final?.choices) ? final.choices[0] : undefined;
  const url = first?.url ?? first?.mp3_url ?? first?.flac_url;
  check('result has choices[0].url (adapter assumption)', Boolean(url), final ? `keys: ${Object.keys(final).join(', ')}${first ? `; choice keys: ${Object.keys(first).join(', ')}` : ''}` : '');
  if (url) {
    const dl = await call('download', 'GET', url, { binary: true });
    const head = dl.buf.subarray(0, 12);
    const audio = dl.buf.length >= 4096 && (head.toString('latin1', 0, 3) === 'ID3' || (head[0] === 0xff && (head[1] & 0xe0) === 0xe0) || head.toString('latin1', 0, 4) === 'RIFF' || head.toString('latin1', 0, 4) === 'fLaC' || head.toString('latin1', 4, 8) === 'ftyp');
    check('downloaded bytes are recognisable audio of plausible size', audio, `${dl.buf.length} bytes, first bytes ${head.toString('hex')}`);
    check('a human has listened and judged the song (NOT automated)', false, 'listening evaluation is required; see docs/poc/README.md');
  }
  console.log(`\nLatency submit→ready: ${Math.round(latencyMs / 1000)} s`);
  summary(checks);
  save('generate');
}

function summary(checks) {
  const bad = checks.filter((c) => !c.ok).length;
  console.log(`\n${checks.length - bad}/${checks.length} checks passed. A passing probe means the adapter's assumptions held for this one request;`);
  console.log('it does not mean the song is good. Listen to it, and record the result.');
}

if (flag('--discover')) await discover();
else if (flag('--billing')) await billing();
else if (flag('--generate')) await generate();
else {
  console.log('Usage: --discover | --billing | --generate --lyrics <file> --spend [--vocal-id <id>] [--model <m>] [--prompt <p>]');
  process.exit(1);
}
