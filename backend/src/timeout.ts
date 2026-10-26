import { ProviderError } from './provider/types.ts';

/**
 * Runs `fn` with an abort signal and a hard deadline. The deadline is enforced
 * even if `fn` ignores the signal. A timeout is reported as `unknown` outcome:
 * the request may have reached the provider.
 */
export async function withTimeout<T>(ms: number, fn: (signal: AbortSignal) => Promise<T>): Promise<T> {
  const controller = new AbortController();
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new ProviderError('timeout', `The provider did not respond within ${Math.round(ms / 1000)} s.`, { outcome: 'unknown' }));
    }, ms);
  });
  try {
    return await Promise.race([fn(controller.signal), timeout]);
  } finally {
    clearTimeout(timer);
  }
}
