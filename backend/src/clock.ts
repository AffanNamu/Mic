export interface Clock {
  now(): Date;
}

export const systemClock: Clock = { now: () => new Date() };

/** UTC ISO-8601 with milliseconds; lexicographic order equals time order. */
export const iso = (d: Date): string => d.toISOString();
export const addMs = (d: Date, ms: number): Date => new Date(d.getTime() + ms);
