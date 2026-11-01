#!/usr/bin/env node
// HeartMuLa (WaveSpeedAI) contract probe. Run it with a real key BEFORE trusting src/provider/wavespeed.ts.
//
// The adapter was written from WaveSpeedAI's documentation, without an account. This tool turns each of its
// assumptions into an observed fact and records the evidence.
//
//   WAVESPEED_API_KEY=... node scripts/heartmula-probe.mjs --balance
//       Key check. Reads the account balance in USD (GET /api/v3/balance). Costs nothing.
//
//   WAVESPEED_API_KEY=... node scripts/heartmula-probe.mjs --generate --lyrics lyrics.txt [--tags "pop, calm"] [--save-audio song.mp3] --spend
//       SPENDS MONEY (the rate card says $0.10). Submits ONE song, polls it, downloads it and checks that the
//       bytes are audio. The submit request is sent once and never retried: if its answer is lost, the task may
//       exist and be billed, so look in the WaveSpeedAI History page before running it again.
//
// Every request/response is written to docs/poc/transcripts/ (or PROBE_OUT_DIR) with the Authorization header
// removed. Nothing here runs unless you ask for it, and nothing spends without --spend.
// Behind an HTTP proxy, Node's fetch ignores HTTPS_PROXY unless NODE_USE_ENV_PROXY=1 (Node >= 22.21).

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = process.env.PROBE_OUT_DIR ?? join(here, '..', '..', 'docs', 'poc', 'transcripts');
const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };

const base = process.env.WAVESPEED_BASE_URL ?? 'https://api.wavespeed.ai';
const key = process.env.WAVESPEED_API_KEY;
const pollMs = Number(process.env.PROBE_POLL_MS ?? 5000);
const stamp = new Date().toISOString().replace(/[:.]/g, '-');
const transcript = [];

const clip = (s) => (s.length > 6000 ? `${s.slice(0, 6000)}…[${s.length - 6000} more chars]` : s);
const redact = (h) => Object.fromEntries(Object.entries(h).map(([k, v]) => [k, k.toLowerCase() === 'authorization' ? 'Bearer [redacted]' : v]));
const auth = () => {
  if (!key) { console.error('WAVESPEED_API_KEY is not set.'); process.exit(2); }
  return { Authorization: `Bearer ${key}`, Accept: 'application/json' };
};
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
    const res = await fetch(url, { method, headers, body, signal: AbortSignal.timeout(60_000) });
    const buf = Buffer.from(await res.arrayBuffer());
    entry.status = res.status;
    entry.ms = Date.now() - started;
    entry.responseHeaders = Object.fromEntries([...res.headers].filter(([k]) => ['content-type', 'content-length', 'retry-after'].includes(k)));
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

const task = (body) => (body && typeof body === 'object' && body.data && typeof body.data === 'object' ? body.data : body);
const parse = (buf) => { try { return JSON.parse(buf.toString('utf8')); } catch { return null; } };

// ------------------------------------------------------------------ --balance
async function balance() {
  console.log(`GET ${base}/api/v3/balance`);
  const { res, buf, error } = await call('balance', 'GET', `${base}/api/v3/balance`, { headers: auth() });
  if (!res) console.log(`Network error: ${error}`);
  else {
    console.log(`HTTP ${res.status}`);
    console.log(buf.toString('utf8').slice(0, 800));
    if (res.status === 401 || res.status === 403) console.log('\nThe key was rejected. Do not continue until this is fixed.');
    const b = task(parse(buf))?.balance;
    if (typeof b === 'number') console.log(`\nBalance: $${b}${b < 0.1 ? '  — less than one song ($0.10): top up before --generate' : ''}`);
  }
  save('balance');
}

