import { getDatabase } from "../../../shared/database/database";
import { Trail } from "../interfaces/trail";
import { GpsCoordinate } from "../interfaces/gps_coordinate";

interface TrailRow {
  id: string;
  name: string;
  description: string;
}

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

// SQLite caps bound variables per statement, so coordinates are inserted in chunks.
const COORDINATE_CHUNK = 100;

export const trailRepository = {
  async getAll(): Promise<Trail[]> {
    const db = await getDatabase();
    const rows = await db.select<TrailRow[]>(
      "SELECT id, name, description FROM trails ORDER BY created_at DESC",
    );
    return Promise.all(
      rows.map(async (row) => ({ ...row, coordinates: await loadCoordinates(row.id) })),
    );
  },

  async getById(id: string): Promise<Trail | null> {
    const db = await getDatabase();
    const rows = await db.select<TrailRow[]>(
      "SELECT id, name, description FROM trails WHERE id = $1",
      [id],
    );
    if (rows.length === 0) return null;
    return { ...rows[0], coordinates: await loadCoordinates(id) };
  },

  /**
   * Inserts the trail, or updates it (replacing its coordinates) if the id already exists.
   * The plugin's connection pool doesn't expose transactions, so this is not atomic.
   */
  async save(trail: Trail): Promise<void> {
    const db = await getDatabase();
    await db.execute(
      `INSERT INTO trails (id, name, description) VALUES ($1, $2, $3)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         description = excluded.description,
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      [trail.id, trail.name, trail.description ?? ""],
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
  },

  async remove(id: string): Promise<void> {
    const db = await getDatabase();
    await db.execute("DELETE FROM trails WHERE id = $1", [id]);
  },
};
