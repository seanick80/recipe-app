/**
 * expo-sqlite connection + migration bootstrap.
 *
 * A single shared connection is opened lazily and memoised. WAL mode is enabled
 * for concurrent read performance and `foreign_keys` is turned on so the
 * `ingredients` cascade actually fires. Migrations are driven by
 * `PRAGMA user_version` against {@link SCHEMA_VERSION}.
 */
import * as SQLite from 'expo-sqlite';

import { CREATE_SQL, GROCERY_SQL, SCHEMA_VERSION } from './schema';

const DB_NAME = 'recipes.db';

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

/** Open (once) and return the shared database, running migrations on first open. */
export function getDatabase(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = openAndMigrate();
  }
  return dbPromise;
}

async function openAndMigrate(): Promise<SQLite.SQLiteDatabase> {
  const db = await SQLite.openDatabaseAsync(DB_NAME);
  await db.execAsync('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');

  const row = await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version');
  const current = row?.user_version ?? 0;

  if (current < SCHEMA_VERSION) {
    // Incremental, idempotent steps (all guarded by IF NOT EXISTS).
    if (current < 1) await db.execAsync(CREATE_SQL); // v1: recipes + ingredients
    if (current < 2) await db.execAsync(GROCERY_SQL); // v2: shopping + grocery
    await db.execAsync(`PRAGMA user_version = ${SCHEMA_VERSION}`);
  }

  return db;
}

/** Test/hot-reload helper: drop the memoised connection so the next call reopens. */
export function resetDatabaseHandle(): void {
  dbPromise = null;
}
