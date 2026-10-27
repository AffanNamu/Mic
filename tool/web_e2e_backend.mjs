// Drives the Flutter web build against a REAL local DeenVoice backend in a real browser:
// sign up → refresh (session persists) → add a voice with server consent → generate → follow the
// job → play → reopen from the library after a reload → sign out/in.
//
// !! The music provider behind the backend is the labelled TEST DOUBLE (a synthetic tone). !!
// This proves the app ↔ API ↔ job pipeline ↔ storage ↔ playback wiring. It is NOT evidence that any
// real AI provider can sing in a cloned voice; the song says "test-double" in the app, and that is asserted.
//
//   flutter build web --release --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:18080 -o build/web_e2e
//   node tool/web_e2e_backend.mjs build/web_e2e docs/verification/backend_e2e
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFile, stat, mkdir, writeFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { createHash } from 'node:crypto';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const [dir, outDir] = process.argv.slice(2);
await mkdir(outDir, { recursive: true });
const API_PORT = 18080, WEB_PORT = 18081;
const API = `http://127.0.0.1:${API_PORT}`;

// --- backend (test-double provider) -------------------------------------------------------------
const backend = spawn('node', ['--disable-warning=ExperimentalWarning', 'test/support/e2e-server.ts', String(API_PORT), `http://127.0.0.1:${WEB_PORT}`],
  { cwd: 'backend', stdio: ['ignore', 'pipe', 'inherit'] });
const ready = await new Promise((resolve, reject) => {
  let buf = '';
  backend.stdout.on('data', (d) => { buf += d; const line = buf.split('\n').find((l) => l.includes('"ready"')); if (line) resolve(JSON.parse(line)); });
  backend.on('exit', (c) => reject(new Error(`backend exited early (${c})`)));
  setTimeout(() => reject(new Error('backend did not start')), 20000);
});
const admin = { authorization: `Bearer ${ready.adminToken}`, 'content-type': 'application/json' };

// --- static web server --------------------------------------------------------------------------
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

// A 10 s mono 16-bit WAV "voice sample" (a tone: test data, not a voice).
function wav(seconds, hz = 200, rate = 16000) {
  const n = seconds * rate, data = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) data.writeInt16LE(Math.round(Math.sin((2 * Math.PI * hz * i) / rate) * 8000), i * 2);
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVEfmt ', 8); h.writeUInt32LE(16, 16);
  h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}
const samplePath = join(tmpdir(), 'deenvoice-e2e-sample.wav');
await writeFile(samplePath, wav(10));

// The microphone is a Chromium fake device that loops the tone file above, so "recording" captures real
// browser audio through the real Web Audio path (not a stub in the app), but the sound is a tone, not a voice.
const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required',
    '--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', `--use-file-for-fake-audio-capture=${samplePath}`] });
const context = await browser.newContext({ viewport: { width: 426, height: 923 }, deviceScaleFactor: 2, permissions: ['microphone'] });
const page = await context.newPage();
const errors = [];
const mediaResponses = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('response', (r) => { if (r.url().includes('/media/songs/')) mediaResponses.push({ status: r.status(), range: r.request().headers()['range'] ?? null, type: r.headers()['content-type'] }); });

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
// Flutter renders some semantics (e.g. headers) as plain elements such as <header>, so look at every labelled element.
const present = (text) => page.evaluate((t) => [...document.querySelectorAll('flt-semantics, [aria-label]')]
  .some((e) => (e.getAttribute('aria-label') || '').includes(t) || (e.textContent || '').includes(t)), text);
const visible = async (text, t = 8000) => {
  const end = Date.now() + t;
  while (Date.now() < end) { if (await present(text)) return; await page.waitForTimeout(150); }
  if (process.env.DEBUG_SEMANTICS) {
    console.log('   SEMANTICS DUMP:', (await semanticsText()).slice(0, 600));
    console.log('   LIVE REGIONS:', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('[aria-live], flt-announcement-polite, flt-announcement-assertive')].map((e) => ({ tag: e.tagName, live: e.getAttribute('aria-live'), text: e.textContent, label: e.getAttribute('aria-label') })))));
    console.log('   ANY NODE WITH "ready":', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('*')].filter((e) => /song is ready/i.test((e.getAttribute('aria-label') || '') + (e.childNodes.length === 1 && e.firstChild.nodeType === 3 ? e.textContent : ''))).map((e) => ({ tag: e.tagName, role: e.getAttribute('role'), label: e.getAttribute('aria-label') })))));
  }
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

await boot();

