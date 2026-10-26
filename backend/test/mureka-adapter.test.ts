/**
 * Adapter tests against a LOCAL MOCK HTTP SERVER.
 *
 * What these prove: the adapter turns HTTP behaviour (status codes, malformed bodies, hangs,
 * oversize bodies, hostile URLs) into the right outcomes for the worker.
 *
 * What these do NOT prove: that Mureka's real API looks like the mock. The request/response field
 * names here are the adapter's ASSUMPTIONS (see the header of src/provider/mureka.ts). They become
 * evidence only when scripts/mureka-probe.mjs confirms them against the live API.
 */
import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import type { IncomingMessage, Server, ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { MurekaProvider } from '../src/provider/mureka.ts';
import { ProviderError } from '../src/provider/types.ts';
import { wav } from './support/wav.ts';

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

const KEY = 'sk-test-SECRET-KEY-123456';
const make = (over: Partial<ConstructorParameters<typeof MurekaProvider>[0]> = {}) =>
  new MurekaProvider({ apiKey: KEY, baseUrl: base, ...over });
const signal = (ms = 2000) => AbortSignal.timeout(ms);
const json = (res: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}) => {
  res.writeHead(status, { 'content-type': 'application/json', ...headers });
  res.end(JSON.stringify(body));
};
const req = (over: object = {}) => ({ lyrics: 'La ilaha illallah', language: 'english', stylePrompt: 'English nasheed', providerVoiceId: null, settings: {}, ...over });

async function outcome(p: Promise<unknown>): Promise<ProviderError> {
  try { await p; } catch (e) { assert.ok(e instanceof ProviderError, `expected ProviderError, got ${e}`); return e; }
  throw new assert.AssertionError({ message: 'expected a ProviderError, but the call succeeded' });
}

describe('capabilities never claim more than is documented or configured', () => {
  it('English only; no voice singing until a clone endpoint is configured; Hausa/Arabic absent by default', () => {
    const c = make().capabilities();
    assert.deepEqual(c.documentedLanguages, ['english']);
    assert.deepEqual(c.languages, ['english']);
    assert.equal(c.voiceConditioning, false);
    assert.deepEqual(c.songTypes, ['full_song']);
    assert.equal(c.engineName, 'Mureka');
  });

  it('experimental languages are allowed for evaluation but never become "documented"', () => {
    const c = make({ experimentalLanguages: ['hausa', 'arabic'], vocalClonePath: '/v1/x' }).capabilities();
    assert.deepEqual(c.languages.sort(), ['arabic', 'english', 'hausa']);
    assert.deepEqual(c.documentedLanguages, ['english']);
    assert.equal(c.voiceConditioning, true);
  });
});

