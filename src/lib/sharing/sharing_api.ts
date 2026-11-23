import { invoke } from "@tauri-apps/api/core";
import type { SimplifyReport } from "../../shared/gps/simplify_track";
import type { GpsCoordinate } from "../trail/interfaces/gps_coordinate";
import type { Trail, TrailActivity, Waypoint } from "../trail/interfaces/trail";

export type Difficulty = "easy" | "moderate" | "hard";
export const DIFFICULTIES: Difficulty[] = ["easy", "moderate", "hard"];

/** The author's own account of how faithful the published line is. Not verified. */
export interface Fidelity {
  originalPoints: number | null;
  points: number | null;
  removedPct: number | null;
  toleranceM: number | null;
  maxErrorM: number | null;
  p95ErrorM: number | null;
}

/** A trail somebody shared, as read from relays and checked by the Rust backend. */
export interface SharedTrail {
  eventId: string;
  authorPubkey: string;
  authorNpub: string;
  authorName: string | null;
  dTag: string;
  name: string;
  description: string;
  activity: TrailActivity;
  /** Distance, climb and difficulty are recomputed from the track, not taken from the author. */
  difficulty: Difficulty;
  distanceM: number;
  gainM: number | null;
  createdAt: number;
  coordinates: GpsCoordinate[];
  waypoints: Waypoint[];
  fidelity: Fidelity;
  /** Distance from the searched point to the trail's start. */
  awayKm: number;
}

export interface ShareResult {
  eventId: string;
  dTag: string;
  report: SimplifyReport;
  difficulty: Difficulty;
  contentBytes: number;
  relaysOk: string[];
  relaysFailed: [string, string][];
}

export interface ExploreQuery {
  lat: number;
  lon: number;
  radiusKm: number;
  minLengthKm?: number;
  maxLengthKm?: number;
  activity?: TrailActivity;
  /** Empty means any difficulty. */
  difficulty: Difficulty[];
}

/** Rust commands reject with plain strings. */
export function errorText(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Rust sends missing altitudes as absent; make sure nothing `null` reaches the stats code. */
function clean(c: GpsCoordinate): GpsCoordinate {
  return {
    latitude: c.latitude,
    longitude: c.longitude,
    ...(c.altitude != null && { altitude: c.altitude }),
  };
}

/**
 * Sharing and exploring trails over Nostr. Everything happens in the Rust backend
 * (`src-tauri/src/sharing`): building and signing events, talking to relays, validating what
 * comes back.
 */
export const sharingApi = {
  relays: {
    list: () => invoke<string[]>("relays_list"),
    add: (url: string) => invoke<string[]>("relays_add", { url }),
    remove: (url: string) => invoke<string[]>("relays_remove", { url }),
    reset: () => invoke<string[]>("relays_reset"),
  },

  /** Publishes a trail, signed with the user's key. Timestamps never leave the device. */
  shareTrail(trail: Trail, authorName?: string): Promise<ShareResult> {
    return invoke<ShareResult>("share_trail", {
      trail: {
        id: trail.id,
        name: trail.name,
        description: trail.description ?? "",
        activity: trail.activity,
        coordinates: trail.coordinates.map(clean),
        waypoints: trail.waypoints.map((w) => ({ ...clean(w), name: w.name })),
        authorName,
      },
    });
  },

  /** Asks relays to delete a shared trail. Returns the relays that took the request. */
  unshareTrail: (trailId: string) => invoke<string[]>("unshare_trail", { trailId }),

  async explore(query: ExploreQuery): Promise<SharedTrail[]> {
    const trails = await invoke<SharedTrail[]>("explore_trails", { query });
    return trails.map((t) => ({
      ...t,
      coordinates: t.coordinates.map(clean),
      waypoints: t.waypoints.map((w) => ({ ...clean(w), name: w.name })),
    }));
  },
};
