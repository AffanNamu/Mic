import { ProviderError } from './types.ts';

/** Helpers shared by the HTTP provider adapters. Each one exists because of a way a provider's reply can hurt us. */

export type Json = Record<string, unknown>;

export const MAX_AUDIO_BYTES = 60 * 1024 * 1024;
export const MAX_JSON_BYTES = 1024 * 1024;
const MAX_ERROR_BYTES = 4096;

export function pickString(obj: Json, keys: string[]): string | null {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === 'string' && v.length > 0) return v;
    if (typeof v === 'number') return String(v);
  }
  return null;
}

export const badShape = (what: string, outcome: 'unknown' | 'not_started') =>
  new ProviderError('provider_bad_response', `Unexpected provider response: ${what}.`, { outcome });

export function networkError(err: unknown, kind: 'read' | 'write'): ProviderError {
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

export async function readLimited(res: Response, max: number, overflow: 'unknown' | 'terminal'): Promise<Buffer> {
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

/** The provider's own error body as an object, bounded. Used only to classify a failure; never shown or logged. */
export async function readErrorJson(res: Response): Promise<Json | null> {
  try {
    const parsed: unknown = JSON.parse((await readLimited(res, MAX_ERROR_BYTES, 'terminal')).toString('utf8'));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as Json) : null;
  } catch {
    return null; // an unreadable error body is simply not classified
  }
}

/** The `Retry-After` header in milliseconds, when it is a positive number of seconds. */
export function retryAfterMs(headers: Headers): number | undefined {
  const s = Number(headers.get('retry-after'));
  return Number.isFinite(s) && s > 0 ? s * 1000 : undefined;
}

/**
 * The URL comes from the provider's response, so: https only, no IP literals or localhost, and an optional
 * host allow-list. A plain-http API host is allowed to serve its own audio, for local test servers only.
 */
export function checkAudioUrl(raw: string, baseUrl: string, audioHosts: string[]): string {
  let u: URL;
  try { u = new URL(raw); } catch { throw new ProviderError('bad_audio_url', 'Result URL is not valid.', { outcome: 'terminal' }); }
  const host = u.hostname.toLowerCase();
  const ipLiteral = /^\d+\.\d+\.\d+\.\d+$/.test(host) || host.includes(':');
  const local = host === 'localhost' || host.endsWith('.local') || host.endsWith('.internal');
  const apiHost = new URL(baseUrl).hostname.toLowerCase();
  const allowed = audioHosts.length ? audioHosts.some((h) => host === h || host.endsWith(`.${h}`)) : true;
  const insecureOk = baseUrl.startsWith('http://') && host === apiHost;
  if ((u.protocol !== 'https:' && !insecureOk) || ((ipLiteral || local) && !insecureOk) || !allowed) {
    throw new ProviderError('bad_audio_url', 'Result URL is not an allowed download location.', { outcome: 'terminal' });
  }
  return u.toString();
}
