export type AudioKind = 'wav' | 'mp3' | 'aac' | 'm4a' | 'ogg' | 'flac' | 'webm';

export interface AudioInfo {
  kind: AudioKind;
  mime: string;
}

const MIME: Record<AudioKind, string> = {
  wav: 'audio/wav', mp3: 'audio/mpeg', aac: 'audio/aac', m4a: 'audio/mp4',
  ogg: 'audio/ogg', flac: 'audio/flac', webm: 'audio/webm',
};

/**
 * Identifies audio by its leading bytes. The declared content type and file
 * name are never trusted. Returns null for anything that is not recognisably
 * audio (HTML error pages, JSON, empty bodies).
 */
export function sniffAudio(buf: Buffer): AudioInfo | null {
  if (buf.length < 12) return null;
  const ascii = (from: number, to: number) => buf.toString('latin1', from, to);
  let kind: AudioKind | null = null;
  if (ascii(0, 4) === 'RIFF' && ascii(8, 12) === 'WAVE') kind = 'wav';
  else if (ascii(0, 4) === 'fLaC') kind = 'flac';
  else if (ascii(0, 4) === 'OggS') kind = 'ogg';
  else if (ascii(4, 8) === 'ftyp') kind = 'm4a';
  else if (buf[0] === 0x1a && buf[1] === 0x45 && buf[2] === 0xdf && buf[3] === 0xa3) kind = 'webm';
  else if (ascii(0, 3) === 'ID3') kind = 'mp3';
  else if (buf[0] === 0xff && ((buf[1] ?? 0) & 0xf6) === 0xf0) kind = 'aac';
  else if (buf[0] === 0xff && ((buf[1] ?? 0) & 0xe0) === 0xe0) kind = 'mp3';
  return kind ? { kind, mime: MIME[kind] } : null;
}

/** Exact duration for PCM WAV; null for other formats (which would need decoding). */
export function wavDurationMs(buf: Buffer): number | null {
  if (buf.length < 44 || buf.toString('latin1', 0, 4) !== 'RIFF') return null;
  let offset = 12;
  let byteRate = 0;
  while (offset + 8 <= buf.length) {
    const id = buf.toString('latin1', offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    if (id === 'fmt ' && offset + 20 <= buf.length) byteRate = buf.readUInt32LE(offset + 16);
    if (id === 'data') {
      const dataBytes = Math.min(size, buf.length - offset - 8);
      return byteRate > 0 ? Math.round((dataBytes / byteRate) * 1000) : null;
    }
    offset += 8 + size + (size % 2);
  }
  return null;
}
