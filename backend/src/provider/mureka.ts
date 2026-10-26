import type { MusicProvider, ProviderCapabilities, SongPoll, SongRequest } from './types.ts';
import { ProviderError } from './types.ts';

/**
 * Mureka adapter.
 *
 * CONTRACT STATUS: NOT VERIFIED AGAINST THE LIVE API. The build environment could not reach
 * api.mureka.ai or platform.mureka.ai (blocked by network policy), so nothing here has been run
 * against Mureka. What is known, and from where (docs/PROVIDER_EVALUATION.md):
 *   - Base URL `https://api.mureka.ai`, bearer auth, async generation; song generation at
 *     `POST /v1/song/generate` and polling at `GET /v1/song/query/{task_id}` (official docs, via search).
 *   - `vocal_id` and `prompt` are request parameters (official changelog).
 *   - A "Vocal cloning" operation exists, but its path and fields could NOT be retrieved.
 * Everything else below (request field names `lyrics`/`model`, response fields `id`/`status`/`choices[].url`,
 * the status vocabulary) is from memory of the 2025 documentation and must be confirmed with
 * `scripts/mureka-probe.mjs` before any real use.
 *
 * Because of that the adapter FAILS CLOSED: enrollment is refused until `vocalClonePath` is set,
 * unknown response shapes are errors (never guessed), and nothing is reported as supported that the
 * operator has not configured.
 */
export interface MurekaOptions {
  apiKey: string;
  baseUrl: string;
  model: string;
  vocalClonePath: string | null;
  songCostMicros: number;
  enrollCostMicros: number;
  /** Extra hosts audio may be downloaded from (besides the API host). Empty = any public https host. */
  audioHosts: string[];
  /** Languages declared supported though not documented. For evaluation runs only. */
  experimentalLanguages: string[];
  fetchImpl?: typeof fetch;
}

const MAX_AUDIO_BYTES = 60 * 1024 * 1024;
const MAX_JSON_BYTES = 1024 * 1024;
const SUCCESS = new Set(['succeeded', 'success', 'completed']);
const FAILURE = new Set(['failed', 'timeouted', 'timed_out', 'cancelled', 'canceled', 'error']);
const RUNNING = new Set(['preparing', 'queued', 'running', 'streaming', 'pending', 'processing']);

type Json = Record<string, unknown>;

export class MurekaProvider implements MusicProvider {
  readonly name = 'mureka';
  readonly configured = true;
  private readonly o: MurekaOptions;
  private readonly fetchFn: typeof fetch;

  constructor(options: Partial<MurekaOptions> & { apiKey: string; baseUrl: string }) {
    this.o = {
      model: 'auto', vocalClonePath: null, songCostMicros: 45_000, enrollCostMicros: 5_000_000,
      audioHosts: [], experimentalLanguages: [], ...options,
    };
    this.fetchFn = options.fetchImpl ?? fetch;
  }

  capabilities(): ProviderCapabilities {
    const documented = ['english']; // Mureka's documented vocal languages; only English maps to a DeenVoice language.
    return {
      engineName: 'Mureka',
      songTypes: ['full_song'],
      documentedLanguages: documented,
      languages: [...new Set([...documented, ...this.o.experimentalLanguages])],
      voiceConditioning: this.o.vocalClonePath !== null,
      advancedOptionIds: [],
      voiceSampleSeconds: { min: 5, max: 15 },
      estimatedSongCostMicros: this.o.songCostMicros,
      estimatedEnrollCostMicros: this.o.enrollCostMicros,
    };
  }

  // ------------------------------------------------------------------ voice

  async enrollVoice(input: { audio: Buffer; mime: string; fileName: string }, signal: AbortSignal) {
    if (!this.o.vocalClonePath) {
      throw new ProviderError('provider_contract_unverified',
        'Mureka vocal-cloning is not configured: set MUREKA_VOCAL_CLONE_PATH from the official API reference (see docs/PROVIDER_EVALUATION.md).',
        { outcome: 'terminal' });
    }
    // UNVERIFIED: multipart field names. The upload operation documents a 5-15 s `voice` sample.
    const form = new FormData();
    form.set('purpose', 'voice');
    form.set('file', new Blob([new Uint8Array(input.audio)], { type: input.mime }), input.fileName);
    const body = await this.request('POST', this.o.vocalClonePath, { body: form }, signal, 'write');
    const id = pickString(body, ['vocal_id', 'id']);
    if (!id) throw badShape('vocal cloning response had no vocal_id/id', 'unknown');
    return { providerVoiceId: id, costMicros: this.o.enrollCostMicros };
  }

