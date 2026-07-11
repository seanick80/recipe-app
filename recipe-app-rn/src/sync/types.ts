/**
 * Local-DB + sync types for Phase 3.
 *
 * The RN app is offline-first: recipes live in a local SQLite store and the
 * server is the source of truth reconciled by {@link SyncService}. This mirrors
 * the SwiftUI app's SwiftData+CloudKit → server-sync design (see
 * `docs/sync-execution-plan.md`, the 9 sync scenarios), but the sync metadata
 * that lived as fields on the SwiftData `Recipe` model here lives on
 * {@link LocalRecipe}.
 *
 * Wire/content field names stay snake_case (matching `types/recipe.ts` and the
 * server) so a recipe round-trips through the API with no re-mapping. Sync
 * metadata is camelCase and never leaves the device.
 */
import type { Ingredient, Recipe } from '../types/recipe';

/** An ingredient as stored locally — the wire shape minus the server-assigned `id`. */
export type LocalIngredient = Omit<Ingredient, 'id'>;

/**
 * A recipe in the local store: the content fields (snake_case, wire-identical)
 * plus per-record sync metadata. `localId` is the stable local identity;
 * `serverId` is the server UUID (null until first uploaded).
 */
export type LocalRecipe = {
  /** Stable client-generated identity (UUID). Never changes. */
  localId: string;
  /** Server UUID; null = never synced (a local-only recipe). */
  serverId: string | null;

  // --- content (snake_case, identical to the server wire format) ---
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
  is_favorite: boolean;
  is_published: boolean;
  ingredients: LocalIngredient[];

  /** Server `created_at` once synced; local creation time otherwise. ISO-8601 UTC. */
  createdAt: string;
  /** Server `updated_at` once synced; local mtime otherwise. ISO-8601 UTC. */
  updatedAt: string;

  // --- sync metadata (camelCase; device-only; mirrors iOS Recipe.swift) ---
  /** Local edits not yet pushed to the server. */
  needsSync: boolean;
  /** Timestamp of the last successful sync of this record. ISO-8601 UTC, or null. */
  lastSyncedAt: string | null;
  /** Deleted from the user's view; hidden from the main list, in "Recently Deleted". */
  locallyDeleted: boolean;
  /**
   * True when this deletion originated on THIS device (user swipe) and must be
   * pushed to the server as a DELETE. False for deletes *detected* from the
   * server (Scenario 7) — those are already gone remotely and just linger
   * locally until the 30-day purge. This persistent flag is what lets a
   * server-side delete rest in "Recently Deleted" instead of being re-pushed.
   */
  pendingRemoteDelete: boolean;
  /** When it was locally deleted (30-day retention window). ISO-8601 UTC, or null. */
  deletedAt: string | null;
  /** Created by conflict resolution (server won; this preserves the local copy). */
  isConflictedCopy: boolean;
};

/** Content payload sent on POST/PUT — the server `RecipeCreate` shape. */
export type RecipeInput = Omit<Recipe, 'id' | 'created_at' | 'updated_at' | 'deleted_at' | 'ingredients'> & {
  ingredients: LocalIngredient[];
};

/** Lightweight sync-list row: `GET /recipes?fields=id,updated_at`. */
export type RecipeListItem = {
  id: string;
  updated_at: string;
};

/**
 * The server operations {@link SyncService} needs. An interface so tests inject
 * a mock and the real implementation (in `api/recipes.ts`) binds the auth token.
 */
export interface SyncApi {
  /** Lightweight id+updated_at list of the user's active (non-deleted) recipes. */
  listRecipeIds(): Promise<RecipeListItem[]>;
  /** Full recipe by server id. */
  getRecipe(serverId: string): Promise<Recipe>;
  /** POST a new recipe; returns the server's canonical version (with id/timestamps). */
  createRecipe(input: RecipeInput): Promise<Recipe>;
  /** PUT a full replacement; returns the updated server version. */
  updateRecipe(serverId: string, input: RecipeInput): Promise<Recipe>;
  /** DELETE (soft-delete server-side). Resolves on 204; rejects with ApiError otherwise. */
  deleteRecipe(serverId: string): Promise<void>;
}

/**
 * Local persistence {@link SyncService} needs. Backed by expo-sqlite in the app
 * (`db/sqliteRecipeRepo.ts`) and by an in-memory map in tests
 * (`sync/memoryRepo.ts`). `getAll` returns everything including locally-deleted
 * records — the sync algorithm needs them.
 */
export interface RecipeRepository {
  getAll(): Promise<LocalRecipe[]>;
  getByLocalId(localId: string): Promise<LocalRecipe | null>;
  getByServerId(serverId: string): Promise<LocalRecipe | null>;
  insert(recipe: LocalRecipe): Promise<void>;
  update(recipe: LocalRecipe): Promise<void>;
  /** Hard delete (removes the row). */
  remove(localId: string): Promise<void>;
}

/** Injected side effects, kept out of the algorithm for deterministic tests. */
export type SyncEnv = {
  /** Current time. Injected so tests can pin it. */
  now: () => Date;
  /** New local id (UUID). Injected so tests can make it deterministic. */
  newId: () => string;
};

/** Outcome of one `sync()` run — drives the UI banners. */
export type SyncResult = {
  /** Server-only recipes downloaded and inserted locally (Scenario 3). */
  pulledNew: number;
  /** Existing recipes overwritten from a newer server version (Scenario 4). */
  pulledUpdated: number;
  /** Local recipes created/updated on the server (Scenarios 1, 2, 8). */
  pushed: number;
  /** Recipes detected as deleted on the server → soft-deleted locally (Scenario 7). */
  serverDeleted: number;
  /** Local (user-initiated) deletes successfully pushed + removed (Scenario 6). */
  localDeletesPushed: number;
  /** Both-sides-edited recipes resolved server-wins with a local copy kept (Scenario 5). */
  conflictsResolved: number;
  /** Recipes whose push/delete failed this run (they retry next sync) (Scenario 9). */
  writeFailures: number;
};

/** A zeroed {@link SyncResult}. */
export function emptySyncResult(): SyncResult {
  return {
    pulledNew: 0,
    pulledUpdated: 0,
    pushed: 0,
    serverDeleted: 0,
    localDeletesPushed: 0,
    conflictsResolved: 0,
    writeFailures: 0,
  };
}