describe('submitSong', () => {
  it('sends bearer auth, JSON, lyrics, style and the enrolled vocal id; returns the task id', async () => {
    handler = (_q, res) => json(res, 200, { id: 'task-77', status: 'preparing' });
    const out = await make().submitSong(req({ providerVoiceId: 'vocal-9' }), signal());
    assert.deepEqual(out, { providerTaskId: 'task-77' });
    const s = seen[0]!;
    assert.equal(s.method, 'POST');
    assert.equal(s.url, '/v1/song/generate');
    assert.equal(s.headers.authorization, `Bearer ${KEY}`);
    assert.match(String(s.headers['content-type']), /application\/json/);
    assert.deepEqual(JSON.parse(s.body.toString()), {
      lyrics: 'La ilaha illallah', model: 'auto', prompt: 'English nasheed', vocal_id: 'vocal-9',
    });
  });

  it('omits vocal_id when there is no voice and prompt when there is no style', async () => {
    handler = (_q, res) => json(res, 200, { id: 't' });
    await make().submitSong(req({ stylePrompt: '' }), signal());
    assert.deepEqual(Object.keys(JSON.parse(seen[0]!.body.toString())).sort(), ['lyrics', 'model']);
  });

  const cases: Array<[string, number, Record<string, string>, Partial<ProviderError>]> = [
    ['401 → credentials invalid (terminal)', 401, {}, { code: 'provider_credentials', outcome: 'terminal', credentialsInvalid: true }],
    ['403 → credentials invalid (terminal)', 403, {}, { code: 'provider_credentials', outcome: 'terminal', credentialsInvalid: true }],
    ['402 → provider funds exhausted (terminal)', 402, {}, { code: 'provider_funds', outcome: 'terminal', providerFunds: true }],
    ['429 → not started, honours Retry-After', 429, { 'retry-after': '7' }, { code: 'provider_rate_limited', outcome: 'not_started', retryAfterMs: 7000 }],
    ['400 → rejected (terminal)', 400, {}, { code: 'provider_rejected', outcome: 'terminal' }],
    ['422 → rejected (terminal)', 422, {}, { code: 'provider_rejected', outcome: 'terminal' }],
    ['500 on a write → outcome UNKNOWN (must not be retried)', 500, {}, { code: 'provider_server_error', outcome: 'unknown' }],
    ['502 on a write → outcome UNKNOWN', 502, {}, { code: 'provider_server_error', outcome: 'unknown' }],
    ['503 on a write → outcome UNKNOWN', 503, {}, { code: 'provider_server_error', outcome: 'unknown' }],
  ];
  for (const [name, status, headers, expected] of cases) {
    it(name, async () => {
      handler = (_q, res) => json(res, status, { error: 'x' }, headers);
      const e = await outcome(make().submitSong(req(), signal()));
      for (const [k, v] of Object.entries(expected)) assert.equal((e as unknown as Record<string, unknown>)[k], v, k);
    });
  }

  it('a 2xx with an unreadable body is outcome UNKNOWN (the work may have started)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end('<html>maintenance</html>'); };
    const e = await outcome(make().submitSong(req(), signal()));
    assert.equal(e.code, 'provider_bad_response');
    assert.equal(e.outcome, 'unknown');
  });

  it('a 2xx with no task id, an array, or null is outcome UNKNOWN, not a guessed id', async () => {
    for (const body of [{}, { status: 'ok' }, [], null]) {
      handler = (_q, res) => json(res, 200, body);
      assert.equal((await outcome(make().submitSong(req(), signal()))).outcome, 'unknown');
    }
  });

  it('a hung server becomes a timeout with unknown outcome', async () => {
    handler = () => { /* never answer */ };
    const e = await outcome(make().submitSong(req(), AbortSignal.timeout(60)));
    assert.equal(e.code, 'timeout');
    assert.equal(e.outcome, 'unknown');
  });

  it('a refused connection is "not started" (nothing left the machine)', async () => {
    const free = createServer();
    await new Promise<void>((r) => free.listen(0, '127.0.0.1', r));
    const port = (free.address() as AddressInfo).port;
    await new Promise((r) => free.close(r)); // nothing listens on this port any more
    const dead = new MurekaProvider({ apiKey: KEY, baseUrl: `http://127.0.0.1:${port}` });
    const e = await outcome(dead.submitSong(req(), signal()));
    assert.equal(e.code, 'provider_unreachable');
    assert.equal(e.outcome, 'not_started');
  });

  it('an enormous response is cut off rather than buffered (unknown outcome for a write)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(Buffer.alloc(3 * 1024 * 1024, 0x20)); };
    const e = await outcome(make().submitSong(req(), signal(5000)));
    assert.equal(e.code, 'response_too_large');
    assert.equal(e.outcome, 'unknown');
  });

  it('the API key is never part of any error message', async () => {
    for (const status of [401, 402, 429, 400, 500]) {
      handler = (_q, res) => json(res, status, { error: `echo ${KEY}` });
      const e = await outcome(make().submitSong(req(), signal()));
      assert.ok(!e.message.includes(KEY) && !JSON.stringify(e).includes(KEY));
    }
  });
});

describe('pollSong', () => {
  const poll = (body: unknown, status = 200) => { handler = (_q, res) => json(res, status, body); return make().pollSong('task 1/x', signal()); };

  it('queries the encoded task id with auth', async () => {
    await poll({ status: 'running' });
    assert.equal(seen[0]!.method, 'GET');
    assert.equal(seen[0]!.url, '/v1/song/query/task%201%2Fx');
    assert.equal(seen[0]!.headers.authorization, `Bearer ${KEY}`);
  });

  it('maps in-progress statuses to running', async () => {
    for (const status of ['preparing', 'queued', 'running', 'streaming', 'PENDING']) {
      assert.deepEqual(await poll({ status }), { state: 'running' }, status);
    }
  });

  it('does not treat an UNKNOWN status as success — it keeps waiting until the deadline', async () => {
    assert.deepEqual(await poll({ status: 'frobnicated' }), { state: 'running' });
  });

  it('maps failure statuses to failed', async () => {
    for (const status of ['failed', 'timeouted', 'cancelled']) {
      const r = await poll({ status, failed_reason: 'bad lyrics' });
      assert.equal(r.state, 'failed');
    }
  });

  it('success returns the first result URL and duration', async () => {
    const r = await poll({ status: 'succeeded', choices: [{ url: 'https://cdn.example/a.mp3', duration: 183.4 }, { url: 'https://cdn.example/b.mp3' }] });
    assert.deepEqual(r, { state: 'succeeded', audioUrl: 'https://cdn.example/a.mp3', durationMs: 183, costMicros: null });
  });

  it('success with no choices or no url gives audioUrl null (the worker will fail it as empty)', async () => {
    assert.deepEqual(await poll({ status: 'succeeded' }), { state: 'succeeded', audioUrl: null, durationMs: null, costMicros: null });
    assert.equal(((await poll({ status: 'succeeded', choices: [{}] })) as { audioUrl: string | null }).audioUrl, null);
    assert.equal(((await poll({ status: 'succeeded', choices: [] })) as { audioUrl: string | null }).audioUrl, null);
  });

  it('a missing status is an error that is safe to ask again', async () => {
    const e = await outcome(poll({ nope: true }));
    assert.equal(e.code, 'provider_bad_response');
    assert.equal(e.outcome, 'not_started');
  });

  it('5xx on a read is safe to retry; 401 flags credentials; 404 is terminal', async () => {
    assert.equal((await outcome(poll({}, 503))).outcome, 'not_started');
    assert.equal((await outcome(poll({}, 401))).credentialsInvalid, true);
    assert.equal((await outcome(poll({}, 404))).outcome, 'terminal');
  });
});

