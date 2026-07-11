/**
 * SyncService — the Phase 3 spike. A faithful port of the SwiftUI
 * `SyncService.swift` sync algorithm (see `docs/sync-execution-plan.md` for the
 * 9 scenarios) over an offline-first local store, so the RN client reconciles
 * with the server exactly like the shipping iOS client.
 *
 * The algorithm is pure over three injected collaborators — a
 * {@link RecipeRepository}, a {@link SyncApi}, and a {@link SyncEnv} (clock +
 * id) — with no direct SQLite, network, or global-time access. That is what
 * makes all 9 scenarios unit-testable headlessly (the P0 correctness bar for
 * this spike), and it keeps the risky logic isolated from native modules.
 *
 * Two deliberate deviations from the iOS port, both documented inline:
 *   1. The sync watermark is the server's own `updated_at`, not the device
 *      clock — this makes the "server is newer" comparison immune to device
 *      clock skew (iOS compared a server timestamp against a device `Date()`).
 *   2. A delete detected on the *server* during pull is soft-deleted locally
 *      and left in "Recently Deleted"; only *user*-initiated deletes are pushed
 *      as DELETE. iOS conflated both under one flag and re-issued a redundant
 *      DELETE, so a web-deleted recipe never actually rested in Recently
 *      Deleted as Scenario 7 documents. This port matches the documented spec.
 */
import { ApiError } from '../lib/apiClient';
import type { Recipe } from '../types/recipe';
import {
  emptySyncResult,
  type LocalIngredient,
  type LocalRecipe,
  type RecipeInput,
  type RecipeListItem,
  type RecipeRepository,
  type SyncApi,
  type SyncEnv,
  type SyncResult,
} from './types';

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

/** Milliseconds since epoch for an ISO string, or 0 (epoch) when null/unset. */
function ms(iso: string | null): number {
  return iso ? Date.parse(iso) : 0;
}

/** Ingredients on the wire → local shape (drop the server-assigned `id`). */
function toLocalIngredients(dto: Recipe): LocalIngredient[] {
  return dto.ingredients.map((i) => ({
    name: i.name,
    quantity: i.quantity,
    unit: i.unit,
    category: i.category,
    display_order: i.display_order,
    notes: i.notes,
  }));
}

/** Local recipe → the POST/PUT body (content only; ingredients ordered). */
export function localToInput(recipe: LocalRecipe): RecipeInput {
  return {
    name: recipe.name,
    summary: recipe.summary,
    instructions: recipe.instructions,
    prep_time_minutes: recipe.prep_time_minutes,
    cook_time_minutes: recipe.cook_time_minutes,
    servings: recipe.servings,
    cuisine: recipe.cuisine,
    course: recipe.course,
    tags: recipe.tags,
    source_url: recipe.source_url,
    difficulty: recipe.difficulty,
    is_favorite: recipe.is_favorite,
    is_published: recipe.is_published,
    ingredients: [...recipe.ingredients].sort((a, b) => a.display_order - b.display_order),
  };
}

/** Server recipe → a brand-new local record (server-only download, Scenario 3). */
export function serverToLocal(dto: Recipe, env: SyncEnv): LocalRecipe {
  return {
    localId: env.newId(),
    serverId: dto.id,
    name: dto.name,
    summary: dto.summary,
    instructions: dto.instructions,
    prep_time_minutes: dto.prep_time_minutes,
    cook_time_minutes: dto.cook_time_minutes,
    servings: dto.servings,
    cuisine: dto.cuisine,
    course: dto.course,
    tags: dto.tags,
    source_url: dto.source_url,
    difficulty: dto.difficulty,
    is_favorite: dto.is_favorite,
    is_published: dto.is_published,
    ingredients: toLocalIngredients(dto),
    createdAt: dto.created_at,
    updatedAt: dto.updated_at,
    // Watermark = server's updated_at (deviation #1), not device now().
    needsSync: false,
    lastSyncedAt: dto.updated_at,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    isConflictedCopy: false,
  };
}

/** Overwrite an existing local record's content from the server (Scenarios 4/5). */
function applyServer(local: LocalRecipe, dto: Recipe): void {
  local.name = dto.name;
  local.summary = dto.summary;
  local.instructions = dto.instructions;
  local.prep_time_minutes = dto.prep_time_minutes;
  local.cook_time_minutes = dto.cook_time_minutes;
  local.servings = dto.servings;
  local.cuisine = dto.cuisine;
  local.course = dto.course;
  local.tags = dto.tags;
  local.source_url = dto.source_url;
  local.difficulty = dto.difficulty;
  local.is_favorite = dto.is_favorite;
  local.is_published = dto.is_published;
  local.ingredients = toLocalIngredients(dto); // delete-all + re-insert
  local.createdAt = dto.created_at;
  local.updatedAt = dto.updated_at;
  local.lastSyncedAt = dto.updated_at;
  local.needsSync = false;
}

