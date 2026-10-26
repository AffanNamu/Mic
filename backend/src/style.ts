/** Turns the app's style choices into text a lyrics-to-song provider can use. */
const GENRE: Record<string, string> = {
  islamic_nasheed: 'Islamic nasheed, devotional, traditional and modern',
  hausa_nasheed: 'Hausa nasheed, devotional',
  arabic_nasheed: 'Arabic nasheed, spiritual and uplifting',
  english_nasheed: 'English nasheed, modern and inspirational',
  qasida: 'qasida, classical devotional poetry',
};
const MOOD: Record<string, string> = {
  peaceful: 'peaceful', uplifting: 'uplifting', reflective: 'reflective',
  joyful: 'joyful', hopeful: 'hopeful', solemn: 'solemn',
};
const TEMPO: Record<string, string> = { slow: 'slow tempo', normal: 'medium tempo', upbeat: 'upbeat tempo' };
const INTENSITY: Record<string, string> = {
  gentle: 'gentle vocal', balanced: 'balanced vocal', powerful: 'powerful vocal',
};
const INSTRUMENTS: Record<string, string> = {
  traditional: 'traditional acoustic instruments, hand percussion',
  acoustic: 'acoustic instruments',
  modern: 'modern arrangement',
  vocals_only: 'a cappella, vocals only, no instruments',
};

export const STYLE_KEYS = ['genre', 'mood', 'tempo', 'duration', 'intensity', 'instruments'] as const;

export function stylePrompt(style: Record<string, string>): string {
  return [
    GENRE[style['genre'] ?? ''], MOOD[style['mood'] ?? ''], TEMPO[style['tempo'] ?? ''],
    INTENSITY[style['intensity'] ?? ''], INSTRUMENTS[style['instruments'] ?? ''],
  ].filter(Boolean).join(', ');
}
