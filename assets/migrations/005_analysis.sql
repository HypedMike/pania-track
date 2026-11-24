-- GPS accuracy (meters) of each recorded point, so the quality of a recording can be judged
-- later. Null for imported trails and for recordings made before this was kept.
ALTER TABLE trail_coordinates ADD COLUMN accuracy REAL;

-- Tours that were followed, for looking back at them: the plan made at the start and what
-- the GPS recorded along the way.
CREATE TABLE tour_runs (
    id               TEXT PRIMARY KEY NOT NULL,
    trail_id         TEXT NOT NULL REFERENCES trails(id) ON DELETE CASCADE,
    started_at       TEXT NOT NULL,
    ended_at         TEXT,
    -- Constant speed the plan assumed (m/s), and the slope-aware plan (JSON: { stepM, totalM, seconds }).
    planned_speed_ms REAL NOT NULL,
    plan_profile     TEXT,
    target_arrival   TEXT,
    -- 1 when the person got to the end of the trail.
    finished         INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX tour_runs_trail ON tour_runs (trail_id, started_at);

CREATE TABLE tour_run_fixes (
    run_id    TEXT NOT NULL REFERENCES tour_runs(id) ON DELETE CASCADE,
    position  INTEGER NOT NULL,
    latitude  REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude  REAL,
    time_ms   INTEGER NOT NULL,
    accuracy  REAL,
    PRIMARY KEY (run_id, position)
);
