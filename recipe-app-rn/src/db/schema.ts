/**
 * Local SQLite schema for the offline-first recipe store (Phase 3).
 *
 * Two tables: `recipes` (content + per-record sync metadata) and `ingredients`
 * (child rows, cascade-deleted). Ingredients are replaced wholesale on every
 * write (delete-all + re-insert) — the same strategy the server and the SwiftUI
 * client use, which sidesteps fragile ingredient diffing.
 *
 * `PRAGMA user_version` drives migrations: bump {@link SCHEMA_VERSION} and add a
 * step in `db/database.ts` when the schema changes.
 */
export const SCHEMA_VERSION = 1;

/** DDL run once on a fresh database (idempotent — guarded by IF NOT EXISTS). */
export const CREATE_SQL = `
CREATE TABLE IF NOT EXISTS recipes (
  local_id           TEXT PRIMARY KEY NOT NULL,
  server_id          TEXT UNIQUE,
  name               TEXT NOT NULL DEFAULT '',
  summary            TEXT NOT NULL DEFAULT '',
  instructions       TEXT NOT NULL DEFAULT '',
  prep_time_minutes  INTEGER NOT NULL DEFAULT 0,
  cook_time_minutes  INTEGER NOT NULL DEFAULT 0,
  servings           INTEGER NOT NULL DEFAULT 1,
  cuisine            TEXT NOT NULL DEFAULT '',
  course             TEXT NOT NULL DEFAULT '',
  tags               TEXT NOT NULL DEFAULT '',
  source_url         TEXT NOT NULL DEFAULT '',
  difficulty         TEXT NOT NULL DEFAULT '',
  is_favorite        INTEGER NOT NULL DEFAULT 0,
  is_published       INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  needs_sync            INTEGER NOT NULL DEFAULT 0,
  last_synced_at        TEXT,
  locally_deleted       INTEGER NOT NULL DEFAULT 0,
  pending_remote_delete INTEGER NOT NULL DEFAULT 0,
  deleted_at            TEXT,
  is_conflicted_copy    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ingredients (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  recipe_local_id TEXT NOT NULL REFERENCES recipes(local_id) ON DELETE CASCADE,
  name            TEXT NOT NULL DEFAULT '',
  quantity        REAL NOT NULL DEFAULT 0,
  unit            TEXT NOT NULL DEFAULT '',
  category        TEXT NOT NULL DEFAULT '',
  display_order   INTEGER NOT NULL DEFAULT 0,
  notes           TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_ingredients_recipe ON ingredients(recipe_local_id);
CREATE INDEX IF NOT EXISTS idx_recipes_server_id ON recipes(server_id);
`;

/** Shape of a `recipes` row as returned by expo-sqlite (before boolean coercion). */
export type RecipeRow = {
  local_id: string;
  server_id: string | null;
  name: string;
  summary: string;
  instructions: string;
  prep_time_minutes: number;
  cook_time_minutes: number;
  servings: number;
  cuisine: string;
  course: string;
  tags: string;
  source_url: string;
  difficulty: string;
  is_favorite: number;
  is_published: number;
  created_at: string;
  updated_at: string;
  needs_sync: number;
  last_synced_at: string | null;
  locally_deleted: number;
  pending_remote_delete: number;
  deleted_at: string | null;
  is_conflicted_copy: number;
};

/** Shape of an `ingredients` row. */
export type IngredientRow = {
  recipe_local_id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  display_order: number;
  notes: string;
};
