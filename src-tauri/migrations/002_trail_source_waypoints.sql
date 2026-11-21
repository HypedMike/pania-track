ALTER TABLE trails ADD COLUMN source TEXT NOT NULL DEFAULT 'recorded';

CREATE TABLE trail_waypoints (
    trail_id  TEXT NOT NULL REFERENCES trails(id) ON DELETE CASCADE,
    position  INTEGER NOT NULL,
    latitude  REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude  REAL,
    name      TEXT NOT NULL DEFAULT '',
    timestamp TEXT,
    PRIMARY KEY (trail_id, position)
);