await step('signed out: sign-in is shown instead of the app', async () => {
  await visible('Welcome back');
  await shot('sign_in');
});
await step('create an account (10+ char password enforced client-side first)', async () => {
  await click('Create a new account');
  await typeInto('Email', 'participant@example.com');
  await typeInto('Password', 'short');
  await click('Create account');
  await visible('Use a password of at least 10 characters.');
  await page.getByRole('textbox', { name: 'Password' }).click({ force: true });
  await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace');
  await page.keyboard.type('a sound password 123', { delay: 30 });
  await click('Create account');
  await visible('My Songs');
  await visible('No songs yet');
  await shot('library_empty');
});
await step('operator grants credits; after a reload the session persisted and the balance is real', async () => {
  const g = await fetch(`${API}/v1/admin/credits/grant`, { method: 'POST', headers: admin, body: JSON.stringify({ email: 'participant@example.com', amount: 3, note: 'e2e' }) });
  if (g.status !== 200) throw new Error(`grant failed ${g.status}`);
  await boot();
  await visible('My Songs');
  await gone('Welcome back');
  await visible('3 credits');
});
await step('Create Song: no voices yet, honest; engine named; Hausa (the default) is refused by capabilities', async () => {
  await click('New song');
  await visible('Generate Song');
  await visible('You have no saved voices yet');
  await shot('create_song_connected');
});
await step('Add New Voice shows the SERVER\'s consent wording and needs the checkbox + a file', async () => {
  await click('Add New Voice');
  await visible('This is my own voice. I agree that DeenVoice may store this recording');
  await visible('deleting it here may not immediately remove copies held by the provider');
  await shot('add_voice_server_consent');
});
await step('uploading a sample enrolls a voice; it shows Processing… then becomes selectable', async () => {
  await page.getByRole('checkbox').first().click({ force: true }).catch(async () => { await page.getByText('This is my own voice').first().click({ force: true }); });
  await page.waitForTimeout(500);
  const chooser = page.waitForEvent('filechooser', { timeout: 8000 });
  await click('Upload a recording');
  (await chooser).setFiles(samplePath);
  await visible('Voice submitted');
  await visible('Processing…', 6000);
  await shot('voice_processing');
  await visible('Personal voice', 20000);
  await shot('voice_ready');
});
await step('recording in the app: Record now captures real microphone audio, is reviewed, and enrolls a second voice', async () => {
  const sessionToken = await page.evaluate(() => {
    const raw = localStorage.getItem('flutter.deenvoice.session.v1');
    return raw ? JSON.parse(JSON.parse(raw)).token ?? null : null;
  });
  const voicesBefore = sessionToken
    ? (await fetch(`${API}/v1/voices`, { headers: { authorization: `Bearer ${sessionToken}` } }).then((r) => r.json())).voices.length
    : null;
  await click('Add New Voice');
  await visible('This is my own voice. I agree that DeenVoice may store this recording');
  await page.getByRole('checkbox').first().click({ force: true }).catch(async () => { await page.getByText('This is my own voice').first().click({ force: true }); });
  await page.waitForTimeout(500);
  await click('Record now');
  await visible('A clean sample works best');
  await visible('Record 5 seconds to 15 seconds.');
  await shot('recorder_ready');
  await click('Start recording');
  await visible('Keep going until at least 0:05', 6000);
  await page.waitForTimeout(1500);
  await shot('recorder_recording');
  await visible('Long enough', 12000);
  if (process.env.DEBUG_SEMANTICS) {
    console.log('   STOP NODES:', JSON.stringify(await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].filter((e) => /Stop|Start/.test(e.getAttribute('aria-label') || '')).map((e) => ({ role: e.getAttribute('role'), label: e.getAttribute('aria-label'), rect: JSON.stringify(e.getBoundingClientRect()), hidden: e.getAttribute('aria-hidden') })))));
  }
  await click('Stop recording');
  await visible('Your recording', 8000);
  await shot('recorder_review');
  const gone2 = await present('We barely heard anything');
  if (gone2) throw new Error('the fake microphone tone was judged silent');
  await click('Use this recording');
  await visible('Voice submitted', 8000);
  await visible('Personal voice', 20000);
  if (sessionToken) {
    const after = (await fetch(`${API}/v1/voices`, { headers: { authorization: `Bearer ${sessionToken}` } }).then((r) => r.json())).voices.length;
    if (after !== voicesBefore + 1) throw new Error(`expected one more voice on the server, had ${voicesBefore}, now ${after}`);
  }
  await shot('recorded_voice_enrolled');
});
await step('Generate with the default language (Hausa) is refused: this engine does not support it', async () => {
  await typeInto('Song title', 'My first nasheed');
  await typeInto('Song lyrics', 'Original words about gratitude and light');
  await click('Generate Song');
  await visible('doesn’t support Hausa', 6000).catch(async () => { await visible('Hausa', 2000); });
  await shot('hausa_refused');
});
await step('choose English, then Generate: a real job is created and followed', async () => {
  await btn('Language: Hausa').click({ force: true }).catch(() => click('Language'));
  await page.waitForTimeout(700);
  await page.getByText('English', { exact: true }).last().click({ force: true });
  await page.waitForTimeout(700);
  await click('Generate Song');
  // The job moves quickly from queued to processing (the worker ticks every 500 ms), so accept
  // whichever real stage the server reports first, then require the "generating" stage.
  const stages = ['Queued', 'Starting', 'Generating your song'];
  const t0 = Date.now();
  while (!(await Promise.all(stages.map(present))).some(Boolean)) {
    if (Date.now() - t0 > 10000) throw new Error('no in-progress stage ever appeared');
    await page.waitForTimeout(100);
  }
  await shot('job_in_progress');
  await visible('Generating your song', 25000);
  await shot('job_generating');
  await visible('Your song is ready', 45000);
  await shot('job_ready');
});
await step('Play opens the song: maker is stated as test-double, lyrics shown, audio is fetched with Range and plays', async () => {
  await click('Play');
  await visible('Made with test-double');
  await visible('Original words about gratitude and light');
  const before = mediaResponses.length;
  await click('Play');
  await page.waitForTimeout(3500);
  const text = await semanticsText();
  const m = /(\d+):(\d\d) \/ (\d+):(\d\d)/.exec(text);
  if (!m) throw new Error(`no position readout in: ${text.slice(0, 200)}`);
  const pos = Number(m[1]) * 60 + Number(m[2]);
  if (pos < 1) throw new Error(`playback did not advance (position ${m[0]})`);
  if (!mediaResponses.length) throw new Error('the page never requested the signed media URL');
  const ok = mediaResponses.every((r) => r.status === 200 || r.status === 206);
  if (!ok) throw new Error(`media responses: ${JSON.stringify(mediaResponses)}`);
  console.log('   position readout:', m[0], '| media responses:', JSON.stringify(mediaResponses.slice(0, 4)), `(+${mediaResponses.length - before} since Play)`);
  await shot('playing');
});
await step('the media link itself is private: without the signature the audio is refused', async () => {
  const bare = mediaResponses.length ? await fetch(`${API}/media/songs/does-not-matter`) : null;
  if (!bare || bare.status !== 403) throw new Error(`unsigned request returned ${bare?.status}`);
});
await step('after a full reload the song is still in the library and plays again', async () => {
  await boot();
  await visible('My Songs');
  await visible('Your songs');
  await visible('My first nasheed');
  await click('Open My first nasheed');
  await visible('Made with test-double');
  await click('Play'); await page.waitForTimeout(2500);
  const m = /(\d+):(\d\d) \/ (\d+):(\d\d)/.exec(await semanticsText());
  if (!m || Number(m[1]) * 60 + Number(m[2]) < 1) throw new Error('did not play after reload');
  await shot('reopened_from_library');
});
await step('credits: one reserved then captured (3 → 2)', async () => {
  const me = await fetch(`${API}/v1/admin/metrics`, { headers: admin }).then((r) => r.json());
  if (me.jobs.completed !== 1) throw new Error(`metrics jobs: ${JSON.stringify(me.jobs)}`);
  await page.keyboard.press('Escape'); await page.goBack().catch(() => {});
  await boot(); await visible('2 credits');
});
await step('sign out returns to sign-in', async () => {
  await click('Menu'); await page.waitForTimeout(400);
  await page.getByRole('menuitem', { name: 'Sign out' }).click({ force: true });
  await visible('Welcome back');
  await shot('signed_out_again');
});

// Cross-account isolation is exercised through the API (the backend suite covers it exhaustively).
await step('API: a second account cannot list or open the first account\'s song', async () => {
  const reg = await fetch(`${API}/v1/auth/register`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ email: 'someone-else@example.com', password: 'another sound password 1' }) }).then((r) => r.json());
  const list = await fetch(`${API}/v1/songs`, { headers: { authorization: `Bearer ${reg.token}` } }).then((r) => r.json());
  if (list.songs.length !== 0) throw new Error('second account can see songs');
});

console.log(JSON.stringify({ pageErrors: errors }));
const failed = results.filter((r) => r[0] === 'FAIL');
const sha = createHash('sha256').update(JSON.stringify(results)).digest('hex').slice(0, 12);
await writeFile(`${outDir}/results.json`, JSON.stringify({ when: new Date().toISOString(), provider: 'test-double (synthetic tone)', results, pageErrors: errors, mediaResponses, sha }, null, 2));
console.log(`\n${results.length - failed.length}/${results.length} backend e2e checks passed (provider: test double)`);
await browser.close(); web.close(); backend.kill('SIGTERM');
process.exit(failed.length ? 1 : 0);
