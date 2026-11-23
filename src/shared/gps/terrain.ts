import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

/**
 * Terrain elevation from Open-Meteo's elevation API (https://open-meteo.com/en/docs/elevation-api,
 * a 90 m terrain model, free and without a key). A phone's GPS altitude is noisy, the terrain
 * model is smooth, so it gives a more believable climb. Only coordinates are sent.
 */
const ENDPOINT = "https://api.open-meteo.com/v1/elevation";
/** The API takes up to 100 coordinates per request. */
const BATCH = 100;
/** The terrain model is 90 m wide, so asking more often than every ~75 m says nothing new. */
const MAX_SAMPLES = 400;

/** `count` indices spread evenly over `0 … n-1`, always including the first and the last. */
export function sampleIndices(n: number, count: number): number[] {
  if (n <= 0) return [];
  if (n <= count) return Array.from({ length: n }, (_, i) => i);
  return Array.from({ length: count }, (_, i) => Math.round((i * (n - 1)) / (count - 1)));
}

/** Values known at some indices, spread to every index in between by straight lines. */
export function interpolateByIndex(indices: number[], values: number[], n: number): number[] {
  const out = new Array<number>(n);
  let k = 0;
  for (let i = 0; i < n; i++) {
    while (k + 1 < indices.length && indices[k + 1] <= i) k++;
    if (k + 1 >= indices.length || i <= indices[k]) {
      out[i] = values[Math.min(k, values.length - 1)];
    } else {
      const f = (i - indices[k]) / (indices[k + 1] - indices[k]);
      out[i] = values[k] + (values[k + 1] - values[k]) * f;
    }
  }
  return out;
}

/** One terrain elevation, in meters, for every coordinate. Throws when the service cannot be reached. */
export async function fetchTerrainElevations(coords: GpsCoordinate[], signal?: AbortSignal): Promise<number[]> {
  const indices = sampleIndices(coords.length, MAX_SAMPLES);
  const elevations: number[] = [];
  for (let i = 0; i < indices.length; i += BATCH) {
    const chunk = indices.slice(i, i + BATCH).map((idx) => coords[idx]);
    const params = new URLSearchParams({
      latitude: chunk.map((c) => c.latitude.toFixed(5)).join(","),
      longitude: chunk.map((c) => c.longitude.toFixed(5)).join(","),
    });
    const response = await fetch(`${ENDPOINT}?${params}`, { signal });
    if (!response.ok) throw new Error(`Elevation service answered ${response.status}`);
    const body = (await response.json()) as { elevation?: number[] };
    if (!body.elevation || body.elevation.length !== chunk.length) throw new Error("Elevation service sent no data");
    elevations.push(...body.elevation);
  }
  return interpolateByIndex(indices, elevations, coords.length);
}
