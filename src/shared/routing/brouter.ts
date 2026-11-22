import { t } from "../i18n/i18n";
import type { GpsCoordinate } from "../../lib/trail/interfaces/gps_coordinate";

/**
 * Client for the public BRouter server (https://brouter.de), an OpenStreetMap router with
 * elevation data. No API key is needed; the checkpoints' coordinates are sent to the server.
 */
const ENDPOINT = "https://brouter.de/brouter";

/**
 * BRouter routing profiles used by the planner.
 * - `hiking-mountain` prefers marked footpaths and avoids roads where it can.
 * - `shortest` takes the shortest legal walking line, roads included.
 */
export type RoutingProfile = "hiking-mountain" | "shortest";

/** A stretch of the route along one OSM way, with that way's tags (highway, sac_scale, …). */
export interface WaySegment {
  distanceM: number;
  tags: Record<string, string>;
}

export interface RoutedPath {
  coordinates: GpsCoordinate[];
  segments: WaySegment[];
}

interface BRouterFeature {
  geometry: { coordinates: [number, number, number?][] };
  properties: { messages?: string[][] };
}

function parseTags(text: string): Record<string, string> {
  const tags: Record<string, string> = {};
  for (const pair of text.split(" ")) {
    const eq = pair.indexOf("=");
    if (eq > 0) tags[pair.slice(0, eq)] = pair.slice(eq + 1);
  }
  return tags;
}

/** BRouter's `messages` table: a header row, then one row per way segment. */
function parseSegments(messages: string[][] = []): WaySegment[] {
  const [header, ...rows] = messages;
  if (!header) return [];
  const distance = header.indexOf("Distance");
  const wayTags = header.indexOf("WayTags");
  return rows.map((row) => ({
    distanceM: Number(row[distance]) || 0,
    tags: parseTags(row[wayTags] ?? ""),
  }));
}

function friendlyError(status: number, body: string): Error {
  if (/not mapped|no track found|target island/i.test(body)) return new Error(t("plan.error.noPath"));
  if (/distance|too long|limit/i.test(body)) return new Error(t("plan.error.tooLong"));
  return new Error(t("plan.error.server", { status }));
}

/** Routes through `points` in order. Rejects with a user-facing Error. */
export async function fetchRoute(
  points: GpsCoordinate[],
  profile: RoutingProfile,
  alternative: number,
  signal?: AbortSignal,
): Promise<RoutedPath> {
  const lonlats = points.map((p) => `${p.longitude.toFixed(6)},${p.latitude.toFixed(6)}`).join("|");
  const url = `${ENDPOINT}?lonlats=${lonlats}&profile=${profile}&alternativeidx=${alternative}&format=geojson`;

  let response: Response;
  try {
    response = await fetch(url, { signal });
  } catch (e) {
    if (signal?.aborted) throw e;
    throw new Error(t("plan.error.offline"));
  }
  if (!response.ok) throw friendlyError(response.status, await response.text());

  const json = (await response.json()) as { features?: BRouterFeature[] };
  const feature = json.features?.[0];
  if (!feature) throw new Error(t("plan.error.noPath"));
  return {
    coordinates: feature.geometry.coordinates.map(([longitude, latitude, altitude]) => ({
      latitude,
      longitude,
      ...(altitude !== undefined && { altitude }),
    })),
    segments: parseSegments(feature.properties.messages),
  };
}
