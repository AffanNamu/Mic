import type { Config } from '../config.ts';
import type { MusicProvider } from './types.ts';
import { UnconfiguredProvider } from './unconfigured.ts';
import { MurekaProvider } from './mureka.ts';
import { WaveSpeedHeartMulaProvider } from './wavespeed.ts';

export function createProvider(config: Config): MusicProvider {
  if (config.provider === 'mureka') {
    return new MurekaProvider({
      apiKey: config.murekaApiKey!, baseUrl: config.murekaBaseUrl, experimentalLanguages: config.experimentalLanguages,
      model: config.mureka.model, vocalClonePath: config.mureka.vocalClonePath,
      songCostMicros: config.mureka.songCostMicros, enrollCostMicros: config.mureka.enrollCostMicros,
      audioHosts: config.mureka.audioHosts,
    });
  }
  if (config.provider === 'heartmula') {
    return new WaveSpeedHeartMulaProvider({
      apiKey: config.wavespeedApiKey!, baseUrl: config.wavespeedBaseUrl, experimentalLanguages: config.experimentalLanguages,
      songCostMicros: config.wavespeed.songCostMicros, audioHosts: config.wavespeed.audioHosts,
    });
  }
  return new UnconfiguredProvider();
}
