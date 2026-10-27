import { resolve } from 'node:path';

export interface Config {
  host: string;
  port: number;
  databasePath: string;
  blobDir: string;
  /** 32-byte key for AES-256-GCM encryption of stored audio. */
  blobKey: Buffer;
  /** Secret for signing short-lived media URLs. */
  mediaKey: Buffer;
  /** Static token for operator endpoints (credit grants). Null disables them. */
  adminToken: string | null;
  corsOrigins: string[];
  provider: 'mureka' | 'none';
  murekaApiKey: string | null;
  murekaBaseUrl: string;
  mureka: {
    model: string;
    /** Path of the vocal-cloning operation. Unknown until read from the official reference; enrollment is disabled without it. */
    vocalClonePath: string | null;
    songCostMicros: number;
    enrollCostMicros: number;
    audioHosts: string[];
  };
  /** Languages declared supported beyond the provider's documented list (evaluation only). */
  experimentalLanguages: string[];
  maxVoiceBytes: number;
  maxLyricsChars: number;
  sessionTtlMs: number;
  jobDeadlineMs: number;
  leaseMs: number;
  credits: { perSong: number };
}

type Env = Record<string, string | undefined>;

/**
 * Reads configuration from the environment and fails fast, listing every
 * problem at once. There are no default secrets: a server without its keys must
 * not start.
 */
export function loadConfig(env: Env = process.env): Config {
  const problems: string[] = [];
  const need = (name: string): string => {
    const v = env[name];
    if (!v) problems.push(`${name} is required`);
    return v ?? '';
  };

  const blobKeyRaw = need('BLOB_ENCRYPTION_KEY');
  const blobKey = Buffer.from(blobKeyRaw, 'base64');
  if (blobKeyRaw && blobKey.length !== 32) {
    problems.push('BLOB_ENCRYPTION_KEY must be 32 bytes, base64-encoded (openssl rand -base64 32)');
  }
  const mediaRaw = need('MEDIA_SIGNING_KEY');
  if (mediaRaw && mediaRaw.length < 32) problems.push('MEDIA_SIGNING_KEY must be at least 32 characters');

  const provider = (env['PROVIDER'] ?? 'none') as Config['provider'];
  if (provider !== 'mureka' && provider !== 'none') problems.push('PROVIDER must be "mureka" or "none"');
  const murekaApiKey = env['MUREKA_API_KEY'] ?? null;
  if (provider === 'mureka' && !murekaApiKey) problems.push('MUREKA_API_KEY is required when PROVIDER=mureka');

  const adminToken = env['ADMIN_TOKEN'] ?? null;
  if (adminToken !== null && adminToken.length < 24) problems.push('ADMIN_TOKEN must be at least 24 characters');

  const num = (name: string, dflt: number): number => {
    const raw = env[name];
    if (raw === undefined) return dflt;
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0) problems.push(`${name} must be a positive number`);
    return n;
  };

  // Numbers are read before the check so a bad value is reported with the other problems.
  const numbers = {
    port: num('PORT', 8080),
    songCostMicros: num('MUREKA_SONG_COST_MICROS', 45_000),
    enrollCostMicros: num('MUREKA_ENROLL_COST_MICROS', 5_000_000),
    maxVoiceBytes: num('MAX_VOICE_BYTES', 25 * 1024 * 1024),
    maxLyricsChars: num('MAX_LYRICS_CHARS', 3000),
    sessionDays: num('SESSION_TTL_DAYS', 30),
    jobDeadlineMinutes: num('JOB_DEADLINE_MINUTES', 20),
    // Longer than the slowest single step (a 60 s download) so a live worker never loses its own lease.
    leaseSeconds: num('JOB_LEASE_SECONDS', 120),
    creditsPerSong: num('CREDITS_PER_SONG', 1),
  };

  if (problems.length > 0) {
    throw new Error(`Invalid configuration:\n - ${problems.join('\n - ')}`);
  }

  return {
    host: env['HOST'] ?? '127.0.0.1',
    port: numbers.port,
    databasePath: resolve(env['DATABASE_PATH'] ?? './data/deenvoice.sqlite'),
    blobDir: resolve(env['BLOB_DIR'] ?? './data/blobs'),
    blobKey,
    mediaKey: Buffer.from(mediaRaw, 'utf8'),
    adminToken,
    corsOrigins: (env['CORS_ORIGINS'] ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    provider,
    murekaApiKey,
    murekaBaseUrl: env['MUREKA_BASE_URL'] ?? 'https://api.mureka.ai',
    mureka: {
      model: env['MUREKA_MODEL'] ?? 'auto',
      vocalClonePath: env['MUREKA_VOCAL_CLONE_PATH'] ?? null,
      // Published rate card (2026-10-26): lyrics-to-song $0.045 on O2/V8/V9, $0.15 on V9.5; $5 per Vocal ID.
      songCostMicros: numbers.songCostMicros,
      enrollCostMicros: numbers.enrollCostMicros,
      audioHosts: (env['MUREKA_AUDIO_HOSTS'] ?? '').split(',').map((h) => h.trim().toLowerCase()).filter(Boolean),
    },
    experimentalLanguages: (env['EXPERIMENTAL_LANGUAGES'] ?? '')
      .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean),
    maxVoiceBytes: numbers.maxVoiceBytes,
    maxLyricsChars: numbers.maxLyricsChars,
    sessionTtlMs: numbers.sessionDays * 86_400_000,
    jobDeadlineMs: numbers.jobDeadlineMinutes * 60_000,
    leaseMs: numbers.leaseSeconds * 1000,
    credits: { perSong: numbers.creditsPerSong },
  };
}
