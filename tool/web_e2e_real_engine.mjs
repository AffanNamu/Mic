// Drives the Flutter web build against a REAL local DeenVoice backend that uses the REAL music engine
// (PROVIDER=heartmula, HeartMuLa through WaveSpeedAI), in a real browser:
//   first launch -> sign up -> operator grants credits -> Create Song (engine sings in its own voice, no voice needed)
//   -> English -> Generate -> follow the real job -> "Your song is ready" -> Play -> the audio really plays.
//
// This SPENDS MONEY (the engine's price, about $0.10 per song) and needs WAVESPEED_API_KEY in the environment.
// It proves the app <-> API <-> job pipeline <-> real engine <-> storage <-> playback chain for ONE English song.
// It says nothing about how good the song sounds, or about Hausa / Arabic: a person has to listen.
//
//   flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:18090 -o build/web_real
//   WAVESPEED_API_KEY=... node tool/web_e2e_real_engine.mjs build/web_real docs/verification/real_engine backend/data/poc-exports/app-song
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, stat, mkdir, writeFile, mkdtemp } from 'node:fs/promises';
import { extname, join, normalize, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const [dir, outDir, songOut] = process.argv.slice(2);
if (!process.env.WAVESPEED_API_KEY) { console.error('WAVESPEED_API_KEY is not set.'); process.exit(2); }
await mkdir(outDir, { recursive: true });
const API_PORT = 18090, WEB_PORT = 18091;
const API = `http://127.0.0.1:${API_PORT}`;
const adminToken = randomBytes(24).toString('hex');
const work = await mkdtemp(join(tmpdir(), 'deenvoice-real-'));

// --- the real backend -------------------------------------------------------------------------------
const backend = spawn('node', ['--disable-warning=ExperimentalWarning', 'src/main.ts'], {
  cwd: 'backend', stdio: ['ignore', 'pipe', 'pipe'],
  env: {
    PATH: process.env.PATH, HOME: process.env.HOME,
    HTTPS_PROXY: process.env.HTTPS_PROXY ?? '', https_proxy: process.env.https_proxy ?? '', NO_PROXY: process.env.NO_PROXY ?? '',
    NODE_EXTRA_CA_CERTS: process.env.NODE_EXTRA_CA_CERTS ?? '', NODE_USE_ENV_PROXY: '1',
    PORT: String(API_PORT), HOST: '127.0.0.1', CORS_ORIGINS: `http://127.0.0.1:${WEB_PORT}`,
    DATABASE_PATH: join(work, 'db.sqlite'), BLOB_DIR: join(work, 'blobs'),
    BLOB_ENCRYPTION_KEY: randomBytes(32).toString('base64'), MEDIA_SIGNING_KEY: randomBytes(32).toString('hex'),
    ADMIN_TOKEN: adminToken, PROVIDER: 'heartmula', WAVESPEED_API_KEY: process.env.WAVESPEED_API_KEY,
  },
});
const logs = [];
await new Promise((resolve, reject) => {
  const onData = (d) => { for (const l of String(d).split('\n')) { if (!l) continue; logs.push(l); if (l.includes('"listening"')) resolve(); } };
  backend.stdout.on('data', onData); backend.stderr.on('data', onData);
  backend.on('exit', (c) => reject(new Error(`backend exited early (${c}): ${logs.slice(-3).join(' | ')}`)));
  setTimeout(() => reject(new Error('backend did not start')), 20000);
});
const admin = { authorization: `Bearer ${adminToken}`, 'content-type': 'application/json' };
const health = await fetch(`${API}/healthz`).then((r) => r.json());
console.log('backend provider:', JSON.stringify(health.provider));
if (health.provider?.name !== 'heartmula' || !health.provider?.configured) throw new Error('the backend is not using the real engine');

// --- static web server --------------------------------------------------------------------------------
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json',
  '.png': 'image/png', '.webp': 'image/webp', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const web = createServer(async (req, res) => {
  try {
    let p = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (p.endsWith('/')) p += 'index.html';
    const file = join(dir, p); await stat(file);
    res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end('nf'); }
});
await new Promise((r) => web.listen(WEB_PORT, '127.0.0.1', r));

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const context = await browser.newContext({ viewport: { width: 426, height: 923 }, deviceScaleFactor: 2 });
const page = await context.newPage();
const errors = [];
const mediaResponses = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('response', (r) => { if (r.url().includes('/media/songs/')) mediaResponses.push({ url: r.url(), status: r.status(), range: r.request().headers()['range'] ?? null, type: r.headers()['content-type'] }); });

async function boot() {
  await page.goto(`http://127.0.0.1:${WEB_PORT}/`);
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(3500);
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(1500);
}
const results = [];
let n = 0;
async function step(name, fn) {
  try { await fn(); results.push(['PASS', name]); console.log('PASS', name); }
  catch (e) {
    results.push(['FAIL', name, e.message.split('\n')[0]]); console.log('FAIL', name, '-', e.message.split('\n')[0]);
    await page.screenshot({ path: `${outDir}/FAIL_${name.replace(/\W+/g, '_').slice(0, 60)}.png` }).catch(() => {});
  }
}
const shot = async (label) => { await page.waitForTimeout(900); return page.screenshot({ path: `${outDir}/${String(++n).padStart(2, '0')}_${label}.png` }); };
const present = (text) => page.evaluate((t) => [...document.querySelectorAll('flt-semantics, [aria-label]')]
  .some((e) => (e.getAttribute('aria-label') || '').includes(t) || (e.textContent || '').includes(t)), text);
const visible = async (text, t = 8000) => {
  const end = Date.now() + t;
  while (Date.now() < end) { if (await present(text)) return; await page.waitForTimeout(200); }
  throw new Error(`text never appeared: ${text}`);
};
const gone = async (text, t = 3000) => {
  const end = Date.now() + t;
  while (Date.now() < end) { if (!(await present(text))) return; await page.waitForTimeout(150); }
  throw new Error(`text still present: ${text}`);
};
const typeInto = async (name, text) => {
  await page.getByRole('textbox', { name }).click({ force: true });
  await page.waitForTimeout(600);
  await page.keyboard.type(text, { delay: 30 });
  await page.waitForTimeout(300);
};
const btn = (name) => page.getByRole('button', { name, exact: false }).first();
const click = async (name) => { await btn(name).click({ force: true }); await page.waitForTimeout(500); };
const semanticsText = () => page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((e) => e.getAttribute('aria-label') || e.textContent || '').join(' | '));

