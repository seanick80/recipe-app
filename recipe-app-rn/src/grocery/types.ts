/**
 * Shopping + Grocery domain types (Phase 4 slice 3). Ported from the SwiftUI
 * `ShoppingTemplate`/`TemplateItem`/`GroceryList`/`GroceryItem` models.
 *
 * Phase 4 shipped these local-only; the grocery-sync work added per-record sync
 * metadata to the two aggregate roots ({@link GroceryList} and
 * {@link ShoppingTemplate}) that mirrors the recipe store's `LocalRecipe`
 * metadata — `serverId`, `needsSync`, `lastSyncedAt`, `locallyDeleted`,
 * `pendingRemoteDelete`, `deletedAt`. Content field naming stays as before
 * (camelCase, device-side); the wire DTOs below are snake_case (server shape).
 *
 * Grocery lists reconcile per-item against the server's item API, so a
 * {@link GroceryItem} carries an optional `serverId` (its server UUID once
 * created; `null`/absent = a local-only item not yet pushed). Template items are
 * pushed as an aggregate (POST create / PUT full-replace), so they need no item
 * server id.
 */

/** A reusable "staples" item inside a {@link ShoppingTemplate}. */
export type TemplateItem = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  sortOrder: number;
};

/**
 * Per-record sync metadata carried by the grocery aggregate roots. Same fields,
 * meanings, and null conventions as the recipe store's `LocalRecipe` metadata
 * (see `sync/types.ts`) — device-only, never sent on the wire.
 */
export type GrocerySyncMeta = {
  /** Server UUID; null = never synced (a local-only record). */
  serverId: string | null;
  /** Server `updated_at` once synced; local mtime otherwise. ISO-8601 UTC. */
  updatedAt: string;
  /** Local edits not yet pushed to the server. */
  needsSync: boolean;
  /** Watermark: the server `updated_at` at the last successful sync, or null. */
  lastSyncedAt: string | null;
  /** Soft-deleted from the user's view (queued for a server DELETE, or aged out). */
  locallyDeleted: boolean;
  /** True when this delete originated locally and must be pushed as a DELETE. */
  pendingRemoteDelete: boolean;
  /** When it was locally deleted (30-day retention window). ISO-8601 UTC, or null. */
  deletedAt: string | null;
};

/** A named, ordered set of staples (e.g. "Weekly Staples"). */
export type ShoppingTemplate = GrocerySyncMeta & {
  id: string;
  name: string;
  sortOrder: number;
  createdAt: string;
  items: TemplateItem[];
};

/** One line on a grocery list. `category` is assigned once, at creation. */
export type GroceryItem = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  isChecked: boolean;
  /** Comma-joined recipe names that contributed this item (generate flow). */
  sourceRecipeName: string;
  /** Comma-joined recipe ids that contributed this item. */
  sourceRecipeId: string;
  /** Server UUID; null/undefined = a local-only item not yet pushed. */
  serverId?: string | null;
};

/** A grocery list; `archivedAt` non-null means it's archived (kept, read-only). */
export type GroceryList = GrocerySyncMeta & {
  id: string;
  name: string;
  createdAt: string;
  archivedAt: string | null;
  items: GroceryItem[];
};

/** A recipe as consumed by generate-from-recipes (mapped from a LocalRecipe). */
export type GenerateRecipe = {
  id: string;
  name: string;
  ingredients: { name: string; quantity: number; unit: string; category: string }[];
};

/** A category section for grouped display. */
export type CategorySection = {
  category: string;
  items: GroceryItem[];
};

// ---------------------------------------------------------------------------
// Sync layer — wire DTOs, the server API surface, the local repo, env, result.
// Mirrors `sync/types.ts` (recipes) adapted to the grocery per-item list API.
// ---------------------------------------------------------------------------

/** Lightweight sync-list row: `GET /grocery/lists?fields=id,updated_at`. */
export type GrocerySyncListItem = {
  id: string;
  updated_at: string;
};

/** A grocery item on the wire (server `GroceryItemResponse`). NOTE: no `list_id`. */
export type GroceryItemDto = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  is_checked: boolean;
  source_recipe_name: string;
  source_recipe_id: string;
  updated_at: string;
};

/** A full grocery list on the wire (server `GroceryListResponse`). */
export type GroceryListDto = {
  id: string;
  name: string;
  items: GroceryItemDto[];
  created_at: string;
  updated_at: string;
  archived_at: string | null;
};

