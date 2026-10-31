/**
 * HeartMuLa-via-WaveSpeedAI adapter tests against a LOCAL MOCK HTTP SERVER.
 *
 * What these prove: the adapter turns HTTP behaviour (status codes, the documented error codes, malformed
 * bodies, hangs, oversize bodies, hostile URLs) into the right outcomes for the worker, and that it never
 * pretends to sing in a recorded voice.
 *
 * What these do NOT prove: that WaveSpeedAI's service looks like the mock. The request and response shapes
 * are READ FROM THE DOCUMENTATION (see the header of src/provider/wavespeed.ts) and become evidence only
 * when scripts/heartmula-probe.mjs has been run with a real key.
 */
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { IncomingMessage, Server, ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { WaveSpeedHeartMulaProvider, withSectionTag } from '../src/provider/wavespeed.ts';
import { ProviderError } from '../src/provider/types.ts';
import { createProvider } from '../src/provider/index.ts';
import { testConfig } from './support/harness.ts';

interface Seen { method: string; url: string; headers: IncomingMessage['headers']; body: Buffer }
let server: Server;
let base = '';
let seen: Seen[] = [];
let handler: (req: IncomingMessage, res: ServerResponse, body: Buffer) => void;

beforeEach(async () => {
  seen = [];
  handler = (_req, res) => { res.statusCode = 500; res.end(); };
  server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c: Buffer) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      seen.push({ method: req.method ?? '', url: req.url ?? '', headers: req.headers, body });
      handler(req, res, body);
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterEach(async () => {
  server.closeAllConnections();
  await new Promise((r) => server.close(r));
});

const KEY = 'ws-test-SECRET-KEY-987654';
const make = (over: Partial<ConstructorParameters<typeof WaveSpeedHeartMulaProvider>[0]> = {}) =>
  new WaveSpeedHeartMulaProvider({ apiKey: KEY, baseUrl: base, ...over });
const signal = (ms = 2000) => AbortSignal.timeout(ms);
const json = (res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) => {
  res.writeHead(status, { 'content-type': 'application/json', ...headers });
  res.end(JSON.stringify(body));
};
const req = (over: object = {}) => ({ lyrics: '[Verse]\nLa ilaha illallah', language: 'english', stylePrompt: 'nasheed, calm', providerVoiceId: null, settings: {}, ...over });
const wrap = (data: object) => ({ code: 200, message: 'success', data });

async function outcome(p: Promise<unknown>): Promise<ProviderError> {
  try { await p; } catch (e) { assert.ok(e instanceof ProviderError, `expected ProviderError, got ${e}`); return e; }
  throw new assert.AssertionError({ message: 'expected a ProviderError, but the call succeeded' });
}

describe('capabilities never claim more than is documented or configured', () => {
  it('English only, no personal voice, the documented price; Hausa/Arabic absent by default', () => {
    const c = make().capabilities();
    assert.equal(c.engineName, 'HeartMuLa');
    assert.deepEqual(c.documentedLanguages, ['english']);
    assert.deepEqual(c.languages, ['english']);
    assert.equal(c.voiceConditioning, false);
    assert.equal(c.voiceSampleSeconds, null);
    assert.deepEqual(c.songTypes, ['full_song']);
    assert.equal(c.estimatedSongCostMicros, 100_000);
    assert.equal(c.estimatedEnrollCostMicros, null);
  });

  it('experimental languages are allowed for evaluation but never become "documented"', () => {
    const c = make({ experimentalLanguages: ['hausa', 'arabic'] }).capabilities();
    assert.deepEqual(c.languages.sort(), ['arabic', 'english', 'hausa']);
    assert.deepEqual(c.documentedLanguages, ['english']);
    assert.equal(c.voiceConditioning, false, 'a language list never turns on voice cloning');
  });
});

describe('voices are refused, never ignored', () => {
  it('enrolment is a terminal "not supported" and nothing is sent', async () => {
    const e = await outcome(make().enrollVoice());
    assert.equal(e.code, 'voice_not_supported');
    assert.equal(e.outcome, 'terminal');
    assert.equal(seen.length, 0);
  });

  it('a song that names an enrolled voice is refused instead of being sung in a stock voice', async () => {
    const e = await outcome(make().submitSong(req({ providerVoiceId: 'v-1' }), signal()));
    assert.equal(e.code, 'voice_not_supported');
    assert.equal(e.outcome, 'terminal');
    assert.equal(seen.length, 0, 'no task was created, so nothing can be billed');
  });

  it('deletion is reported as unsupported — not pretended', async () => {
    assert.equal(await make().deleteVoice(), 'unsupported');
    assert.equal(seen.length, 0);
  });
});

describe('withSectionTag', () => {
  it('puts untagged lyrics under [verse], leaves tagged lyrics exactly as written, normalises line endings', () => {
    assert.equal(withSectionTag('Line one\r\nLine two\r\n'), '[verse]\nLine one\nLine two');
    assert.equal(withSectionTag('[Chorus]\nAlhamdulillah\n\n[Verse]\nMorning'), '[Chorus]\nAlhamdulillah\n\n[Verse]\nMorning');
    assert.equal(withSectionTag('[intro-short]\n[Verse]\nA'), '[intro-short]\n[Verse]\nA');
  });
});

describe('submitSong', () => {
  it('sends bearer auth, JSON, lyrics and tags to the documented path; returns the prediction id', async () => {
    handler = (_q, res) => json(res, 200, wrap({ id: 'pred-1', status: 'created', model: 'wavespeed-ai/heartmula/generate-music' }));
    const out = await make().submitSong(req(), signal());
    assert.deepEqual(out, { providerTaskId: 'pred-1' });
    const s = seen[0]!;
    assert.equal(s.method, 'POST');
    assert.equal(s.url, '/api/v3/wavespeed-ai/heartmula/generate-music');
    assert.equal(s.headers.authorization, `Bearer ${KEY}`);
    assert.match(String(s.headers['content-type']), /application\/json/);
    assert.deepEqual(JSON.parse(s.body.toString()), { lyrics: '[Verse]\nLa ilaha illallah', tags: 'nasheed, calm' });
  });

  it('accepts a reply without the {code, message, data} envelope', async () => {
    handler = (_q, res) => json(res, 200, { id: 'flat-1', status: 'created' });
    assert.deepEqual(await make().submitSong(req(), signal()), { providerTaskId: 'flat-1' });
  });

  it('adds [verse] to untagged lyrics and omits tags when there is no style', async () => {
    handler = (_q, res) => json(res, 200, wrap({ id: 'p' }));
    await make().submitSong(req({ lyrics: 'Plain words', stylePrompt: '' }), signal());
    assert.deepEqual(JSON.parse(seen[0]!.body.toString()), { lyrics: '[verse]\nPlain words' });
  });

  const cases: Array<[string, number, unknown, Record<string, string>, Partial<ProviderError>]> = [
    ['401 → credentials invalid (terminal)', 401, { code: 401, message: 'Invalid API key' }, {}, { code: 'provider_credentials', outcome: 'terminal', credentialsInvalid: true }],
    ['403 → credentials invalid (terminal)', 403, {}, {}, { code: 'provider_credentials', outcome: 'terminal', credentialsInvalid: true }],
    ['402 → no balance (terminal)', 402, {}, {}, { code: 'provider_funds', outcome: 'terminal', providerFunds: true }],
    ['400 with code 1407 insufficient_credits → no balance (terminal, never retried)', 400, { code: 1407, message: 'insufficient_credits' }, {}, { code: 'provider_funds', outcome: 'terminal', providerFunds: true }],
    ['400 with code 1200 content moderation → refused text (terminal)', 400, { code: 1200, message: 'sensitive' }, {}, { code: 'provider_content_rejected', outcome: 'terminal' }],
    ['400 other → rejected (terminal)', 400, { code: 1401, message: 'Invalid Parameter' }, {}, { code: 'provider_rejected', outcome: 'terminal' }],
    ['429 → not started, honours Retry-After', 429, {}, { 'retry-after': '7' }, { code: 'provider_rate_limited', outcome: 'not_started', retryAfterMs: 7000 }],
    ['500 on a write → outcome UNKNOWN (must not be retried: a task may exist)', 500, {}, {}, { code: 'provider_server_error', outcome: 'unknown' }],
    ['502 on a write → outcome UNKNOWN', 502, {}, {}, { code: 'provider_server_error', outcome: 'unknown' }],
    ['504 on a write → outcome UNKNOWN', 504, {}, {}, { code: 'provider_server_error', outcome: 'unknown' }],
  ];
  for (const [name, status, body, headers, expected] of cases) {
    it(name, async () => {
      handler = (_q, res) => json(res, status, body, headers);
      const e = await outcome(make().submitSong(req(), signal()));
      for (const [k, v] of Object.entries(expected)) assert.equal((e as unknown as Record<string, unknown>)[k], v, k);
    });
  }

  it('an error carried in a 2xx envelope is still an error (1407 → no balance)', async () => {
    handler = (_q, res) => json(res, 200, { code: 1407, message: 'insufficient_credits' });
    const e = await outcome(make().submitSong(req(), signal()));
    assert.equal(e.code, 'provider_funds');
    assert.equal(e.providerFunds, true);
  });

  it('a 2xx envelope error in the 5xxx range on a write is outcome UNKNOWN', async () => {
    handler = (_q, res) => json(res, 200, { code: 5003, message: 'unavailable' });
    assert.equal((await outcome(make().submitSong(req(), signal()))).outcome, 'unknown');
  });

  it('a 2xx with an unreadable body is outcome UNKNOWN (the task may exist)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end('<html>maintenance</html>'); };
    assert.equal((await outcome(make().submitSong(req(), signal()))).outcome, 'unknown');
  });

  it('a 2xx with no prediction id, an array, or null is outcome UNKNOWN, not a guessed id', async () => {
    for (const body of [wrap({ status: 'created' }), [], null, {}]) {
      handler = (_q, res) => json(res, 200, body);
      assert.equal((await outcome(make().submitSong(req(), signal()))).outcome, 'unknown', JSON.stringify(body));
    }
  });

  it('a hung server becomes a timeout with unknown outcome', async () => {
    handler = () => { /* never answers */ };
    const e = await outcome(make().submitSong(req(), AbortSignal.timeout(150)));
    assert.equal(e.code, 'timeout');
    assert.equal(e.outcome, 'unknown');
  });

  it('a refused connection is "not started" (nothing left the machine)', async () => {
    const free = createServer();
    await new Promise<void>((r) => free.listen(0, '127.0.0.1', r));
    const port = (free.address() as AddressInfo).port;
    await new Promise((r) => free.close(r)); // nothing listens on this port any more
    const dead = new WaveSpeedHeartMulaProvider({ apiKey: KEY, baseUrl: `http://127.0.0.1:${port}` });
    const e = await outcome(dead.submitSong(req(), signal()));
    assert.equal(e.code, 'provider_unreachable');
    assert.equal(e.outcome, 'not_started');
  });

  it('an enormous reply is cut off rather than buffered (unknown outcome for a write)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(`{"id":"x","pad":"${'a'.repeat(2_000_000)}"}`); };
    assert.equal((await outcome(make().submitSong(req(), signal(5000)))).outcome, 'unknown');
  });

  it('the API key is never part of any error message', async () => {
    for (const status of [401, 402, 429, 400, 500]) {
      handler = (_q, res) => json(res, status, { code: status, message: `echo ${KEY}` });
      const e = await outcome(make().submitSong(req(), signal()));
      assert.ok(!e.message.includes(KEY) && !JSON.stringify(e).includes(KEY));
    }
  });
});

