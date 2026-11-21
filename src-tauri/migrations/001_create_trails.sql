CREATE TABLE trails (
    id          TEXT PRIMARY KEY NOT NULL,
    name        TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE trail_coordinates (
    trail_id  TEXT NOT NULL REFERENCES trails(id) ON DELETE CASCADE,
    position  INTEGER NOT NULL,
    latitude  REAL NOT NULL,
    longitude REAL NOT NULL,
    altitude  REAL,
    timestamp TEXT,
    PRIMARY KEY (trail_id, position)
);
