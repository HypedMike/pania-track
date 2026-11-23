import type { Fix, PaceProfile } from "../../shared/analysis/analysis_api";
import { getDatabase } from "../../shared/database/database";

/** A tour that was followed: the plan made at the start, and (separately) the GPS fixes recorded. */
export interface TourRun {
  id: string;
  trailId: string;
  /** Milliseconds since the epoch. */
  startedAt: number;
  endedAt: number | null;
  /** Constant speed the plan assumed, m/s. */
  plannedSpeedMs: number;
  /** The slope-aware plan, when the person had enough recordings to build one. */
  planProfile: PaceProfile | null;
  targetArrivalMs: number | null;
  /** The person got to the end of the trail. */
  finished: boolean;
}

interface RunRow {
  id: string;
  trail_id: string;
  started_at: string;
  ended_at: string | null;
  planned_speed_ms: number;
  plan_profile: string | null;
  target_arrival: string | null;
  finished: number;
}

interface FixRow {
  latitude: number;
  longitude: number;
  altitude: number | null;
  time_ms: number;
  accuracy: number | null;
}

const RUN_COLUMNS = "id, trail_id, started_at, ended_at, planned_speed_ms, plan_profile, target_arrival, finished";
// SQLite caps bound variables per statement, so fixes are inserted in chunks.
const FIX_CHUNK = 100;
const FIX_COLUMNS = 6;

function parseProfile(json: string | null): PaceProfile | null {
  if (!json) return null;
  try {
    return JSON.parse(json) as PaceProfile;
  } catch {
    return null;
  }
}

function toRun(row: RunRow): TourRun {
  return {
    id: row.id,
    trailId: row.trail_id,
    startedAt: Date.parse(row.started_at),
    endedAt: row.ended_at ? Date.parse(row.ended_at) : null,
    plannedSpeedMs: row.planned_speed_ms,
    planProfile: parseProfile(row.plan_profile),
    targetArrivalMs: row.target_arrival ? Date.parse(row.target_arrival) : null,
    finished: row.finished === 1,
  };
}

export const tourRunRepository = {
  async create(run: TourRun): Promise<void> {
    const db = await getDatabase();
    await db.execute(
      `INSERT INTO tour_runs (id, trail_id, started_at, planned_speed_ms, plan_profile, target_arrival)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        run.id,
        run.trailId,
        new Date(run.startedAt).toISOString(),
        run.plannedSpeedMs,
        run.planProfile ? JSON.stringify(run.planProfile) : null,
        run.targetArrivalMs ? new Date(run.targetArrivalMs).toISOString() : null,
      ],
    );
  },

  async get(id: string): Promise<TourRun | null> {
    const db = await getDatabase();
    const rows = await db.select<RunRow[]>(`SELECT ${RUN_COLUMNS} FROM tour_runs WHERE id = $1`, [id]);
    return rows.length === 0 ? null : toRun(rows[0]);
  },

  async listForTrail(trailId: string): Promise<TourRun[]> {
    const db = await getDatabase();
    const rows = await db.select<RunRow[]>(
      `SELECT ${RUN_COLUMNS} FROM tour_runs WHERE trail_id = $1 ORDER BY started_at DESC`,
      [trailId],
    );
    return rows.map(toRun);
  },

  /** Adds fixes after the ones already stored. */
  async appendFixes(runId: string, fixes: Fix[]): Promise<void> {
    if (fixes.length === 0) return;
    const db = await getDatabase();
    const counted = await db.select<{ n: number }[]>("SELECT COUNT(*) AS n FROM tour_run_fixes WHERE run_id = $1", [runId]);
    const first = counted[0]?.n ?? 0;
    for (let i = 0; i < fixes.length; i += FIX_CHUNK) {
      const chunk = fixes.slice(i, i + FIX_CHUNK);
      const placeholders = chunk
        .map((_, j) => {
          const p = (k: number) => `$${j * FIX_COLUMNS + k}`;
          return `($1, ${p(2)}, ${p(3)}, ${p(4)}, ${p(5)}, ${p(6)}, ${p(7)})`;
        })
        .join(", ");
      const values = chunk.flatMap((f, j) => [
        first + i + j,
        f.latitude,
        f.longitude,
        f.altitude ?? null,
        f.timeMs ?? 0,
        f.accuracy ?? null,
      ]);
      await db.execute(
        `INSERT INTO tour_run_fixes (run_id, position, latitude, longitude, altitude, time_ms, accuracy) VALUES ${placeholders}`,
        [runId, ...values],
      );
    }
  },

  async getFixes(runId: string): Promise<Fix[]> {
    const db = await getDatabase();
    const rows = await db.select<FixRow[]>(
      "SELECT latitude, longitude, altitude, time_ms, accuracy FROM tour_run_fixes WHERE run_id = $1 ORDER BY position",
      [runId],
    );
    return rows.map((r) => ({
      latitude: r.latitude,
      longitude: r.longitude,
      ...(r.altitude !== null && { altitude: r.altitude }),
      timeMs: r.time_ms,
      ...(r.accuracy !== null && { accuracy: r.accuracy }),
    }));
  },

  async countFixes(runId: string): Promise<number> {
    const db = await getDatabase();
    const rows = await db.select<{ n: number }[]>("SELECT COUNT(*) AS n FROM tour_run_fixes WHERE run_id = $1", [runId]);
    return rows[0]?.n ?? 0;
  },

  async end(runId: string, finished: boolean): Promise<void> {
    const db = await getDatabase();
    await db.execute("UPDATE tour_runs SET ended_at = $2, finished = $3 WHERE id = $1", [
      runId,
      new Date().toISOString(),
      finished ? 1 : 0,
    ]);
  },

  async remove(id: string): Promise<void> {
    const db = await getDatabase();
    await db.execute("DELETE FROM tour_runs WHERE id = $1", [id]);
  },
};