describe('pollSong', () => {
  const poll = (body: unknown, status = 200) => { handler = (_q, res) => json(res, status, body); return make().pollSong('pred 1/x', signal()); };

  it('queries the encoded prediction id with auth', async () => {
    await poll(wrap({ id: 'p', status: 'processing' }));
    assert.equal(seen[0]!.method, 'GET');
    assert.equal(seen[0]!.url, '/api/v3/predictions/pred%201%2Fx/result');
    assert.equal(seen[0]!.headers.authorization, `Bearer ${KEY}`);
  });

  it('created, processing and an unknown status all mean "keep waiting" — never success', async () => {
    for (const status of ['created', 'processing', 'queued', 'something-new', 'COMPLETED-MAYBE']) {
      assert.deepEqual(await poll(wrap({ status })), { state: 'running' }, status);
    }
  });

  it('completed returns the first output URL; duration stays unknown (inference time is not song length)', async () => {
    const r = await poll(wrap({ status: 'completed', outputs: ['https://cdn.example.com/a.mp3', 'https://cdn.example.com/b.mp3'], timings: { inference: 41000 } }));
    assert.deepEqual(r, { state: 'succeeded', audioUrl: 'https://cdn.example.com/a.mp3', durationMs: null, costMicros: null });
  });

  it('completed with an object output reads its url; without the envelope also works', async () => {
    assert.equal(((await poll({ status: 'completed', outputs: [{ url: 'https://cdn.example.com/c.mp3' }] })) as { audioUrl: string }).audioUrl, 'https://cdn.example.com/c.mp3');
  });

  it('completed with no outputs gives audioUrl null (the worker will fail it as empty)', async () => {
    for (const outputs of [[], undefined, [''], [{}]]) {
      const r = await poll(wrap({ status: 'completed', ...(outputs ? { outputs } : {}) }));
      assert.deepEqual(r, { state: 'succeeded', audioUrl: null, durationMs: null, costMicros: null });
    }
  });

  it('failed, cancelled, timeout and deleted are failures, carrying the provider code and message', async () => {
    for (const status of ['failed', 'cancelled', 'timeout', 'deleted']) {
      const r = await poll(wrap({ status, code: 1403, error: 'Task Execution Failed' }));
      assert.deepEqual(r, { state: 'failed', code: '1403', message: 'Task Execution Failed' }, status);
    }
    assert.deepEqual(await poll(wrap({ status: 'timeout' })), { state: 'failed', code: 'timeout', message: 'timeout' });
  });

  it('a missing status is an error that is safe to ask again', async () => {
    const e = await outcome(poll(wrap({ id: 'p' })));
    assert.equal(e.outcome, 'not_started');
  });

  it('429/5xx on a read are safe to retry; 401 flags credentials; 404 is terminal', async () => {
    assert.equal((await outcome(poll({}, 429))).outcome, 'not_started');
    assert.equal((await outcome(poll({}, 503))).outcome, 'not_started');
    const auth = await outcome(poll({}, 401));
    assert.equal(auth.credentialsInvalid, true);
    assert.equal((await outcome(poll({}, 404))).outcome, 'terminal');
  });
});