/** POST body for creating an item under a list. */
export type GroceryItemInput = {
  name: string;
  quantity: number;
  unit: string;
  category: string;
  source_recipe_name: string;
  source_recipe_id: string;
};

/** PATCH body for updating an item (all fields optional). */
export type GroceryItemPatch = {
  name?: string;
  quantity?: number;
  unit?: string;
  category?: string;
  is_checked?: boolean;
};

/** A template item on the wire (server `TemplateItemResponse`). */
export type TemplateItemDto = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  sort_order: number;
  updated_at: string;
};

/** A full template on the wire (server `ShoppingTemplateResponse`). */
export type TemplateDto = {
  id: string;
  name: string;
  sort_order: number;
  items: TemplateItemDto[];
  created_at: string;
  updated_at: string;
};

/** POST/PUT body for a template (aggregate create / full replace). */
export type TemplateInput = {
  name: string;
  sort_order: number;
  items: { name: string; quantity: number; unit: string; category: string; sort_order: number }[];
};

/**
 * The server operations {@link GrocerySyncService} needs. Lists reconcile
 * per-item (the item endpoints); templates round-trip as an aggregate.
 * Implemented in `api/grocery.ts` (binds the auth token); tests inject a fake.
 */
export interface GrocerySyncApi {
  // grocery lists
  listGroceryListIds(): Promise<GrocerySyncListItem[]>;
  getGroceryList(serverId: string): Promise<GroceryListDto>;
  createGroceryList(name: string): Promise<GroceryListDto>;
  deleteGroceryList(serverId: string): Promise<void>;
  archiveGroceryList(serverId: string): Promise<GroceryListDto>;
  restoreGroceryList(serverId: string): Promise<GroceryListDto>;
  // grocery items (parent list is addressed by URL; item responses carry no list id)
  createItem(listServerId: string, input: GroceryItemInput): Promise<GroceryItemDto>;
  toggleItem(itemServerId: string): Promise<GroceryItemDto>;
  patchItem(itemServerId: string, patch: GroceryItemPatch): Promise<GroceryItemDto>;
  deleteItem(itemServerId: string): Promise<void>;
  // shopping templates
  listTemplateIds(): Promise<GrocerySyncListItem[]>;
  getTemplate(serverId: string): Promise<TemplateDto>;
  createTemplate(input: TemplateInput): Promise<TemplateDto>;
  updateTemplate(serverId: string, input: TemplateInput): Promise<TemplateDto>;
  deleteTemplate(serverId: string): Promise<void>;
}

/**
 * Local persistence {@link GrocerySyncService} needs — the same store the UI
 * uses (`grocery/groceryRepo.ts`), or an in-memory fake in tests. `getAllLists`
 * / `getAllTemplates` return everything, INCLUDING locally-deleted records (the
 * sync algorithm needs them). Aggregate writes go through `insert*`/`update*`
 * (row + items, wholesale) and hard delete via `remove*`.
 */
export interface GroceryRepository {
  getAllLists(): Promise<GroceryList[]>;
  insertList(list: GroceryList): Promise<void>;
  updateList(list: GroceryList): Promise<void>;
  removeList(id: string): Promise<void>;

  getAllTemplates(): Promise<ShoppingTemplate[]>;
  insertTemplate(template: ShoppingTemplate): Promise<void>;
  updateTemplate(template: ShoppingTemplate): Promise<void>;
  removeTemplate(id: string): Promise<void>;
}

/** Injected side effects (clock + id), kept out of the algorithm for tests. */
export type GrocerySyncEnv = {
  now: () => Date;
  newId: () => string;
};

/** Outcome of one grocery `sync()` run (lists + templates combined). */
export type GrocerySyncResult = {
  /** Server-only lists/templates downloaded and inserted locally. */
  pulledNew: number;
  /** Existing lists/templates overwritten from a newer server version. */
  pulledUpdated: number;
  /** Local lists/templates created/updated on the server. */
  pushed: number;
  /** Detected as deleted on the server → soft-deleted locally. */
  serverDeleted: number;
  /** Local (user-initiated) deletes successfully pushed + removed. */
  localDeletesPushed: number;
  /** Records whose push/delete failed this run (retried next sync). */
  writeFailures: number;
};

/** A zeroed {@link GrocerySyncResult}. */
export function emptyGrocerySyncResult(): GrocerySyncResult {
  return {
    pulledNew: 0,
    pulledUpdated: 0,
    pushed: 0,
    serverDeleted: 0,
    localDeletesPushed: 0,
    writeFailures: 0,
  };
}
