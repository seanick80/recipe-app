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
export const SCHEMA_VERSION = 3;

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

/**
 * Schema v2/v3 — Shopping + Grocery tables. Phase 4 shipped these local-only; the
 * grocery-sync work (Phase B) added the same per-record sync metadata the
 * `recipes` table carries (server_id + needs_sync + last_synced_at +
 * locally_deleted + pending_remote_delete + deleted_at, plus updated_at as the
 * parents' server-`updated_at` watermark mirror). The columns exist on all four
 * tables for a uniform migration; the sync layer meaningfully uses server_id on
 * `grocery_items` and the full set on the two parent tables (`grocery_lists`,
 * `shopping_templates`). Fresh installs get the columns inline here; existing v2
 * databases are upgraded by {@link MIGRATE_V3_SQL}.
 */
export const GROCERY_SQL = `
CREATE TABLE IF NOT EXISTS grocery_lists (
  id                    TEXT PRIMARY KEY NOT NULL,
  name                  TEXT NOT NULL DEFAULT '',
  created_at            TEXT NOT NULL,
  updated_at            TEXT,
  archived_at           TEXT,
  server_id             TEXT UNIQUE,
  needs_sync            INTEGER NOT NULL DEFAULT 0,
  last_synced_at        TEXT,
  locally_deleted       INTEGER NOT NULL DEFAULT 0,
  pending_remote_delete INTEGER NOT NULL DEFAULT 0,
  deleted_at            TEXT
);

CREATE TABLE IF NOT EXISTS grocery_items (
  id                    TEXT PRIMARY KEY NOT NULL,
  list_id               TEXT NOT NULL REFERENCES grocery_lists(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL DEFAULT '',
  quantity              REAL NOT NULL DEFAULT 1,
  unit                  TEXT NOT NULL DEFAULT '',
  category              TEXT NOT NULL DEFAULT 'Other',
  is_checked            INTEGER NOT NULL DEFAULT 0,
  source_recipe_name    TEXT NOT NULL DEFAULT '',
  source_recipe_id      TEXT NOT NULL DEFAULT '',
  server_id             TEXT,
  needs_sync            INTEGER NOT NULL DEFAULT 0,
  last_synced_at        TEXT,
  locally_deleted       INTEGER NOT NULL DEFAULT 0,
  pending_remote_delete INTEGER NOT NULL DEFAULT 0,
  deleted_at            TEXT
);

CREATE TABLE IF NOT EXISTS shopping_templates (
  id                    TEXT PRIMARY KEY NOT NULL,
  name                  TEXT NOT NULL DEFAULT '',
  sort_order            INTEGER NOT NULL DEFAULT 0,
  created_at            TEXT NOT NULL,
  updated_at            TEXT,
  server_id             TEXT UNIQUE,
  needs_sync            INTEGER NOT NULL DEFAULT 0,
  last_synced_at        TEXT,
  locally_deleted       INTEGER NOT NULL DEFAULT 0,
  pending_remote_delete INTEGER NOT NULL DEFAULT 0,
  deleted_at            TEXT
);

CREATE TABLE IF NOT EXISTS template_items (
  id                    TEXT PRIMARY KEY NOT NULL,
  template_id           TEXT NOT NULL REFERENCES shopping_templates(id) ON DELETE CASCADE,
  name                  TEXT NOT NULL DEFAULT '',
  quantity              REAL NOT NULL DEFAULT 1,
  unit                  TEXT NOT NULL DEFAULT '',
  category              TEXT NOT NULL DEFAULT 'Other',
  sort_order            INTEGER NOT NULL DEFAULT 0,
  server_id             TEXT,
  needs_sync            INTEGER NOT NULL DEFAULT 0,
  last_synced_at        TEXT,
  locally_deleted       INTEGER NOT NULL DEFAULT 0,
  pending_remote_delete INTEGER NOT NULL DEFAULT 0,
  deleted_at            TEXT
);

CREATE INDEX IF NOT EXISTS idx_grocery_items_list ON grocery_items(list_id);
CREATE INDEX IF NOT EXISTS idx_template_items_template ON template_items(template_id);
CREATE INDEX IF NOT EXISTS idx_grocery_lists_server_id ON grocery_lists(server_id);
CREATE INDEX IF NOT EXISTS idx_shopping_templates_server_id ON shopping_templates(server_id);
`;

/**
 * v2 → v3 migration: add the grocery-sync metadata columns to the four
 * pre-existing (local-only) grocery tables and seed `updated_at` from
 * `created_at` for existing parent rows. SQLite `ADD COLUMN` is non-destructive,
 * so local rows are preserved. Idempotent-by-version (guarded by user_version).
 */
export const MIGRATE_V3_SQL = `
ALTER TABLE grocery_lists ADD COLUMN updated_at TEXT;
ALTER TABLE grocery_lists ADD COLUMN server_id TEXT;
ALTER TABLE grocery_lists ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_lists ADD COLUMN last_synced_at TEXT;
ALTER TABLE grocery_lists ADD COLUMN locally_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_lists ADD COLUMN pending_remote_delete INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_lists ADD COLUMN deleted_at TEXT;
UPDATE grocery_lists SET updated_at = created_at WHERE updated_at IS NULL;

ALTER TABLE grocery_items ADD COLUMN server_id TEXT;
ALTER TABLE grocery_items ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_items ADD COLUMN last_synced_at TEXT;
ALTER TABLE grocery_items ADD COLUMN locally_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_items ADD COLUMN pending_remote_delete INTEGER NOT NULL DEFAULT 0;
ALTER TABLE grocery_items ADD COLUMN deleted_at TEXT;

ALTER TABLE shopping_templates ADD COLUMN updated_at TEXT;
ALTER TABLE shopping_templates ADD COLUMN server_id TEXT;
ALTER TABLE shopping_templates ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 0;
ALTER TABLE shopping_templates ADD COLUMN last_synced_at TEXT;
ALTER TABLE shopping_templates ADD COLUMN locally_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE shopping_templates ADD COLUMN pending_remote_delete INTEGER NOT NULL DEFAULT 0;
ALTER TABLE shopping_templates ADD COLUMN deleted_at TEXT;
UPDATE shopping_templates SET updated_at = created_at WHERE updated_at IS NULL;

ALTER TABLE template_items ADD COLUMN server_id TEXT;
ALTER TABLE template_items ADD COLUMN needs_sync INTEGER NOT NULL DEFAULT 0;
ALTER TABLE template_items ADD COLUMN last_synced_at TEXT;
ALTER TABLE template_items ADD COLUMN locally_deleted INTEGER NOT NULL DEFAULT 0;
ALTER TABLE template_items ADD COLUMN pending_remote_delete INTEGER NOT NULL DEFAULT 0;
ALTER TABLE template_items ADD COLUMN deleted_at TEXT;

CREATE INDEX IF NOT EXISTS idx_grocery_lists_server_id ON grocery_lists(server_id);
CREATE INDEX IF NOT EXISTS idx_shopping_templates_server_id ON shopping_templates(server_id);
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
