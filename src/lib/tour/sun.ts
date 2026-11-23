/**
 * Sunrise and sunset from the "sunrise equation" (https://en.wikipedia.org/wiki/Sunrise_equation).
 * Accurate to a few minutes at mid-latitudes, which is plenty for "you'll arrive after dark".
 * No network needed.
 */

const J2000 = 2451545.0;
const DAY_MS = 86_400_000;
const rad = (deg: number) => (deg * Math.PI) / 180;

const jdToMs = (jd: number) => (jd - 2440587.5) * DAY_MS;
const msToJd = (ms: number) => ms / DAY_MS + 2440587.5;

export interface SunEvent {
  type: "sunrise" | "sunset";
  /** Milliseconds since the epoch. */
  time: number;
}

/** Sunrise and sunset of solar day number `n`, or null in polar day / polar night. */
function eventsForDay(n: number, lat: number, lon: number): SunEvent[] {
  const jStar = n - lon / 360; // solar noon comes earlier the further east you are
  const M = (357.5291 + 0.98560028 * jStar) % 360;
  const C = 1.9148 * Math.sin(rad(M)) + 0.02 * Math.sin(rad(2 * M)) + 0.0003 * Math.sin(rad(3 * M));
  const lambda = (M + C + 180 + 102.9372) % 360;
  const transit = J2000 + jStar + 0.0053 * Math.sin(rad(M)) - 0.0069 * Math.sin(rad(2 * lambda));
  const sinDecl = Math.sin(rad(lambda)) * Math.sin(rad(23.4397));
  const cosDecl = Math.cos(Math.asin(sinDecl));
  const cosOmega = (Math.sin(rad(-0.833)) - Math.sin(rad(lat)) * sinDecl) / (Math.cos(rad(lat)) * cosDecl);
  if (cosOmega < -1 || cosOmega > 1) return [];
  const omega = (Math.acos(cosOmega) * 180) / Math.PI;
  return [
    { type: "sunrise", time: jdToMs(transit - omega / 360) },
    { type: "sunset", time: jdToMs(transit + omega / 360) },
  ];
}

/** Sunrises and sunsets around `atMs` (about three days of them), in time order. */
export function sunEvents(lat: number, lon: number, atMs: number): SunEvent[] {
  const n = Math.round(msToJd(atMs) - J2000 + 0.0008 + lon / 360);
  const all: SunEvent[] = [];
  for (let d = -2; d <= 2; d++) all.push(...eventsForDay(n + d, lat, lon));
  return all.sort((a, b) => a.time - b.time);
}

/** The next sunset at or after `fromMs`, or null where the sun does not set. */
export function nextSunset(lat: number, lon: number, fromMs: number): number | null {
  return sunEvents(lat, lon, fromMs).find((e) => e.type === "sunset" && e.time >= fromMs)?.time ?? null;
}

/** Whether the sun is below the horizon at `atMs`. Polar day and night count as light. */
export function isDark(lat: number, lon: number, atMs: number): boolean {
  const before = sunEvents(lat, lon, atMs).filter((e) => e.time <= atMs);
  return before.length > 0 && before[before.length - 1].type === "sunset";
}
