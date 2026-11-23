import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

/**
 * Past weather from Open-Meteo's archive (https://open-meteo.com/en/docs/historical-weather-api),
 * to see how temperature and rain affected the person's pace. Only a coordinate and a date go
 * out. The archive trails real time by a few days, so very recent walks have no weather yet.
 */
const ENDPOINT = "https://archive-api.open-meteo.com/v1/archive";
const CACHE_PREFIX = "pania.weather.";
const HOUR_MS = 3_600_000;

export interface WalkWeather {
  tempC: number;
  /** Rain over the walk, in mm. */
  precipMm: number;
}

interface Hourly {
  /** "YYYY-MM-DDTHH:00" in GMT. */
  time: string[];
  temperature_2m: (number | null)[];
  precipitation: (number | null)[];
}

/** Average temperature and total rain over the hours a walk touched. `null` if no hour has data. */
export function summarizeWalkWeather(hourly: Hourly, fromMs: number, toMs: number): WalkWeather | null {
  let tempSum = 0;
  let tempCount = 0;
  let precip = 0;
  hourly.time.forEach((time, i) => {
    const start = Date.parse(`${time}:00Z`);
    if (Number.isNaN(start) || start + HOUR_MS <= fromMs || start > toMs) return;
    const t = hourly.temperature_2m[i];
    if (t !== null && t !== undefined) {
      tempSum += t;
      tempCount++;
    }
    precip += hourly.precipitation[i] ?? 0;
  });
  return tempCount === 0 ? null : { tempC: tempSum / tempCount, precipMm: precip };
}

function day(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function readCache(key: string): WalkWeather | null | undefined {
  try {
    const raw = localStorage.getItem(CACHE_PREFIX + key);
    return raw === null ? undefined : (JSON.parse(raw) as WalkWeather | null);
  } catch {
    return undefined;
  }
}

function writeCache(key: string, value: WalkWeather | null) {
  try {
    localStorage.setItem(CACHE_PREFIX + key, JSON.stringify(value));
  } catch {
    // Storage full or blocked: the weather is just looked up again next time.
  }
}

/**
 * The weather during a trail, from where it started and the times of its first and last points.
 * Cached per trail, since the past does not change. `null` for trails without times, and when
 * the archive does not have the day yet (not cached, so it is asked again later).
 */
export async function fetchWalkWeather(
  trailId: string,
  coords: GpsCoordinate[],
  signal?: AbortSignal,
): Promise<WalkWeather | null> {
  const cached = readCache(trailId);
  if (cached !== undefined) return cached;
  const times = coords.map((c) => (c.timestamp ? Date.parse(c.timestamp) : NaN)).filter((t) => !Number.isNaN(t));
  if (times.length < 2 || coords.length === 0) return null;
  const from = Math.min(...times);
  const to = Math.max(...times);
  const params = new URLSearchParams({
    latitude: coords[0].latitude.toFixed(3),
    longitude: coords[0].longitude.toFixed(3),
    start_date: day(from),
    end_date: day(to),
    hourly: "temperature_2m,precipitation",
    timezone: "GMT",
  });
  const response = await fetch(`${ENDPOINT}?${params}`, { signal });
  if (!response.ok) throw new Error(`Weather archive answered ${response.status}`);
  const hourly = ((await response.json()) as { hourly?: Hourly }).hourly;
  const summary = hourly ? summarizeWalkWeather(hourly, from, to) : null;
  // A day the archive has not caught up with yet comes back empty: do not remember that.
  if (summary) writeCache(trailId, summary);
  return summary;
}
