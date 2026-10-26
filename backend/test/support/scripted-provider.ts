import type { MusicProvider, ProviderCapabilities, SongPoll, SongRequest } from '../../src/provider/types.ts';
import { ProviderError } from '../../src/provider/types.ts';
import { wav } from './wav.ts';

/**
 * TEST DOUBLE. Not a music provider and never wired into the server.
 *
 * It exists so the backend's own behaviour (state machine, ledger, retries,
 * recovery, storage) can be tested deterministically, including failures a real
 * provider produces only rarely. Everything it returns is a synthetic sine tone.
 * Passing tests against it prove NOTHING about any real provider's output or
 * contract; real-provider acceptance is covered separately in docs/ACCEPTANCE.md.
 */
export class ScriptedProvider implements MusicProvider {
  readonly name = 'test-double';
  configured = true;

  readonly calls = { enroll: 0, submit: 0, poll: 0, download: 0, delete: 0 };
  readonly submitted: SongRequest[] = [];
  caps: Partial<ProviderCapabilities> = {};

  onEnroll: (n: number, signal: AbortSignal) => Promise<{ providerVoiceId: string; costMicros: number | null }> =
    async (n) => ({ providerVoiceId: `vocal-${n}`, costMicros: 5_000_000 });
  onDelete: () => Promise<'deleted' | 'requested' | 'unsupported'> = async () => 'unsupported';
  onSubmit: (req: SongRequest, n: number, signal: AbortSignal) => Promise<{ providerTaskId: string }> =
    async (_req, n) => ({ providerTaskId: `task-${n}` });
  onPoll: (taskId: string, n: number, signal: AbortSignal) => Promise<SongPoll> =
    async () => ({ state: 'succeeded', audioUrl: 'https://test-double.invalid/audio.wav', durationMs: 3000, costMicros: null });
  onDownload: (url: string, n: number, signal: AbortSignal) => Promise<Buffer> = async () => wav(3);

  capabilities(): ProviderCapabilities {
    return {
      engineName: 'Test double',
      songTypes: ['full_song', 'vocal_only', 'instrumental', 'nasheed_style'],
      languages: ['english', 'arabic'],
      documentedLanguages: ['english'],
      voiceConditioning: true,
      advancedOptionIds: [],
      voiceSampleSeconds: { min: 5, max: 15 },
      estimatedSongCostMicros: 45_000,
      estimatedEnrollCostMicros: 5_000_000,
      ...this.caps,
    };
  }

  enrollVoice(_input: { audio: Buffer; mime: string; fileName: string }, signal: AbortSignal) {
    return this.onEnroll(++this.calls.enroll, signal);
  }
  deleteVoice(_id: string, _signal: AbortSignal) {
    this.calls.delete++;
    return this.onDelete();
  }
  submitSong(req: SongRequest, signal: AbortSignal) {
    this.submitted.push(req);
    return this.onSubmit(req, ++this.calls.submit, signal);
  }
  pollSong(taskId: string, signal: AbortSignal) {
    return this.onPoll(taskId, ++this.calls.poll, signal);
  }
  downloadAudio(url: string, signal: AbortSignal) {
    return this.onDownload(url, ++this.calls.download, signal);
  }
}

/** Makes `fn` fail with `error` for its first `times` calls, then behave normally. */
export function failFirst<A extends unknown[], R>(times: number, error: () => Error, fn: (...a: A) => Promise<R>) {
  let seen = 0;
  return async (...a: A): Promise<R> => {
    if (seen++ < times) throw error();
    return fn(...a);
  };
}

export const providerError = (
  code: string,
  outcome: 'not_started' | 'unknown' | 'terminal',
  extra: { credentialsInvalid?: boolean; providerFunds?: boolean; retryAfterMs?: number; httpStatus?: number } = {},
) => new ProviderError(code, `scripted ${code}`, { outcome, ...extra });

/** A promise that never settles on its own, but rejects when aborted (like a hung HTTP request). */
export const hang = (signal: AbortSignal): Promise<never> =>
  new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('aborted'))));