/** Local-time "YYYY-MM-DD HH:mm" for the conflicted-copy name (matches iOS). */
export function formatConflictDate(d: Date): string {
  const p = (n: number): string => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

/** Snapshot the user's current local edits as a new, unsynced sibling (Scenario 5). */
export function conflictCopy(local: LocalRecipe, env: SyncEnv): LocalRecipe {
  const nowIso = env.now().toISOString();
  return {
    localId: env.newId(),
    serverId: null,
    name: `${local.name} (conflicted copy ${formatConflictDate(env.now())})`,
    summary: local.summary,
    instructions: local.instructions,
    prep_time_minutes: local.prep_time_minutes,
    cook_time_minutes: local.cook_time_minutes,
    servings: local.servings,
    cuisine: local.cuisine,
    course: local.course,
    tags: local.tags,
    source_url: local.source_url,
    difficulty: local.difficulty,
    is_favorite: local.is_favorite,
    is_published: local.is_published,
    ingredients: local.ingredients.map((i) => ({ ...i })),
    createdAt: nowIso,
    updatedAt: nowIso,
    needsSync: true, // uploaded as a new recipe next push
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    isConflictedCopy: true,
  };
}

export class SyncService {
  private readonly repo: RecipeRepository;
  private readonly api: SyncApi;
  private readonly env: SyncEnv;

  constructor(deps: { repo: RecipeRepository; api: SyncApi; env: SyncEnv }) {
    this.repo = deps.repo;
    this.api = deps.api;
    this.env = deps.env;
  }

  /**
   * One full reconciliation. Fetches the lightweight server list, then either
   * runs first-sync (bulk upload) OR pull→push→processDeletions — the two paths
   * are mutually exclusive per cycle, matching iOS. Purges expired soft-deletes
   * at the end regardless. Fetching the list or a fatal error propagates to the
   * caller (SyncContext maps it to a session-expired / generic banner);
   * per-recipe errors are swallowed and counted as {@link SyncResult.writeFailures}.
   */
  async sync(): Promise<SyncResult> {
    const result = emptySyncResult();

    const serverList = await this.api.listRecipeIds();
    const serverIds = new Set(serverList.map((i) => i.id));
    const serverMap = new Map(serverList.map((i) => [i.id, i.updated_at]));

    // Snapshot once (iOS captures localRecipes before pull and reuses it for
    // push/delete, so recipes downloaded/created during pull are not re-pushed
    // this cycle). Objects are mutated in place and persisted via repo.update.
    const localRecipes = await this.repo.getAll();

    const isFirstSync =
      serverList.length === 0 &&
      localRecipes.some((r) => r.serverId === null && !r.locallyDeleted);

    if (isFirstSync) {
      await this.performFirstSync(localRecipes, result);
    } else {
      await this.pullChanges(localRecipes, serverList, serverIds, serverMap, result);
      await this.pushChanges(localRecipes, result);
      await this.processDeletions(localRecipes, result);
    }

    await this.purgeExpiredDeletions();
    return result;
  }

  /** Clears every record's watermark, forcing a full re-download, then syncs. */
  async forceFullSync(): Promise<SyncResult> {
    const all = await this.repo.getAll();
    for (const r of all) {
      r.lastSyncedAt = null;
      await this.repo.update(r);
    }
    return this.sync();
  }

  private async pullChanges(
    localRecipes: LocalRecipe[],
    serverList: RecipeListItem[],
    serverIds: Set<string>,
    serverMap: Map<string, string>,
    result: SyncResult,
  ): Promise<void> {
    const localByServerId = new Map<string, LocalRecipe>();
    for (const r of localRecipes) {
      if (r.serverId) localByServerId.set(r.serverId, r);
    }

    // Scenario 3: a server id we've never seen locally → download & insert.
    for (const item of serverList) {
      if (localByServerId.has(item.id)) continue;
      try {
        const dto = await this.api.getRecipe(item.id);
        await this.repo.insert(serverToLocal(dto, this.env));
        result.pulledNew += 1;
      } catch {
        // transient — retry next sync
      }
    }

    // Existing-on-both-sides + server-side deletions.
    for (const [serverId, local] of localByServerId) {
      // Scenario 7: present locally, absent from server list → deleted on server.
      if (!serverIds.has(serverId)) {
        if (!local.locallyDeleted) {
          local.locallyDeleted = true;
          local.pendingRemoteDelete = false; // already gone remotely — don't re-push
          local.deletedAt = this.env.now().toISOString();
          await this.repo.update(local);
          result.serverDeleted += 1;
        }
        continue;
      }

      const serverUpdatedAt = serverMap.get(serverId);
      if (!serverUpdatedAt) continue;
      const serverIsNewer = ms(serverUpdatedAt) > ms(local.lastSyncedAt);
      if (!serverIsNewer) continue;

      if (local.needsSync) {
        // Scenario 5: both sides changed → server wins, keep a local copy.
        try {
          const dto = await this.api.getRecipe(serverId);
          await this.repo.insert(conflictCopy(local, this.env));
          applyServer(local, dto);
          await this.repo.update(local);
          result.conflictsResolved += 1;
        } catch {
          // transient — retry next sync
        }
      } else {
        // Scenario 4: server newer, no local edits → overwrite.
        try {
          const dto = await this.api.getRecipe(serverId);
          applyServer(local, dto);
          await this.repo.update(local);
          result.pulledUpdated += 1;
        } catch {
          // transient — retry next sync
        }
      }
    }
  }

  private async pushChanges(localRecipes: LocalRecipe[], result: SyncResult): Promise<void> {
    const dirty = localRecipes.filter((r) => r.needsSync && !r.locallyDeleted);
    for (const local of dirty) {
      try {
        const input = localToInput(local);
        if (local.serverId) {
          // Scenario 2: update an existing server recipe.
          const dto = await this.api.updateRecipe(local.serverId, input);
          local.lastSyncedAt = dto.updated_at;
          local.updatedAt = dto.updated_at;
          local.needsSync = false;
        } else {
          // Scenario 1: create a new server recipe.
          const dto = await this.api.createRecipe(input);
          local.serverId = dto.id;
          local.createdAt = dto.created_at;
          local.updatedAt = dto.updated_at;
          local.lastSyncedAt = dto.updated_at;
          local.needsSync = false;
        }
        await this.repo.update(local);
        result.pushed += 1;
      } catch {
        // Scenario 9: needsSync stays true, retried next cycle.
        result.writeFailures += 1;
      }
    }
  }

  private async processDeletions(localRecipes: LocalRecipe[], result: SyncResult): Promise<void> {
    for (const local of localRecipes) {
      if (!local.locallyDeleted) continue;

      // Deviation #2: only user-initiated deletes get pushed. Server-detected
      // deletes (pendingRemoteDelete === false) are already gone remotely and
      // linger locally as "Recently Deleted" until the 30-day purge.
      if (!local.pendingRemoteDelete) continue;

      // Never synced → just drop it, no server call.
      if (!local.serverId) {
        await this.repo.remove(local.localId);
        result.localDeletesPushed += 1;
        continue;
      }

      try {
        await this.api.deleteRecipe(local.serverId);
        await this.repo.remove(local.localId);
        result.localDeletesPushed += 1;
      } catch (e) {
        if (e instanceof ApiError && e.kind === 'notFound') {
          // Already gone on the server → clean up locally, not a failure.
          await this.repo.remove(local.localId);
          result.localDeletesPushed += 1;
        } else {
          result.writeFailures += 1;
        }
      }
    }
  }

  private async performFirstSync(localRecipes: LocalRecipe[], result: SyncResult): Promise<void> {
    const unsynced = localRecipes.filter((r) => r.serverId === null && !r.locallyDeleted);
    for (const local of unsynced) {
      try {
        const dto = await this.api.createRecipe(localToInput(local));
        local.serverId = dto.id;
        local.createdAt = dto.created_at;
        local.updatedAt = dto.updated_at;
        local.lastSyncedAt = dto.updated_at;
        local.needsSync = false;
        await this.repo.update(local);
        result.pushed += 1;
      } catch {
        result.writeFailures += 1;
      }
    }
  }

  private async purgeExpiredDeletions(): Promise<void> {
    const cutoff = this.env.now().getTime() - THIRTY_DAYS_MS;
    const all = await this.repo.getAll();
    for (const r of all) {
      if (r.locallyDeleted && r.deletedAt && Date.parse(r.deletedAt) < cutoff) {
        await this.repo.remove(r.localId);
      }
    }
  }
}