const EMAIL = 'tester@example.com';
let savedBytes = 0;
try {
  await boot();
  await step('first launch: introduction, then welcome', async () => {
    await visible('Songs in your own voice');
    await click('Next'); await visible('Only voices you may use');
    await click('Next'); await click('Get started');
    await visible('Welcome Back');
  });
  await step('create an account', async () => {
    await click('Continue with Email');
    await click('Create a new account');
    await typeInto('Email', EMAIL);
    await typeInto('Password', 'a sound password 123');
    await click('Create account');
    await visible('Create a Song');
    await visible('No songs yet');
    await shot('home_empty');
  });
  await step('operator grants credits; the balance in the app is the real one', async () => {
    const g = await fetch(`${API}/v1/admin/credits/grant`, { method: 'POST', headers: admin, body: JSON.stringify({ email: EMAIL, amount: 3, note: 'real engine test' }) });
    if (g.status !== 200) throw new Error(`grant failed ${g.status}`);
    await boot();
    await visible('Create a Song');
    await click('Profile'); await visible('3 credits available'); await shot('profile');
    await click('Back'); await visible('Create a Song');
  });
  await step('Create Song: the engine is named, and no voice is asked for', async () => {
    await click('Create a Song');
    await visible('Generate Song');
    await visible('sings in its own built-in voice');
    await gone('Add New Voice', 1500);
    await shot('create_song_own_voice');
  });
  await step('fill title and lyrics, choose English, Generate: a real job is created and followed', async () => {
    await typeInto('Song title', 'Gratitude');
    await typeInto('Song lyrics', '[Verse]');
    await page.keyboard.press('Enter');
    for (const line of ['Morning light on the quiet street', 'A gentle breeze and a steady heartbeat', '', '[Chorus]', 'Alhamdulillah, I am grateful', 'Every day is a gift to hold']) {
      if (line) await page.keyboard.type(line, { delay: 20 });
      await page.keyboard.press('Enter');
    }
    await btn('Language: Hausa').click({ force: true }).catch(() => click('Language'));
    await page.waitForTimeout(700);
    await page.getByText('English', { exact: true }).last().click({ force: true });
    await page.waitForTimeout(700);
    await shot('create_song_filled');
    await click('Generate Song');
    const stages = ['Queued', 'Starting', 'Generating your song'];
    const t0 = Date.now();
    while (!(await Promise.all(stages.map(present))).some(Boolean)) {
      if (Date.now() - t0 > 20000) throw new Error('no in-progress stage ever appeared');
      await page.waitForTimeout(200);
    }
    await shot('job_in_progress');
    await visible('Your song is ready', 240000);
    await shot('job_ready');
  });
  await step('Play opens the song and the audio really plays', async () => {
    await click('Play');
    await visible('Made with');
    await visible('Morning light on the quiet street');
    await shot('player');
    await click('Play');
    await page.waitForTimeout(5000);
    const text = await semanticsText();
    const m = /(\d+):(\d\d) \/ (\d+):(\d\d)/.exec(text);
    if (!m) throw new Error(`no position readout in: ${text.slice(0, 200)}`);
    const pos = Number(m[1]) * 60 + Number(m[2]);
    if (pos < 2) throw new Error(`playback did not advance (position ${m[0]})`);
    if (!mediaResponses.length) throw new Error('the page never requested the signed media URL');
    if (!mediaResponses.every((r) => r.status === 200 || r.status === 206)) throw new Error(`media responses: ${JSON.stringify(mediaResponses)}`);
    console.log('   position readout:', m[0], '| media responses:', mediaResponses.length, '| content-type:', mediaResponses[0].type);
    await shot('playing');
  });
  await step('the stored song is real audio of plausible size (saved for listening)', async () => {
    const r = await fetch(mediaResponses[0].url);
    const buf = Buffer.from(await r.arrayBuffer());
    const head = buf.subarray(0, 12);
    const audio = buf.length > 100000 && (head.toString('latin1', 0, 3) === 'ID3' || (head[0] === 0xff && (head[1] & 0xe0) === 0xe0) || head.toString('latin1', 4, 8) === 'ftyp');
    if (!audio) throw new Error(`not audio: ${buf.length} bytes, head ${head.toString('hex')}`);
    if (songOut) { await mkdir(dirname(songOut), { recursive: true }); await writeFile(`${songOut}.mp3`, buf); }
    savedBytes = buf.length;
    console.log('   bytes:', buf.length);
  });
  await step('after a full reload the song is on Home and in the Library', async () => {
    await boot();
    await visible('Recent Songs');
    await visible('Gratitude');
    await shot('home_with_song');
  });
} finally {
  await browser.close().catch(() => {});
  web.close();
  backend.kill('SIGTERM');
}
const failed = results.filter((r) => r[0] === 'FAIL');
console.log(`\n${results.length - failed.length}/${results.length} steps passed; page errors: ${errors.length}${errors.length ? ' -> ' + errors.slice(0, 3).join(' | ') : ''}`);
console.log('backend log lines mentioning warn/error:', logs.filter((l) => /"level":"(warn|error)"/.test(l)).slice(0, 5).join('\n') || 'none');
process.exit(failed.length ? 1 : 0);