  /** The researched documentation shows no self-service deletion API for a Vocal ID, so say so. */
  async deleteVoice(): Promise<'unsupported'> {
    return 'unsupported';
  }

  // ------------------------------------------------------------------- song

  async submitSong(req: SongRequest, signal: AbortSignal) {
    const payload: Json = { lyrics: req.lyrics, model: this.o.model };
    if (req.stylePrompt) payload['prompt'] = req.stylePrompt;
    if (req.providerVoiceId) payload['vocal_id'] = req.providerVoiceId;
    const body = await this.request('POST', '/v1/song/generate', { json: payload }, signal, 'write');
    const id = pickString(body, ['id', 'task_id']);
    if (!id) throw badShape('generate response had no task id', 'unknown');
    return { providerTaskId: id };
  }

  async pollSong(taskId: string, signal: AbortSignal): Promise<SongPoll> {
    const body = await this.request('GET', `/v1/song/query/${encodeURIComponent(taskId)}`, {}, signal, 'read');
    const status = pickString(body, ['status'])?.toLowerCase();
    if (!status) throw badShape('query response had no status', 'not_started');
    if (RUNNING.has(status)) return { state: 'running' };
    if (FAILURE.has(status)) {
      return { state: 'failed', code: status, message: pickString(body, ['failed_reason', 'message', 'error']) ?? status };
    }
    if (!SUCCESS.has(status)) {
      // An unknown status is not guessed at. The job deadline bounds how long we keep asking.
      return { state: 'running' };
    }
    const choices = Array.isArray(body['choices']) ? (body['choices'] as unknown[]) : [];
    const first = (choices[0] ?? null) as Json | null;
    const url = first ? pickString(first, ['url', 'mp3_url', 'flac_url']) : null;
    const duration = first && typeof first['duration'] === 'number' ? Math.round(first['duration'] as number) : null;
    return { state: 'succeeded', audioUrl: url, durationMs: duration, costMicros: null };
  }

  async downloadAudio(audioUrl: string, signal: AbortSignal): Promise<Buffer> {
    const url = this.checkAudioUrl(audioUrl);
    let res: Response;
    try {
      res = await this.fetchFn(url, { signal, redirect: 'follow' });
    } catch (err) {
      throw networkError(err, 'read');
    }
    if (!res.ok) throw this.httpError(res.status, res.headers, 'read');
    const declared = Number(res.headers.get('content-length') ?? 0);
    if (declared > MAX_AUDIO_BYTES) throw new ProviderError('audio_too_large', 'Result is too large.', { outcome: 'terminal' });
    return readLimited(res, MAX_AUDIO_BYTES, 'terminal');
  }

  // ---------------------------------------------------------------- internals

  /** https only, no IP literals or localhost, optional host allow-list. The URL comes from the provider's response. */
  private checkAudioUrl(raw: string): string {
    let u: URL;
    try { u = new URL(raw); } catch { throw new ProviderError('bad_audio_url', 'Result URL is not valid.', { outcome: 'terminal' }); }
    const host = u.hostname.toLowerCase();
    const ipLiteral = /^\d+\.\d+\.\d+\.\d+$/.test(host) || host.includes(':');
    const local = host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal');
    const apiHost = new URL(this.o.baseUrl).hostname.toLowerCase();
    const allowed = this.o.audioHosts.length ? this.o.audioHosts.some((h) => host === h || host.endsWith(`.${h}`)) : true;
    const insecureOk = this.o.baseUrl.startsWith('http://') && host === apiHost; // local test servers only
    if ((u.protocol !== 'https:' && !insecureOk) || ((ipLiteral || local) && !insecureOk) || !allowed) {
      throw new ProviderError('bad_audio_url', 'Result URL is not an allowed download location.', { outcome: 'terminal' });
    }
    return u.toString();
  }

  private async request(
    method: 'GET' | 'POST', path: string, init: { json?: Json; body?: FormData }, signal: AbortSignal, kind: 'read' | 'write',
  ): Promise<Json> {
    const headers: Record<string, string> = { Authorization: `Bearer ${this.o.apiKey}`, Accept: 'application/json' };
    let body: string | FormData | undefined;
    if (init.json) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(init.json); }
    else if (init.body) body = init.body;

