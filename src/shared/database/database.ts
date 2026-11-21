import Database from "@tauri-apps/plugin-sql";

/** Must match DB_URL in src-tauri/src/lib.rs, which is where migrations are registered. */
const DB_URL = "sqlite:pania.db";

let connection: Promise<Database> | null = null;

/** Returns the shared SQLite connection, opening it (and running pending migrations) on first use. */
export function getDatabase(): Promise<Database> {
  if (!connection) {
    connection = Database.load(DB_URL).then(async (db) => {
      await db.execute("PRAGMA foreign_keys = ON");
      return db;
    });
    // Allow a retry if opening failed.
    connection.catch(() => {
      connection = null;
    });
  }
  return connection;
}
