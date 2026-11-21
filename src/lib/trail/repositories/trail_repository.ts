import { getDatabase } from "../../../shared/database/database";
import { Trail, TrailSource, Waypoint } from "../interfaces/trail";
import { GpsCoordinate } from "../interfaces/gps_coordinate";

interface TrailRow {
  id: string;
  name: string;
  description: string;
  source: TrailSource;
  created_at: string;
  updated_at: string;
}

interface WaypointRow extends CoordinateRow {
  name: string;
}

const TRAIL_COLUMNS = "id, name, description, source, created_at, updated_at";

interface CoordinateRow {
  latitude: number;
  longitude: number;
  altitude: number | null;
  timestamp: string | null;
}

function toCoordinate(row: CoordinateRow): GpsCoordinate {
  return {
    latitude: row.latitude,
    longitude: row.longitude,
    ...(row.altitude !== null && { altitude: row.altitude }),
    ...(row.timestamp !== null && { timestamp: row.timestamp }),
  };
}

async function loadCoordinates(trailId: string): Promise<GpsCoordinate[]> {
  const db = await getDatabase();
  const rows = await db.select<CoordinateRow[]>(
    "SELECT latitude, longitude, altitude, timestamp FROM trail_coordinates WHERE trail_id = $1 ORDER BY position",
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

async function hydrate(row: TrailRow): Promise<Trail> {
  const [coordinates, waypoints] = await Promise.all([loadCoordinates(row.id), loadWaypoints(row.id)]);
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    source: row.source,
    createdAt: Date.parse(row.created_at),
    updatedAt: Date.parse(row.updated_at),
    coordinates,
    waypoints,
  };
}

// SQLite caps bound variables per statement, so coordinates are inserted in chunks.
const COORDINATE_CHUNK = 100;

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
      `INSERT INTO trails (id, name, description, source) VALUES ($1, $2, $3, $4)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         description = excluded.description,
         source = excluded.source,
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      [trail.id, trail.name, trail.description ?? "", trail.source],
    );
    await db.execute("DELETE FROM trail_coordinates WHERE trail_id = $1", [trail.id]);

    for (let i = 0; i < trail.coordinates.length; i += COORDINATE_CHUNK) {
      const chunk = trail.coordinates.slice(i, i + COORDINATE_CHUNK);
      const placeholders = chunk
        .map((_, j) => `($1, $${j * 5 + 2}, $${j * 5 + 3}, $${j * 5 + 4}, $${j * 5 + 5}, $${j * 5 + 6})`)
        .join(", ");
      const values = chunk.flatMap((c, j) => [
        i + j,
        c.latitude,
        c.longitude,
        c.altitude ?? null,
        c.timestamp ?? null,
      ]);
      await db.execute(
        `INSERT INTO trail_coordinates (trail_id, position, latitude, longitude, altitude, timestamp) VALUES ${placeholders}`,
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
