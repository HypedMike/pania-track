import { getDatabase } from "../../../shared/database/database";
import { Trail, TrailActivity, TrailAuthor, TrailSource, Waypoint } from "../interfaces/trail";
import { GpsCoordinate } from "../interfaces/gps_coordinate";

interface TrailRow {
  id: string;
  name: string;
  description: string;
  source: TrailSource;
  activity: TrailActivity;
  created_at: string;
  updated_at: string;
  author_pubkey: string | null;
  author_npub: string | null;
  author_name: string | null;
  author_d_tag: string | null;
  author_event_id: string | null;
  shared_at: string | null;
  shared_event_id: string | null;
}

interface WaypointRow extends CoordinateRow {
  name: string;
}

const TRAIL_COLUMNS =
  "id, name, description, source, activity, created_at, updated_at, author_pubkey, author_npub, author_name, author_d_tag, author_event_id, shared_at, shared_event_id";

interface CoordinateRow {
  latitude: number;
  longitude: number;
  altitude: number | null;
  timestamp: string | null;
  accuracy?: number | null;
}

function toCoordinate(row: CoordinateRow): GpsCoordinate {
  return {
    latitude: row.latitude,
    longitude: row.longitude,
    ...(row.altitude !== null && { altitude: row.altitude }),
    ...(row.timestamp !== null && { timestamp: row.timestamp }),
    ...(row.accuracy != null && { accuracy: row.accuracy }),
  };
}

async function loadCoordinates(trailId: string): Promise<GpsCoordinate[]> {
  const db = await getDatabase();
  const rows = await db.select<CoordinateRow[]>(
    "SELECT latitude, longitude, altitude, timestamp, accuracy FROM trail_coordinates WHERE trail_id = $1 ORDER BY position",
    [trailId],
  );
  return rows.map(toCoordinate);
}

async function loadWaypoints(trailId: string): Promise<Waypoint[]> {
  const db = await getDatabase();
  const rows = await db.select<WaypointRow[]>(
    "SELECT latitude, longitude, altitude, name, timestamp FROM trail_waypoints WHERE trail_id = $1 ORDER BY position",
    [trailId],
  );
  return rows.map((row) => ({ ...toCoordinate(row), name: row.name }));
}

function toAuthor(row: TrailRow): TrailAuthor | undefined {
  if (!row.author_pubkey || !row.author_npub || !row.author_d_tag) return undefined;
  return {
    pubkey: row.author_pubkey,
    npub: row.author_npub,
    ...(row.author_name && { name: row.author_name }),
    dTag: row.author_d_tag,
    eventId: row.author_event_id ?? "",
  };
}

async function hydrate(row: TrailRow): Promise<Trail> {
  const [coordinates, waypoints] = await Promise.all([loadCoordinates(row.id), loadWaypoints(row.id)]);
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    source: row.source,
    activity: row.activity,
    createdAt: Date.parse(row.created_at),
    updatedAt: Date.parse(row.updated_at),
    coordinates,
    waypoints,
    author: toAuthor(row),
    ...(row.shared_at && { sharedAt: Date.parse(row.shared_at) }),
    ...(row.shared_event_id && { sharedEventId: row.shared_event_id }),
  };
}

// SQLite caps bound variables per statement, so coordinates are inserted in chunks.
const COORDINATE_CHUNK = 100;
/** Bound values per coordinate row: position, latitude, longitude, altitude, timestamp, accuracy. */
const COORDINATE_COLUMNS = 6;

export const trailRepository = {
  async getAll(): Promise<Trail[]> {
    const db = await getDatabase();
    const rows = await db.select<TrailRow[]>(
      `SELECT ${TRAIL_COLUMNS} FROM trails ORDER BY created_at DESC`,
    );
    return Promise.all(rows.map(hydrate));
  },

  async getById(id: string): Promise<Trail | null> {
    const db = await getDatabase();
    const rows = await db.select<TrailRow[]>(
      `SELECT ${TRAIL_COLUMNS} FROM trails WHERE id = $1`,
      [id],
    );
    return rows.length === 0 ? null : hydrate(rows[0]);
  },

  /**
   * Inserts the trail, or updates it (replacing its coordinates) if the id already exists.
   * The plugin's connection pool doesn't expose transactions, so this is not atomic.
   */
  async save(trail: Trail): Promise<void> {
    const db = await getDatabase();
    await db.execute(
      `INSERT INTO trails (id, name, description, source, activity,
         author_pubkey, author_npub, author_name, author_d_tag, author_event_id, shared_at, shared_event_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         description = excluded.description,
         source = excluded.source,
         activity = excluded.activity,
         author_pubkey = excluded.author_pubkey,
         author_npub = excluded.author_npub,
         author_name = excluded.author_name,
         author_d_tag = excluded.author_d_tag,
         author_event_id = excluded.author_event_id,
         shared_at = excluded.shared_at,
         shared_event_id = excluded.shared_event_id,
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      [
        trail.id,
        trail.name,
        trail.description ?? "",
        trail.source,
        trail.activity,
        trail.author?.pubkey ?? null,
        trail.author?.npub ?? null,
        trail.author?.name ?? null,
        trail.author?.dTag ?? null,
        trail.author?.eventId ?? null,
        trail.sharedAt ? new Date(trail.sharedAt).toISOString() : null,
        trail.sharedEventId ?? null,
      ],
    );
    await db.execute("DELETE FROM trail_coordinates WHERE trail_id = $1", [trail.id]);

    for (let i = 0; i < trail.coordinates.length; i += COORDINATE_CHUNK) {
      const chunk = trail.coordinates.slice(i, i + COORDINATE_CHUNK);
      const placeholders = chunk
        .map((_, j) => {
          const p = (k: number) => `$${j * COORDINATE_COLUMNS + k}`;
          return `($1, ${p(2)}, ${p(3)}, ${p(4)}, ${p(5)}, ${p(6)}, ${p(7)})`;
        })
        .join(", ");
      const values = chunk.flatMap((c, j) => [
        i + j,
        c.latitude,
        c.longitude,
        c.altitude ?? null,
        c.timestamp ?? null,
        c.accuracy ?? null,
      ]);
      await db.execute(
        `INSERT INTO trail_coordinates (trail_id, position, latitude, longitude, altitude, timestamp, accuracy) VALUES ${placeholders}`,
        [trail.id, ...values],
      );
    }

    await db.execute("DELETE FROM trail_waypoints WHERE trail_id = $1", [trail.id]);
    for (const [i, w] of trail.waypoints.entries()) {
      await db.execute(
        `INSERT INTO trail_waypoints (trail_id, position, latitude, longitude, altitude, name, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [trail.id, i, w.latitude, w.longitude, w.altitude ?? null, w.name, w.timestamp ?? null],
      );
    }
  },

  async remove(id: string): Promise<void> {
    const db = await getDatabase();
    await db.execute("DELETE FROM trails WHERE id = $1", [id]);
  },
};
