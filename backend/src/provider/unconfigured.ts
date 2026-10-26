import type { MusicProvider, ProviderCapabilities } from './types.ts';
import { ProviderError } from './types.ts';

const notConfigured = () =>
  new ProviderError('provider_not_configured', 'No music provider is configured on this server.', {
    outcome: 'terminal',
  });

/** The default: every operation fails clearly. Never produces audio. */
export class UnconfiguredProvider implements MusicProvider {
  readonly name = 'none';
  readonly configured = false;

  capabilities(): ProviderCapabilities {
    return {
      engineName: null, songTypes: [], languages: [], documentedLanguages: [],
      voiceConditioning: false, advancedOptionIds: [], voiceSampleSeconds: null,
      estimatedSongCostMicros: null, estimatedEnrollCostMicros: null,
    };
  }
  enrollVoice(): Promise<never> { return Promise.reject(notConfigured()); }
  deleteVoice(): Promise<never> { return Promise.reject(notConfigured()); }
  submitSong(): Promise<never> { return Promise.reject(notConfigured()); }
  pollSong(): Promise<never> { return Promise.reject(notConfigured()); }
  downloadAudio(): Promise<never> { return Promise.reject(notConfigured()); }
}
