import type { Deps } from './deps.ts';
import { all, one } from './db.ts';

/**
 * Operator metrics for evaluating a provider: completion rate, latency and cost
 * per *successful* song. Provider cost is the rate-card estimate unless the
 * provider reported a real figure, so treat it as an estimate until reconciled
 * against the provider's invoice.
 */
export function metrics(deps: Deps, sinceIso: string) {
  const byStatus = all(deps.db,
    `SELECT status, COUNT(*) AS n FROM jobs WHERE created_at >= ? GROUP BY status`, sinceIso)
    .map((r) => [String(r['status']), Number(r['n'])] as const);
  const counts = Object.fromEntries(byStatus);
  const completed = counts['completed'] ?? 0;
  const failed = counts['failed'] ?? 0;
  const finished = completed + failed;

  const latency = all(deps.db,
    `SELECT (julianday(completed_at) - julianday(created_at)) * 86400000 AS ms
       FROM jobs WHERE status = 'completed' AND created_at >= ? ORDER BY ms`, sinceIso).map((r) => Number(r['ms']));
  const pct = (p: number) => (latency.length ? Math.round(latency[Math.min(latency.length - 1, Math.floor(p * latency.length))]!) : null);

  const cost = one(deps.db,
    `SELECT COALESCE(SUM(provider_cost_micros), 0) AS all_micros,
            COALESCE(SUM(CASE WHEN status = 'completed' THEN provider_cost_micros END), 0) AS ok_micros
       FROM jobs WHERE created_at >= ? AND provider_task_id IS NOT NULL`, sinceIso);
  const voiceCost = one(deps.db,
    `SELECT COALESCE(SUM(provider_cost_micros), 0) AS micros FROM voices WHERE created_at >= ?`, sinceIso);
  const failures = all(deps.db,
    `SELECT failure_code AS code, COUNT(*) AS n FROM jobs WHERE status = 'failed' AND created_at >= ? GROUP BY failure_code ORDER BY n DESC`, sinceIso)
    .map((r) => ({ code: String(r['code']), count: Number(r['n']) }));

  const allMicros = Number(cost?.['all_micros'] ?? 0);
  return {
    since: sinceIso,
    jobs: counts,
    completionRate: finished ? completed / finished : null,
    latencyMs: { p50: pct(0.5), p90: pct(0.9), max: latency.length ? Math.round(latency[latency.length - 1]!) : null },
    cost: {
      currency: 'USD',
      basis: 'provider-reported where available, otherwise published rate card (estimate)',
      songsAttemptedMicros: allMicros,
      voiceEnrollmentMicros: Number(voiceCost?.['micros'] ?? 0),
      /** All spend on songs, including failed attempts that were billed, divided by successes. */
      perSuccessfulSongMicros: completed ? Math.round(allMicros / completed) : null,
    },
    failures,
  };
}