describe('downloadAudio', () => {
  it('downloads from the API host over a local http base (tests only)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-type': 'audio/mpeg' }); res.end(Buffer.from('ID3-audio-bytes')); };
    const out = await make().downloadAudio(`${base}/files/a.mp3`, signal());
    assert.equal(out.toString(), 'ID3-audio-bytes');
    assert.equal(seen[0]!.headers.authorization, undefined, 'the API key is not sent to the download URL');
  });

  it('rejects non-https URLs from a real (https) deployment, IP literals, localhost, and bad URLs', async () => {
    const real = new WaveSpeedHeartMulaProvider({ apiKey: KEY, baseUrl: 'https://api.wavespeed.ai' });
    for (const url of ['http://cdn.example.com/a.mp3', 'https://127.0.0.1/a.mp3', 'https://localhost/a.mp3', 'https://[::1]/a.mp3', 'https://x.internal/a.mp3', 'not a url', 'file:///etc/passwd']) {
      const e = await outcome(real.downloadAudio(url, signal()));
      assert.equal(e.code, 'bad_audio_url', url);
      assert.equal(e.outcome, 'terminal');
    }
  });

  it('enforces an allow-list of download hosts when configured', async () => {
    const p = new WaveSpeedHeartMulaProvider({ apiKey: KEY, baseUrl: 'https://api.wavespeed.ai', audioHosts: ['wavespeed.ai'] });
    assert.equal((await outcome(p.downloadAudio('https://evil.example.com/a.mp3', signal()))).code, 'bad_audio_url');
  });

  it('non-2xx is an error; 5xx is safe to retry; 404 is terminal; an oversize body is refused', async () => {
    handler = (_q, res) => { res.statusCode = 503; res.end(); };
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).outcome, 'not_started');
    handler = (_q, res) => { res.statusCode = 404; res.end(); };
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).outcome, 'terminal');
    handler = (_q, res) => { res.writeHead(200, { 'content-length': String(61 * 1024 * 1024) }); res.end('x'); };
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).code, 'audio_too_large');
  });
});

describe('configuration and factory', () => {
  it('PROVIDER=heartmula builds this adapter with the configured price, hosts and experimental languages', () => {
    const p = createProvider(testConfig({
      provider: 'heartmula', wavespeedApiKey: 'k', experimentalLanguages: ['hausa'],
      wavespeed: { songCostMicros: 123_000, audioHosts: ['cdn.example.com'] },
    }));
    assert.equal(p.name, 'heartmula');
    assert.equal(p.configured, true);
    const c = p.capabilities();
    assert.equal(c.estimatedSongCostMicros, 123_000);
    assert.deepEqual(c.languages.sort(), ['english', 'hausa']);
    assert.equal(c.voiceConditioning, false);
  });
});
