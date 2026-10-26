/**
 * What happened to a request that failed, from the point of view of cost:
 *  - not_started: the provider definitely did not begin work (connection
 *    refused, 429, 503 with no side effect). Safe to retry.
 *  - unknown: the request may have reached the provider (timeout, connection
 *    reset, 5xx). Retrying could start and bill a second song, so it is not
 *    retried automatically.
 *  - terminal: the provider rejected it (bad input, bad credentials, no funds,
 *    policy). Retrying will not help.
 */
export type ErrorOutcome = 'not_started' | 'unknown' | 'terminal';

export class ProviderError extends Error {
  readonly code: string;
  readonly outcome: ErrorOutcome;
  readonly retryAfterMs: number | undefined;
  readonly httpStatus: number | undefined;
  /** The provider rejected our credentials (expired, revoked, wrong). */
  readonly credentialsInvalid: boolean;
  /** The provider account has no balance left. */
  readonly providerFunds: boolean;

  constructor(
    code: string,
    message: string,
    opts: {
      outcome: ErrorOutcome;
      retryAfterMs?: number;
      httpStatus?: number;
      credentialsInvalid?: boolean;
      providerFunds?: boolean;
    },
  ) {
    super(message);
    this.name = 'ProviderError';
    this.code = code;
    this.outcome = opts.outcome;
    this.retryAfterMs = opts.retryAfterMs;
    this.httpStatus = opts.httpStatus;
    this.credentialsInvalid = opts.credentialsInvalid ?? false;
    this.providerFunds = opts.providerFunds ?? false;
  }
}

export interface ProviderCapabilities {
  /** Null means no provider is connected: nothing can be generated. */
  engineName: string | null;
  /** Client song-type ids (`full_song`, `vocal_only`, `instrumental`, `nasheed_style`). */
  songTypes: string[];
  /** Client language ids that jobs may use (documented + experimental). */
  languages: string[];
  /** The subset of `languages` the provider documents as supported. */
  documentedLanguages: string[];
  /** Can sing in an enrolled voice. */
  voiceConditioning: boolean;
  advancedOptionIds: string[];
  /** Required length of an enrollment sample, if the provider states one. */
  voiceSampleSeconds: { min: number; max: number } | null;
  /** Published rate card, in millionths of a USD (1_000_000 = $1). For cost accounting only. */
  estimatedSongCostMicros: number | null;
  estimatedEnrollCostMicros: number | null;
}

export interface SongRequest {
  lyrics: string;
  language: string;
  /** Style text composed from genre, mood, tempo and instruments. */
  stylePrompt: string;
  providerVoiceId: string | null;
  settings: Record<string, string>;
}

export type SongPoll =
  | { state: 'running' }
  | { state: 'succeeded'; audioUrl: string | null; durationMs: number | null; costMicros: number | null }
  | { state: 'failed'; code: string; message: string };

export interface MusicProvider {
  readonly name: string;
  readonly configured: boolean;
  capabilities(): ProviderCapabilities;
  enrollVoice(input: { audio: Buffer; mime: string; fileName: string }, signal: AbortSignal):
    Promise<{ providerVoiceId: string; costMicros: number | null }>;
  /** `unsupported` must be reported honestly when the provider offers no deletion API. */
  deleteVoice(providerVoiceId: string, signal: AbortSignal): Promise<'deleted' | 'requested' | 'unsupported'>;
  submitSong(req: SongRequest, signal: AbortSignal): Promise<{ providerTaskId: string }>;
  pollSong(providerTaskId: string, signal: AbortSignal): Promise<SongPoll>;
  downloadAudio(audioUrl: string, signal: AbortSignal): Promise<Buffer>;
}
