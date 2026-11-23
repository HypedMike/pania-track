import { GpsCoordinate } from "./gps_coordinate";

/**
 * Planned trails are drawn from checkpoints in the planner; they haven't been walked yet.
 * Bookmarked trails were saved from another person's shared trail (see `Trail.author`).
 */
export type TrailSource = "recorded" | "imported" | "planned" | "bookmarked";

/** How the trail was (or is being) covered. */
export type TrailActivity = "foot" | "bike";

/** A named point of interest along a trail. */
export interface Waypoint extends GpsCoordinate {
  name: string;
}

/** Who made a bookmarked trail. Kept with the saved copy, even if the original disappears. */
export interface TrailAuthor {
  /** Public key, hex. */
  pubkey: string;
  npub: string;
  name?: string;
  /** The trail's id on Nostr; with `pubkey` it identifies the original. */
  dTag: string;
  /** The Nostr event this copy was saved from. */
  eventId: string;
}

export interface Trail {
  id: string;
  name: string;
  description?: string;
  source: TrailSource;
  activity: TrailActivity;
  /** Ordered points that make up the trail path. */
  coordinates: GpsCoordinate[];
  waypoints: Waypoint[];
  /** Creation time, in milliseconds since the epoch. */
  createdAt?: number;
  updatedAt?: number;
  /** Set on trails saved from someone else (`source` is "bookmarked"). */
  author?: TrailAuthor;
  /** When this trail was last published to Nostr, and the event that carries it. */
  sharedAt?: number;
  sharedEventId?: string;
}