// ------------------------------------------------------------------ --generate
async function generate() {
  if (!flag('--spend')) {
    console.error('Refusing to run: --generate spends money (the rate card says $0.10 a song). Re-run with --spend to confirm.');
    process.exit(2);
  }
  const lyricsFile = opt('--lyrics');
  if (!lyricsFile) { console.error('--lyrics <file> is required (use ORIGINAL lyrics you have the right to use).'); process.exit(2); }
  const text = readFileSync(lyricsFile, 'utf8').replace(/\r\n?/g, '\n').trim();
  const lyrics = /^\s*\[[^\]\n]+\]\s*$/m.test(text) ? text : `[verse]\n${text}`;
  const payload = { lyrics };
  const tags = opt('--tags');
  if (tags) payload.tags = tags;

  const checks = [];
  const check = (name, ok, detail = '') => { checks.push({ name, ok, detail }); console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`); };

  const t0 = Date.now();
  const sub = await call('submit', 'POST', `${base}/api/v3/wavespeed-ai/heartmula/generate-music`, { headers: { ...auth(), 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
  console.log(`\nsubmit → HTTP ${sub.res?.status ?? 'network error'}  (sent once; never retried)`);
  const body = parse(sub.buf);
  if (sub.res && !sub.res.ok && /1407|insufficient/i.test(JSON.stringify(body))) {
    console.log('  The account is out of credit (error 1407). Top up, then re-run. Nothing was generated or billed.');
  }
  if (!sub.res) console.log('  The answer was lost: a task may exist and be billed. Check the WaveSpeedAI History page before running again.');
  check('submit returned 2xx', Boolean(sub.res?.ok), sub.res ? `HTTP ${sub.res.status}` : sub.error);
  const first = task(body);
  const id = first?.id;
  check('submit response has the prediction id in `data.id` or `id` (adapter assumption)', Boolean(id), body ? `keys: ${Object.keys(body).join(', ')}${first !== body ? `; data keys: ${Object.keys(first).join(', ')}` : ''}` : 'unparseable');
  if (!id) { summary(checks); return save('generate'); }

  let final = null;
  const seen = new Set();
  for (let i = 0; i < 240; i++) {
    await new Promise((r) => setTimeout(r, pollMs));
    const q = await call(`result #${i + 1}`, 'GET', `${base}/api/v3/predictions/${encodeURIComponent(String(id))}/result`, { headers: auth() });
    const r = task(parse(q.buf));
    const status = r?.status;
    if (status) seen.add(String(status));
    process.stdout.write(`  poll ${i + 1}: HTTP ${q.res?.status ?? 'err'} status=${status ?? '?'}\n`);
    if (q.res && q.res.ok && status && ['completed', 'failed', 'cancelled', 'canceled', 'timeout', 'deleted'].includes(String(status).toLowerCase())) { final = r; break; }
    if (q.res && q.res.status >= 400 && q.res.status < 500 && q.res.status !== 429) break; // a request problem: asking again will not help
  }
  const latencyMs = Date.now() - t0;
  console.log(`\nStatus values observed: ${[...seen].join(', ') || '(none)'}`);
  console.log('Adapter treats `completed` as success; failed/cancelled/timeout/deleted as failure; anything else as "keep waiting".');
  check('prediction reached a final status', Boolean(final), `${Math.round(latencyMs / 1000)} s`);
  check('final status is `completed`', final?.status === 'completed', `status=${final?.status}${final?.error ? `, error=${final.error}` : ''}`);
  const out = Array.isArray(final?.outputs) ? final.outputs[0] : undefined;
  const url = typeof out === 'string' ? out : out?.url;
  check('result has outputs[0] as a URL (adapter assumption)', Boolean(url), final ? `keys: ${Object.keys(final).join(', ')}; outputs: ${JSON.stringify(final.outputs)?.slice(0, 200)}` : '');
  if (url) {
    console.log(`  download host: ${new URL(url).hostname}  (put it in WAVESPEED_AUDIO_HOSTS to restrict downloads to it)`);
    const dl = await call('download', 'GET', url, { binary: true });
    const head = dl.buf.subarray(0, 12);
    const audio = dl.buf.length >= 4096 && (head.toString('latin1', 0, 3) === 'ID3' || (head[0] === 0xff && (head[1] & 0xe0) === 0xe0) || head.toString('latin1', 0, 4) === 'RIFF' || head.toString('latin1', 0, 4) === 'fLaC' || head.toString('latin1', 4, 8) === 'ftyp');
    check('downloaded bytes are recognisable audio of plausible size', audio, `${dl.buf.length} bytes, first bytes ${head.toString('hex')}`);
    const saveTo = opt('--save-audio');
    if (saveTo && audio) { mkdirSync(dirname(saveTo), { recursive: true }); writeFileSync(saveTo, dl.buf); console.log(`  audio saved to ${saveTo} (keep it private: do not commit it)`); }
    check('a human has listened and judged the song (NOT automated)', false, 'listening evaluation is required; see docs/poc/README.md');
  }
  console.log(`\nLatency submit→ready: ${Math.round(latencyMs / 1000)} s`);
  summary(checks);
  save('generate');
}

function summary(checks) {
  const bad = checks.filter((c) => !c.ok).length;
  console.log(`\n${checks.length - bad}/${checks.length} checks passed. A passing probe means the adapter's assumptions held for this one request;`);
  console.log('it does not mean the song is good, or that Hausa or Arabic is sung correctly. Listen to it, and record the result.');
}

if (flag('--balance')) await balance();
else if (flag('--generate')) await generate();
else {
  console.log('Usage: --balance | --generate --lyrics <file> [--tags <tags>] [--save-audio <file>] --spend');
  process.exit(1);
}
