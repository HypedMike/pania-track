import { computeStats, type TrailStats } from "../../shared/gps/trail_stats";
import type { Trail } from "../trail/interfaces/trail";

export type Period = "week" | "month" | "year" | "all";

export interface TrailEntry {
  trail: Trail;
  stats: TrailStats;
  /** When the trail was walked: first GPS timestamp, falling back to when it was saved. */
  date: Date | null;
}

export interface Bucket {
  start: Date;
  end: Date;
  recordedM: number;
  importedM: number;
}

export interface Records {
  longest?: TrailEntry;
  climb?: TrailEntry;
  highest?: TrailEntry;
  time?: TrailEntry;
}

export interface SourceTotals {
  count: number;
  distanceM: number;
}

export interface PeriodSummary {
  count: number;
  distanceM: number;
  gainM: number;
  movingMs: number;
  avgDistanceM: number;
  avgGainM: number | null;
  avgSpeedKmh: number | null;
  records: Records;
  recorded: SourceTotals;
  imported: SourceTotals;
  /** Local-date keys (see dayKey) of days with at least one trail. */
  activeDays: Set<string>;
}

const MAX_YEAR_BARS = 6;

export function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function addDays(d: Date, n: number): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

/** Weeks start on Monday. */
export function startOfWeek(d: Date): Date {
  const s = startOfDay(d);
  return addDays(s, -((s.getDay() + 6) % 7));
}

export function dayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

export function toEntries(trails: Trail[]): TrailEntry[] {
  return trails.map((trail) => {
    const stamp = trail.coordinates.find((c) => c.timestamp)?.timestamp;
    const parsed = stamp ? Date.parse(stamp) : NaN;
    const ms = Number.isNaN(parsed) ? trail.createdAt : parsed;
    return { trail, stats: computeStats(trail.coordinates), date: ms ? new Date(ms) : null };
  });
}

/** Half-open [start, end) range of a period; null bounds mean unbounded. */
export function periodRange(period: Period, now: Date): { start: Date | null; end: Date | null } {
  switch (period) {
    case "week": {
      const start = startOfWeek(now);
      return { start, end: addDays(start, 7) };
    }
    case "month":
      return {
        start: new Date(now.getFullYear(), now.getMonth(), 1),
        end: new Date(now.getFullYear(), now.getMonth() + 1, 1),
      };
    case "year":
      return { start: new Date(now.getFullYear(), 0, 1), end: new Date(now.getFullYear() + 1, 0, 1) };
    case "all":
      return { start: null, end: null };
  }
}

export function filterByPeriod(entries: TrailEntry[], period: Period, now: Date): TrailEntry[] {
  const { start, end } = periodRange(period, now);
  if (!start || !end) return entries;
  return entries.filter((e) => e.date && e.date >= start && e.date < end);
}

/** Bars for the distance chart: days (week), 6 weeks (month), months (year) or years (all). */
export function buildBuckets(period: Period, entries: TrailEntry[], now: Date): Bucket[] {
  const ranges: { start: Date; end: Date }[] = [];
  if (period === "week") {
    const ws = startOfWeek(now);
    for (let i = 0; i < 7; i++) ranges.push({ start: addDays(ws, i), end: addDays(ws, i + 1) });
  } else if (period === "month") {
    const ws = startOfWeek(now);
    for (let i = -5; i <= 0; i++) ranges.push({ start: addDays(ws, i * 7), end: addDays(ws, i * 7 + 7) });
  } else if (period === "year") {
    for (let m = 0; m < 12; m++) {
      ranges.push({ start: new Date(now.getFullYear(), m, 1), end: new Date(now.getFullYear(), m + 1, 1) });
    }
  } else {
    const years = entries.flatMap((e) => (e.date ? [e.date.getFullYear()] : []));
    const first = Math.max(Math.min(now.getFullYear(), ...years), now.getFullYear() - MAX_YEAR_BARS + 1);
    for (let y = first; y <= now.getFullYear(); y++) {
      ranges.push({ start: new Date(y, 0, 1), end: new Date(y + 1, 0, 1) });
    }
  }

  const buckets: Bucket[] = ranges.map((r) => ({ ...r, recordedM: 0, importedM: 0 }));
  for (const { trail, stats, date } of entries) {
    if (!date) continue;
    const bucket = buckets.find((b) => date >= b.start && date < b.end);
    if (!bucket) continue;
    if (trail.source === "recorded") bucket.recordedM += stats.distanceM;
    else bucket.importedM += stats.distanceM;
  }
  return buckets;
}

function best(entries: TrailEntry[], value: (e: TrailEntry) => number | null): TrailEntry | undefined {
  let winner: TrailEntry | undefined;
  let max = -Infinity;
  for (const e of entries) {
    const v = value(e);
    if (v !== null && v > max) {
      max = v;
      winner = e;
    }
  }
  return winner;
}

export function summarize(entries: TrailEntry[]): PeriodSummary {
  const recorded: SourceTotals = { count: 0, distanceM: 0 };
  const imported: SourceTotals = { count: 0, distanceM: 0 };
  const activeDays = new Set<string>();
  let distanceM = 0;
  let gainM = 0;
  let gainCount = 0;
  let movingMs = 0;
  let timedDistanceM = 0;

  for (const { trail, stats, date } of entries) {
    distanceM += stats.distanceM;
    const totals = trail.source === "recorded" ? recorded : imported;
    totals.count += 1;
    totals.distanceM += stats.distanceM;
    if (stats.elevationGainM !== null) {
      gainM += stats.elevationGainM;
      gainCount += 1;
    }
    if (stats.durationMs !== null && stats.durationMs > 0) {
      movingMs += stats.durationMs;
      timedDistanceM += stats.distanceM;
    }
    if (date) activeDays.add(dayKey(date));
  }

  const count = entries.length;
  return {
    count,
    distanceM,
    gainM,
    movingMs,
    avgDistanceM: count > 0 ? distanceM / count : 0,
    avgGainM: gainCount > 0 ? gainM / gainCount : null,
    avgSpeedKmh: movingMs > 0 ? timedDistanceM / 1000 / (movingMs / 3_600_000) : null,
    records: {
      longest: best(entries, (e) => e.stats.distanceM),
      climb: best(entries, (e) => e.stats.elevationGainM),
      highest: best(entries, (e) => e.stats.highestM),
      time: best(entries, (e) => e.stats.durationMs),
    },
    recorded,
    imported,
    activeDays,
  };
}