describe('downloadAudio: the URL comes from the provider, so it is untrusted', () => {
  const serveAudio = (bytes: Buffer, status = 200) => {
    handler = (_q, res) => { res.writeHead(status, { 'content-type': 'audio/wav' }); res.end(bytes); };
  };

  it('downloads from the API host over a local http base (tests only)', async () => {
    const audio = wav(2);
    serveAudio(audio);
    const out = await make().downloadAudio(`${base}/files/a.wav`, signal());
    assert.deepEqual(out, audio);
    assert.equal(seen[0]!.headers.authorization, undefined, 'the API key must not be sent to the download URL');
  });

  it('rejects non-https URLs from a real (https) deployment, IP literals, localhost, and bad URLs', async () => {
    const prod = new MurekaProvider({ apiKey: KEY, baseUrl: 'https://api.mureka.ai' });
    for (const url of [
      'http://cdn.example/a.mp3', 'https://127.0.0.1/a.mp3', 'https://10.0.0.5/a.mp3', 'https://[::1]/a.mp3',
      'https://localhost/a.mp3', 'https://metadata.google.internal/x', 'https://printer.local/x', 'file:///etc/passwd', 'not a url',
    ]) {
      const e = await outcome(prod.downloadAudio(url, signal()));
      assert.equal(e.outcome, 'terminal', url);
      assert.match(e.code, /bad_audio_url/, url);
    }
    assert.equal(seen.length, 0, 'no request may be made for a rejected URL');
  });

  it('enforces an allow-list of download hosts when configured', async () => {
    const strict = new MurekaProvider({ apiKey: KEY, baseUrl: 'https://api.mureka.ai', audioHosts: ['cdn.mureka.ai'] });
    assert.equal((await outcome(strict.downloadAudio('https://evil.example/a.mp3', signal()))).code, 'bad_audio_url');
    assert.equal((await outcome(strict.downloadAudio('https://cdn.mureka.ai.evil.example/a.mp3', signal()))).code, 'bad_audio_url');
  });

  it('non-2xx is an error; 5xx is safe to retry; 404 is terminal', async () => {
    serveAudio(Buffer.from('no'), 503);
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).outcome, 'not_started');
    serveAudio(Buffer.from('no'), 404);
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).outcome, 'terminal');
  });

  it('an empty 200 body comes back empty so the worker can reject it (the adapter does not call it a song)', async () => {
    serveAudio(Buffer.alloc(0));
    assert.equal((await make().downloadAudio(`${base}/a`, signal())).length, 0);
  });

  it('refuses a body larger than the cap (declared or streamed)', async () => {
    handler = (_q, res) => { res.writeHead(200, { 'content-length': String(100 * 1024 * 1024) }); res.end(Buffer.alloc(10)); };
    assert.equal((await outcome(make().downloadAudio(`${base}/a`, signal()))).code, 'audio_too_large');
  });
});

describe('voice enrollment', () => {
  it('fails closed with a clear reason while the clone endpoint is unverified/unset — and sends nothing', async () => {
    const e = await outcome(make().enrollVoice({ audio: wav(10), mime: 'audio/wav', fileName: 'v' }, signal()));
    assert.equal(e.code, 'provider_contract_unverified');
    assert.equal(e.outcome, 'terminal');
    assert.equal(seen.length, 0);
  });

  it('when an operator configures the path, uploads multipart with auth and returns the id (ASSUMED contract)', async () => {
    handler = (_q, res) => json(res, 200, { vocal_id: 'vocal-abc' });
    const p = make({ vocalClonePath: '/v1/vocal/clone' });
    const out = await p.enrollVoice({ audio: wav(10), mime: 'audio/wav', fileName: 'voice-1' }, signal());
    assert.deepEqual(out, { providerVoiceId: 'vocal-abc', costMicros: 5_000_000 });
    const s = seen[0]!;
    assert.equal(s.url, '/v1/vocal/clone');
    assert.match(String(s.headers['content-type']), /multipart\/form-data/);
    assert.equal(s.headers.authorization, `Bearer ${KEY}`);
    assert.ok(s.body.includes(wav(10).subarray(0, 12)), 'the audio is in the upload');
  });

  it('an enrollment response without an id is outcome UNKNOWN (it may have been billed)', async () => {
    handler = (_q, res) => json(res, 200, { ok: true });
    const e = await outcome(make({ vocalClonePath: '/v1/vocal/clone' }).enrollVoice({ audio: wav(10), mime: 'audio/wav', fileName: 'v' }, signal()));
    assert.equal(e.outcome, 'unknown');
  });

  it('deletion is reported as unsupported — not pretended', async () => {
    assert.equal(await make().deleteVoice(), 'unsupported');
    assert.equal(seen.length, 0);
  });
});