    let res: Response;
    try {
      res = await this.fetchFn(new URL(path, this.o.baseUrl), { method, headers, ...(body !== undefined ? { body } : {}), signal });
    } catch (err) {
      throw networkError(err, kind);
    }
    if (!res.ok) throw this.httpError(res.status, res.headers, kind);

    // Read first so a size error is reported as such; only the parse failure is a "bad shape".
    // An oversized 2xx to a write may still mean work started, so it is unknown there.
    const raw = await readLimited(res, MAX_JSON_BYTES, kind === 'write' ? 'unknown' : 'terminal');
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw.toString('utf8'));
    } catch {
      // A 2xx with a body we cannot read: for a write, the work may have started.
      throw badShape('response was not valid JSON', kind === 'write' ? 'unknown' : 'not_started');
    }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw badShape('response was not a JSON object', kind === 'write' ? 'unknown' : 'not_started');
    }
    return parsed as Json;
  }

  private httpError(status: number, headers: Headers, kind: 'read' | 'write'): ProviderError {
    const retryAfter = Number(headers.get('retry-after'));
    const retryAfterMs = Number.isFinite(retryAfter) && retryAfter > 0 ? retryAfter * 1000 : undefined;
    const base = { httpStatus: status, ...(retryAfterMs !== undefined ? { retryAfterMs } : {}) };
    if (status === 401 || status === 403) {
      return new ProviderError('provider_credentials', 'The provider rejected our credentials.', { ...base, outcome: 'terminal', credentialsInvalid: true });
    }
    if (status === 402) {
      return new ProviderError('provider_funds', 'The provider account has no balance.', { ...base, outcome: 'terminal', providerFunds: true });
    }
    if (status === 429) {
      // Rate or concurrency limit: the request was refused before any work started.
      return new ProviderError('provider_rate_limited', 'The provider is rate limiting us.', { ...base, outcome: 'not_started' });
    }
    if (status >= 400 && status < 500) {
      return new ProviderError('provider_rejected', `The provider rejected the request (${status}).`, { ...base, outcome: 'terminal' });
    }
    // 5xx: for a write we cannot know whether the work began; for a read, asking again is harmless.
    return new ProviderError('provider_server_error', `The provider failed (${status}).`, { ...base, outcome: kind === 'write' ? 'unknown' : 'not_started' });
  }
}

function pickString(obj: Json, keys: string[]): string | null {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.length > 0) return v;
    if (typeof v === 'number') return String(v);
  }
  return null;
}

const badShape = (what: string, outcome: 'unknown' | 'not_started') =>
  new ProviderError('provider_bad_response', `Unexpected provider response: ${what}.`, { outcome });

function networkError(err: unknown, kind: 'read' | 'write'): ProviderError {
  const e = err as { name?: string; cause?: { code?: string; errors?: Array<{ code?: string }> }; code?: string };
  const codes = [e.code, e.cause?.code, ...(e.cause?.errors ?? []).map((x) => x.code)].filter(Boolean) as string[];
  // The request never left the machine: certainly no work started.
  const neverSent = ['ECONNREFUSED', 'ENOTFOUND', 'EAI_AGAIN', 'ENETUNREACH', 'EHOSTUNREACH'];
  if (codes.length > 0 && codes.every((c) => neverSent.includes(c))) {
    return new ProviderError('provider_unreachable', 'Could not reach the provider.', { outcome: 'not_started' });
  }
  const aborted = e.name === 'AbortError' || e.name === 'TimeoutError';
  return new ProviderError(aborted ? 'timeout' : 'provider_network_error', 'The connection to the provider failed.', {
    outcome: kind === 'write' ? 'unknown' : 'not_started',
  });
}

async function readLimited(res: Response, max: number, overflow: 'unknown' | 'terminal'): Promise<Buffer> {
  const reader = res.body?.getReader();
  if (!reader) return Buffer.alloc(0);
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > max) {
      await reader.cancel();
      throw new ProviderError('response_too_large', 'The provider response was too large.', { outcome: overflow });
    }
    chunks.push(Buffer.from(value));
  }
  return Buffer.concat(chunks);
}
