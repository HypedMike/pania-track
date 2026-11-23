import { currentLocale } from "../../shared/i18n/i18n";

/** m/s as "4.3 km/h". */
export function formatSpeed(ms: number | null | undefined): string {
  return ms === null || ms === undefined ? "—" : `${(ms * 3.6).toFixed(1)} km/h`;
}

/** Seconds as "1h 05m" or "12m" (see `formatDuration`, which takes milliseconds). */
export function formatSeconds(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return "—";
  const total = Math.round(Math.abs(seconds) / 60);
  const h = Math.floor(total / 60);
  const m = total % 60;
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
}

/** A difference in time with its sign: "+12m" is slower than planned, "-3m" is faster. */
export function formatDelta(seconds: number): string {
  if (Math.abs(seconds) < 30) return "±0m";
  return `${seconds > 0 ? "+" : "−"}${formatSeconds(seconds)}`;
}

/** Percent slope as "+12%" or "−5%". */
export function formatGrade(pct: number): string {
  const rounded = Math.round(pct);
  return `${rounded > 0 ? "+" : rounded < 0 ? "−" : ""}${Math.abs(rounded)}%`;
}

/** Clock time of a point in time, in the app's language. */
export function formatClockTime(ms: number): string {
  return new Date(ms).toLocaleTimeString(currentLocale(), { hour: "2-digit", minute: "2-digit" });
}

/** Meters per hour of climbing, "620 m/h". */
export function formatVerticalSpeed(mh: number | null | undefined): string {
  return mh === null || mh === undefined ? "—" : `${Math.round(mh)} m/h`;
}

/** Month names in the app's language, January first. */
export function monthNames(): string[] {
  return Array.from({ length: 12 }, (_, i) =>
    new Date(2024, i, 1).toLocaleDateString(currentLocale(), { month: "short" }),
  );
}

/** Weekday names in the app's language, Monday first. */
export function weekdayNames(): string[] {
  // 1 January 2024 was a Monday.
  return Array.from({ length: 7 }, (_, i) =>
    new Date(2024, 0, 1 + i).toLocaleDateString(currentLocale(), { weekday: "short" }),
  );
}
