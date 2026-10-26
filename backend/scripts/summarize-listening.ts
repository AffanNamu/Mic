// Aggregates listening-test ratings (docs/poc/listening-test-template.csv) per song and language.
//
//   node --disable-warning=ExperimentalWarning scripts/summarize-listening.ts ratings.csv [more.csv ...]
//
// The verdict rules are written down BEFORE listening (docs/poc/README.md) so they cannot drift to fit
// the result: a song or language is only called "meets bar" with enough NATIVE raters, and never from
// automated checks. With too few native raters the verdict is "insufficient evidence", not a pass.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const SCORES = ['similarity', 'pronunciation', 'naturalness', 'arrangement', 'intelligibility', 'overall'] as const;
export type Score = (typeof SCORES)[number];

/** Pre-registered thresholds (mean on a 1-5 scale) and minimum number of native raters. Change only before a round. */
export const BAR = {
  minNativeRaters: 3,
  similarity: 4.0,
  pronunciation: 4.0,
  naturalness: 3.5,
  intelligibility: 3.5,
} as const;

export interface Rating {
  songId: string;
  raterId: string;
  language: string;
  raterNative: boolean;
  heardReferenceFirst: boolean;
  scores: Partial<Record<Score, number>>;
  wouldShare: boolean | null;
  notes: string;
}

export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = '';
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i]!;
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ',') { row.push(cell); cell = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(cell); cell = '';
      if (row.some((v) => v.trim() !== '')) rows.push(row);
      row = [];
    } else cell += c;
  }
  row.push(cell);
  if (row.some((v) => v.trim() !== '')) rows.push(row);
  return rows;
}

const yes = (v: string | undefined) => (v ?? '').trim().toLowerCase();
const truthy = (v: string | undefined) => ['y', 'yes', 'true', '1'].includes(yes(v));

export function readRatings(csv: string): { ratings: Rating[]; problems: string[] } {
  const rows = parseCsv(csv);
  const problems: string[] = [];
  const header = (rows.shift() ?? []).map((h) => h.trim());
  const col = (name: string) => header.indexOf(name);
  for (const need of ['song_id', 'rater_id', 'lyrics_language', 'rater_native_speaker']) {
    if (col(need) < 0) problems.push(`missing column: ${need}`);
  }
  if (problems.length) return { ratings: [], problems };
  const ratings: Rating[] = [];
  rows.forEach((r, i) => {
    const line = i + 2;
    const scores: Partial<Record<Score, number>> = {};
    for (const s of SCORES) {
      const raw = (r[col(s)] ?? '').trim();
      if (raw === '') continue;
      const n = Number(raw);
      if (!Number.isInteger(n) || n < 1 || n > 5) { problems.push(`line ${line}: ${s} must be a whole number 1-5 (got "${raw}")`); continue; }
      scores[s] = n;
    }
    const songId = (r[col('song_id')] ?? '').trim();
    const raterId = (r[col('rater_id')] ?? '').trim();
    if (!songId || !raterId) { problems.push(`line ${line}: song_id and rater_id are required`); return; }
    const shareRaw = yes(r[col('would_share')]);
    ratings.push({
      songId, raterId, language: yes(r[col('lyrics_language')]), raterNative: truthy(r[col('rater_native_speaker')]),
      heardReferenceFirst: truthy(r[col('heard_reference_first')]), scores,
      wouldShare: shareRaw === '' ? null : truthy(shareRaw), notes: (r[col('notes')] ?? '').trim(),
    });
  });
  const seen = new Set<string>();
  for (const r of ratings) {
    const k = `${r.songId}|${r.raterId}`;
    if (seen.has(k)) problems.push(`duplicate rating: rater ${r.raterId} rated ${r.songId} more than once`);
    seen.add(k);
  }
  return { ratings, problems };
}

const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
const round = (n: number | null) => (n === null ? null : Math.round(n * 100) / 100);

export interface SongSummary {
  songId: string;
  language: string;
  raters: number;
  nativeRaters: number;
  means: Partial<Record<Score, number | null>>;
  shareRate: number | null;
  verdict: 'meets bar' | 'below bar' | 'insufficient evidence';
  reasons: string[];
}

export function summarize(ratings: Rating[]): SongSummary[] {
  const bySong = new Map<string, Rating[]>();
  for (const r of ratings) (bySong.get(r.songId) ?? bySong.set(r.songId, []).get(r.songId)!).push(r);
  return [...bySong].map(([songId, rs]) => {
    const native = rs.filter((r) => r.raterNative);
    const means: Partial<Record<Score, number | null>> = {};
    for (const s of SCORES) {
      // Pronunciation and intelligibility are only meaningful from native speakers of the lyrics' language.
      const pool = s === 'pronunciation' || s === 'intelligibility' ? native : rs;
      means[s] = round(mean(pool.map((r) => r.scores[s]).filter((v): v is number => v !== undefined)));
    }
    const share = rs.filter((r) => r.wouldShare !== null);
    const reasons: string[] = [];
    let verdict: SongSummary['verdict'] = 'meets bar';
    if (native.length < BAR.minNativeRaters) {
      verdict = 'insufficient evidence';
      reasons.push(`${native.length} native rater(s); at least ${BAR.minNativeRaters} are required`);
    } else {
      for (const k of ['similarity', 'pronunciation', 'naturalness', 'intelligibility'] as const) {
        const m = means[k];
        if (m === null || m === undefined) { verdict = 'insufficient evidence'; reasons.push(`no ${k} scores`); }
        else if (m < BAR[k]) { if (verdict === 'meets bar') verdict = 'below bar'; reasons.push(`${k} ${m} < ${BAR[k]}`); }
      }
      const unprimed = rs.filter((r) => !r.heardReferenceFirst).length;
      if (unprimed > 0) reasons.push(`${unprimed} rating(s) were made without hearing the reference voice first; similarity may be unreliable`);
    }
    return {
      songId, language: rs[0]!.language, raters: rs.length, nativeRaters: native.length, means,
      shareRate: share.length ? round(share.filter((r) => r.wouldShare).length / share.length) : null, verdict, reasons,
    };
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const files = process.argv.slice(2);
  if (files.length === 0) { console.error('Usage: summarize-listening.ts ratings.csv [more.csv ...]'); process.exit(1); }
  const all: Rating[] = [];
  const problems: string[] = [];
  for (const f of files) {
    const r = readRatings(readFileSync(f, 'utf8'));
    all.push(...r.ratings);
    problems.push(...r.problems.map((p) => `${f}: ${p}`));
  }
  if (problems.length) { console.error('Problems in the ratings:\n - ' + problems.join('\n - ')); process.exit(2); }
  for (const s of summarize(all)) {
    console.log(`\n${s.songId}  [${s.language}]  raters=${s.raters} (native ${s.nativeRaters})  → ${s.verdict.toUpperCase()}`);
    console.log('  ' + Object.entries(s.means).map(([k, v]) => `${k}=${v ?? '–'}`).join('  '));
    if (s.shareRate !== null) console.log(`  would share: ${Math.round(s.shareRate * 100)}%`);
    for (const r of s.reasons) console.log(`  - ${r}`);
  }
}
