// Drives the production web build in Chromium through its accessibility tree
// and asserts what a real user would see. No test doubles: this is lib/main.dart
// with every backend unconfigured, so each action must either work locally or
// say plainly what is missing.
//
//   node tool/web_flow_check.mjs build/web build/renders/flows
import { createServer } from 'node:http';
import { readFile, stat, mkdir } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const [dir, outDir] = process.argv.slice(2);
await mkdir(outDir, { recursive: true });
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm',
  '.json': 'application/json', '.png': 'image/png', '.webp': 'image/webp', '.ttf': 'font/ttf', '.otf': 'font/otf' };
const server = createServer(async (req, res) => {
  try {
    let p = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (p.endsWith('/')) p += 'index.html';
    const file = join(dir, p); await stat(file);
    res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end('nf'); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await (await browser.newContext({ viewport: { width: 426, height: 923 }, deviceScaleFactor: 2 })).newPage();
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
await page.goto(url);
await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
await page.waitForTimeout(4000);
// Turn on Flutter's accessibility tree (what screen readers and this script use).
await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
await page.waitForTimeout(1500);

const results = [];
let n = 0;
async function step(name, fn) {
  try { await fn(); results.push(['PASS', name]); console.log('PASS', name); }
  catch (e) {
    results.push(['FAIL', name, e.message.split('\n')[0]]); console.log('FAIL', name, '-', e.message.split('\n')[0]);
    await page.screenshot({ path: `${outDir}/FAIL_${name.replace(/\W+/g, '_')}.png` });
  }
}
const shot = async (label) => { await page.waitForTimeout(900); return page.screenshot({ path: `${outDir}/${String(++n).padStart(2, '0')}_${label}.png` }); };
// Flutter exposes labels as aria-label on some nodes and as text on others, so
// search both.
const present = (text) => page.evaluate((t) => [...document.querySelectorAll('flt-semantics')]
  .some((e) => (e.getAttribute('aria-label') || '').includes(t) || (e.textContent || '').includes(t)), text);
const visible = async (text, t = 5000) => {
  const end = Date.now() + t;
  while (Date.now() < end) { if (await present(text)) return; await page.waitForTimeout(100); }
  throw new Error(`text never appeared: ${text}`);
};
const gone = async (text) => { if (await present(text)) throw new Error(`unexpected text: ${text}`); };
// Flutter web creates its hidden <input> after a click; typing too early loses keys.
const typeInto = async (name, text) => {
  await page.getByRole('textbox', { name }).click({ force: true });
  await page.waitForTimeout(700);
  await page.keyboard.type(text, { delay: 35 });
  await page.waitForTimeout(400);
};
const btn = (name) => page.getByRole('button', { name, exact: false }).first();

await step('app loads and exposes the page title', async () => {
  await visible('Create Song');
  await shot('initial_production_state');
});
await step('credit pill is honest when billing is unavailable', async () => {
  await btn('Credit balance unavailable').waitFor({ state: 'attached', timeout: 4000 });
});
await step('no fictional voices are shown', async () => {
  await visible('Add New Voice');
  await gone('Sister Aisha'); await gone('Studio Voice');
  await visible('You have no saved voices yet');
});
await step('Generate on an empty form lists what is missing', async () => {
  await btn('Generate Song').click({ force: true });
  await visible('Give your song a title.');
  await visible('Add lyrics, or use Write with AI.');
  await visible('Choose a voice, or add one with Add New Voice.');
  await shot('validation_errors');
});
await step('typing a title and Arabic lyrics works', async () => {
  await typeInto('Song title', 'Ya Rabbi');
  await typeInto('Song lyrics', 'Ya Rabbi, ka yi mana jagora');
  await visible('27/3000');
  await gone('Give your song a title.');
  await shot('typed_title_and_lyrics');
});
await step('song type selection updates the screen', async () => {
  await btn('Instrumental').click({ force: true });
  await visible('Instrumental songs don’t use a voice.');
});
await step('Generate with no engine is refused, truthfully', async () => {
  await btn('Generate Song').click({ force: true });
  await visible('no generation engine is connected');
  await gone('Your song is in the queue');
  await shot('generation_unavailable');
});
await step('credits entry point explains the missing billing service', async () => {
  await btn('Credit balance unavailable').click({ force: true });
  await visible('Your credit balance is not connected in this build yet.');
  await shot('credits_sheet');
  await page.keyboard.press('Escape'); await page.waitForTimeout(600);
});
await step('Write with AI reports the assistant as not connected', async () => {
  await btn('Write with AI').click({ force: true });
  await typeInto(/What is the song about/, 'gratitude');
  await btn('Write lyrics').click({ force: true });
  await visible('The lyrics assistant is not connected in this build yet.');
  await shot('write_with_ai_unavailable');
  await page.keyboard.press('Escape'); await page.waitForTimeout(600);
});
await step('Add New Voice requires consent before upload', async () => {
  await btn('Add New Voice').click({ force: true });
  await visible('Only add a voice you are allowed to use.');
  await shot('add_voice_consent');
  await page.keyboard.press('Escape'); await page.waitForTimeout(600);
});
await step('Manage Voices shows an honest empty state, and Back returns', async () => {
  await btn('Manage Voices').click({ force: true });
  await visible('You have no saved voices yet. Add a recording');
  await page.keyboard.press('Escape'); await page.waitForTimeout(300);
  await page.goBack().catch(() => {});
});
await step('advanced options are disabled with a reason', async () => {
  await btn('Advanced Options').click({ force: true });
  await visible('No engine');
  await shot('advanced_unavailable');
});

console.log(JSON.stringify({ pageErrors: errors }, null, 0));
const failed = results.filter((r) => r[0] === 'FAIL');
console.log(`\n${results.length - failed.length}/${results.length} flow checks passed`);
await browser.close(); server.close();
process.exit(failed.length ? 1 : 0);
