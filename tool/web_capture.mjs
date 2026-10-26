// Serves a built Flutter web app and screenshots it at the reference size
// (426x923 CSS px at 2x = 852x1846), using the container's Chromium.
//
//   node tool/web_capture.mjs <web-build-dir> <out.png> [--wait-ms 6000]
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require('playwright');

const [dir, out] = process.argv.slice(2);
const waitMs = Number(process.argv[process.argv.indexOf('--wait-ms') + 1]) || 6000;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.png': 'image/png',
  '.webp': 'image/webp', '.ttf': 'font/ttf', '.otf': 'font/otf', '.css': 'text/css' };

const server = createServer(async (req, res) => {
  try {
    let p = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (p.endsWith('/')) p += 'index.html';
    const file = join(dir, p);
    await stat(file);
    res.writeHead(200, { 'content-type': types[extname(file)] ?? 'application/octet-stream' });
    res.end(await readFile(file));
  } catch { res.writeHead(404); res.end('not found'); }
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;

const browser = await chromium.launch({
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await (await browser.newContext({
  viewport: { width: 426, height: 923 }, deviceScaleFactor: 2,
})).newPage();
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.goto(url);
await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
await page.waitForTimeout(waitMs);
await page.screenshot({ path: out });
console.log(`saved ${out}`);
if (logs.length) console.log(logs.slice(0, 15).join('\n'));
await browser.close();
server.close();
