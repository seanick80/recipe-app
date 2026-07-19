/**
 * GrocerySyncService — reconciles the local Shopping + Grocery store with the
 * server, mirroring the recipe {@link import('../sync/syncService').SyncService}
 * as closely as the grocery API allows. Pure over three injected collaborators
 * (a {@link GroceryRepository}, a {@link GrocerySyncApi}, and a
 * {@link GrocerySyncEnv} clock+id) so the whole algorithm is unit-testable
 * headlessly with an in-memory repo + a fake server.
 *
 * Same offline-first shape as recipes: the watermark is the server's own
 * `updated_at` (clock-skew-immune), user deletes are soft-deletes pushed as a
 * DELETE, and server-detected deletes linger in a 30-day purge window. Two
 * grocery-specific adaptations:
 *
 *   1. GROCERY LISTS reconcile PER-ITEM. The server has no whole-list PUT; a
 *      list is created (POST name) then items are POSTed under it, and edits are
 *      reconciled against a fresh server GET — create new items, PATCH changed
 *      ones (or `toggle` when only the checkbox differs), DELETE the ones gone
 *      locally. Item responses carry no `list_id`; the client tracks the parent
 *      locally (each local item stores its own server id). Archive state syncs
 *      via the archive/restore endpoints. The server exposes NO list-rename
 *      endpoint, so a rename after creation does not propagate (documented gap).
 *
 *   2. NO CONFLICT COPY for lists/templates (unlike recipes' Scenario 5). When
 *      the server is newer than the local watermark, the server version wins
 *      wholesale (pull overwrites local). Simpler, and matches the Phase-B spec.
 *
 * SHOPPING TEMPLATES are simpler: they round-trip as an aggregate (POST create /
 * PUT full-replace / DELETE), so no per-item reconcile is needed.
 */
import { ApiError } from '../lib/apiClient';
import {
  emptyGrocerySyncResult,
  type GroceryItem,
  type GroceryItemInput,
  type GroceryList,
  type GroceryListDto,
  type GroceryRepository,
  type GrocerySyncApi,
  type GrocerySyncEnv,
  type GrocerySyncListItem,
  type GrocerySyncResult,
  type ShoppingTemplate,
  type TemplateDto,
  type TemplateInput,
} from './types';

const THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000;

/** Milliseconds since epoch for an ISO string, or 0 (epoch) when null/unset. */
function ms(iso: string | null): number {
  return iso ? Date.parse(iso) : 0;
}

/** Server grocery item → local shape (fresh local id; keep the server id). */
function toLocalItem(dto: GroceryListDto['items'][number], env: GrocerySyncEnv): GroceryItem {
  return {
    id: env.newId(),
    name: dto.name,
    quantity: dto.quantity,
    unit: dto.unit,
    category: dto.category,
    isChecked: dto.is_checked,
    sourceRecipeName: dto.source_recipe_name,
    sourceRecipeId: dto.source_recipe_id,
    serverId: dto.id,
  };
}

/** Local grocery item → the POST body for creating it on the server. */
function toItemInput(item: GroceryItem): GroceryItemInput {
  return {
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    category: item.category,
    source_recipe_name: item.sourceRecipeName,
    source_recipe_id: item.sourceRecipeId,
  };
}

/** Server list → a brand-new local record (server-only download). */
export function serverToLocalList(dto: GroceryListDto, env: GrocerySyncEnv): GroceryList {
  return {
    id: env.newId(),
    name: dto.name,
    createdAt: dto.created_at,
    updatedAt: dto.updated_at,
    archivedAt: dto.archived_at,
    items: dto.items.map((i) => toLocalItem(i, env)),
    serverId: dto.id,
    needsSync: false,
    lastSyncedAt: dto.updated_at,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
  };
}

/** Overwrite an existing local list's content from the server (server wins). */
export function applyServerList(local: GroceryList, dto: GroceryListDto, env: GrocerySyncEnv): void {
  local.name = dto.name;
  local.createdAt = dto.created_at;
  local.updatedAt = dto.updated_at;
  local.archivedAt = dto.archived_at;
  local.items = dto.items.map((i) => toLocalItem(i, env));
  local.lastSyncedAt = dto.updated_at;
  local.needsSync = false;
}

/** Local template → the POST/PUT body (aggregate). */
export function toTemplateInput(template: ShoppingTemplate): TemplateInput {
  return {
    name: template.name,
    sort_order: template.sortOrder,
    items: [...template.items]
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map((i) => ({
        name: i.name,
        quantity: i.quantity,
        unit: i.unit,
        category: i.category,
        sort_order: i.sortOrder,
      })),
  };
}

/** Server template → a brand-new local record (server-only download). */
export function serverToLocalTemplate(dto: TemplateDto, env: GrocerySyncEnv): ShoppingTemplate {
  return {
    id: env.newId(),
    name: dto.name,
    sortOrder: dto.sort_order,
    createdAt: dto.created_at,
    updatedAt: dto.updated_at,
    items: dto.items.map((i) => ({
      id: env.newId(),
      name: i.name,
      quantity: i.quantity,
      unit: i.unit,
      category: i.category,
      sortOrder: i.sort_order,
    })),
    serverId: dto.id,
    needsSync: false,
    lastSyncedAt: dto.updated_at,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
  };
}

/** Overwrite an existing local template's content from the server (server wins). */
export function applyServerTemplate(
  local: ShoppingTemplate,
  dto: TemplateDto,
  env: GrocerySyncEnv,
): void {
  local.name = dto.name;
  local.sortOrder = dto.sort_order;
  local.createdAt = dto.created_at;
  local.updatedAt = dto.updated_at;
  local.items = dto.items.map((i) => ({
    id: env.newId(),
    name: i.name,
    quantity: i.quantity,
    unit: i.unit,
    category: i.category,
    sortOrder: i.sort_order,
  }));
  local.lastSyncedAt = dto.updated_at;
  local.needsSync = false;
}

export class GrocerySyncService {
  private readonly repo: GroceryRepository;
  private readonly api: GrocerySyncApi;
  private readonly env: GrocerySyncEnv;

  constructor(deps: { repo: GroceryRepository; api: GrocerySyncApi; env: GrocerySyncEnv }) {
    this.repo = deps.repo;
    this.api = deps.api;
    this.env = deps.env;
  }

  /** One full reconciliation of lists + templates, then purge expired soft-deletes. */
  async sync(): Promise<GrocerySyncResult> {
    const result = emptyGrocerySyncResult();
    await this.syncLists(result);
    await this.syncTemplates(result);
    await this.purgeExpiredDeletions();
    return result;
  }

  /**
   * Push local changes + process deletions + purge, WITHOUT a server pull. Used
   * after a local mutation (check-off / add / delete) so the change goes up
   * promptly without a pull that could momentarily clobber the just-edited UI.
   * Full pulls are reserved for {@link sync} (init / foreground / pull-to-refresh),
   * so the app no longer fetches from the server on every tap. A brand-new local
   * list/template is still created here (pushOne* creates when `serverId` is null).
   */
  async pushLocalChanges(): Promise<GrocerySyncResult> {
    const result = emptyGrocerySyncResult();
    const localLists = await this.repo.getAllLists();
    await this.pushLists(localLists, result);
    await this.processListDeletions(localLists, result);
    const localTemplates = await this.repo.getAllTemplates();
    await this.pushTemplates(localTemplates, result);
    await this.processTemplateDeletions(localTemplates, result);
    await this.purgeExpiredDeletions();
    return result;
  }

  /** Clear every record's watermark (force a full re-download), then sync. */
  async forceFullSync(): Promise<GrocerySyncResult> {
    for (const l of await this.repo.getAllLists()) {
      l.lastSyncedAt = null;
      await this.repo.updateList(l);
    }
    for (const t of await this.repo.getAllTemplates()) {
      t.lastSyncedAt = null;
      await this.repo.updateTemplate(t);
    }
    return this.sync();
  }

  // ----------------------------------------------------------------- lists ---

  private async syncLists(result: GrocerySyncResult): Promise<void> {
    const serverList = await this.api.listGroceryListIds();
    const serverIds = new Set(serverList.map((i) => i.id));
    const serverMap = new Map(serverList.map((i) => [i.id, i.updated_at]));
    const localLists = await this.repo.getAllLists();

    const isFirstSync =
      serverList.length === 0 &&
      localLists.some((l) => l.serverId === null && !l.locallyDeleted);

    if (isFirstSync) {
      await this.performFirstSyncLists(localLists, result);
    } else {
      await this.pullLists(localLists, serverList, serverIds, serverMap, result);
      await this.pushLists(localLists, result);
      await this.processListDeletions(localLists, result);
    }
  }

  private async pullLists(
    localLists: GroceryList[],
    serverList: GrocerySyncListItem[],
    serverIds: Set<string>,
    serverMap: Map<string, string>,
    result: GrocerySyncResult,
  ): Promise<void> {
    const localByServerId = new Map<string, GroceryList>();
    for (const l of localLists) {
      if (l.serverId) localByServerId.set(l.serverId, l);
    }

    // Server ids we've never seen locally → download & insert.
    for (const item of serverList) {
      if (localByServerId.has(item.id)) continue;
      try {
        const dto = await this.api.getGroceryList(item.id);
        await this.repo.insertList(serverToLocalList(dto, this.env));
        result.pulledNew += 1;
      } catch {
        // transient — retry next sync
      }
    }

    for (const [serverId, local] of localByServerId) {
      // Present locally, absent from the server list → deleted on the server.
      if (!serverIds.has(serverId)) {
        if (!local.locallyDeleted) {
          local.locallyDeleted = true;
          local.pendingRemoteDelete = false; // already gone remotely — don't re-push
          local.deletedAt = this.env.now().toISOString();
          await this.repo.updateList(local);
          result.serverDeleted += 1;
        }
        continue;
      }

      const serverUpdatedAt = serverMap.get(serverId);
      if (!serverUpdatedAt) continue;
      if (ms(serverUpdatedAt) <= ms(local.lastSyncedAt)) continue;

      // Server is newer, BUT the local list has unpushed changes (e.g. a
      // just-toggled item) → do NOT overwrite. Keep the local edit and let the
      // push reconcile it up to the server (favor the local change). Without
      // this guard a background pull clobbers a local check-off before the push
      // sends it (mirrors the recipe sync's server-newer + needsSync guard).
      if (local.needsSync) continue;

      // Server is newer and local is clean → server wins wholesale (no conflict
      // copy for lists).
      try {
        const dto = await this.api.getGroceryList(serverId);
        applyServerList(local, dto, this.env);
        await this.repo.updateList(local);
        result.pulledUpdated += 1;
      } catch {
        // transient — retry next sync
      }
    }
  }

  private async pushLists(localLists: GroceryList[], result: GrocerySyncResult): Promise<void> {
    const dirty = localLists.filter((l) => l.needsSync && !l.locallyDeleted);
    for (const local of dirty) {
      try {
        await this.pushOneList(local);
        result.pushed += 1;
      } catch {
        // needsSync stays true → retried next cycle.
        result.writeFailures += 1;
      }
    }
  }

  private async performFirstSyncLists(
    localLists: GroceryList[],
    result: GrocerySyncResult,
  ): Promise<void> {
    const unsynced = localLists.filter((l) => l.serverId === null && !l.locallyDeleted);
    for (const local of unsynced) {
      try {
        await this.pushOneList(local);
        result.pushed += 1;
      } catch {
        result.writeFailures += 1;
      }
    }
  }

  /**
   * Push one local list to the server: create it if new, reconcile its items
   * (create/patch/toggle/delete) against a fresh server GET, reconcile archive
   * state, then re-read for the authoritative watermark. Mutates `local` in
   * place (server ids on items, timestamps, needsSync) and persists it. Throws
   * on any API error so the caller counts a write failure and retries.
   */
  private async pushOneList(local: GroceryList): Promise<void> {
    // Snapshot the mtime we're pushing FROM. All the network I/O below is slow;
    // a local mutation (check-off / add / delete) can land meanwhile.
    const baseUpdatedAt = local.updatedAt;
    if (!local.serverId) {
      const created = await this.api.createGroceryList(local.name.trim() || 'Grocery List');
      local.serverId = created.id;
    }
    const server = await this.api.getGroceryList(local.serverId);
    await this.reconcileItems(local, server);
    await this.reconcileArchive(local, server);
    const finalDto = await this.api.getGroceryList(local.serverId);

    // Re-read the persisted list and detect a mutation that landed during the
    // I/O above by comparing its mtime against our snapshot. Writing our stale
    // in-memory copy straight back (as the old code did) reverted that edit AND
    // cleared needsSync so it never re-pushed — the sync-clobber bug (#18). The
    // pull path's needsSync guard didn't cover this write-back.
    const current = (await this.repo.getAllLists()).find((l) => l.id === local.id);
    if (!current) return; // deleted mid-push — the deletion path handles it.

    // Carry the item server ids we just learned onto whatever the current items
    // are, matched by stable local id, so a concurrent edit can't cause a
    // duplicate server row on the next push.
    const learned = new Map<string, string>();
    for (const it of local.items) {
      if (it.serverId) learned.set(it.id, it.serverId);
    }
    const items = current.items.map((it) =>
      it.serverId || !learned.has(it.id) ? it : { ...it, serverId: learned.get(it.id)! },
    );

    const concurrentEdit = current.updatedAt !== baseUpdatedAt;
    await this.repo.updateList({
      ...current,
      items,
      serverId: local.serverId,
      // On a clean push adopt the server's authoritative watermark + clear the
      // dirty flag. On a concurrent edit keep the newer local state and
      // needsSync so the next cycle re-pushes it; leave the watermark untouched
      // (the pull is needsSync-guarded, so it won't clobber the local edit).
      createdAt: concurrentEdit ? current.createdAt : finalDto.created_at,
      updatedAt: concurrentEdit ? current.updatedAt : finalDto.updated_at,
      archivedAt: concurrentEdit ? current.archivedAt : finalDto.archived_at,
      lastSyncedAt: concurrentEdit ? current.lastSyncedAt : finalDto.updated_at,
      needsSync: concurrentEdit,
    });
  }

  /** Reconcile a list's items against the server's current item set. */
  private async reconcileItems(local: GroceryList, server: GroceryListDto): Promise<void> {
    const serverById = new Map(server.items.map((i) => [i.id, i]));
    const matched = new Set<string>();

    for (const item of local.items) {
      if (!item.serverId) {
        // A local-only item → create it under the list; keep its server id.
        const created = await this.api.createItem(local.serverId!, toItemInput(item));
        item.serverId = created.id;
        continue;
      }
      const srv = serverById.get(item.serverId);
      if (!srv) {
        // We thought it was on the server but it's gone → recreate.
        const created = await this.api.createItem(local.serverId!, toItemInput(item));
        item.serverId = created.id;
        continue;
      }
      matched.add(item.serverId);
      const contentChanged =
        item.name !== srv.name ||
        item.quantity !== srv.quantity ||
        item.unit !== srv.unit ||
        item.category !== srv.category ||
        item.sourceRecipeName !== srv.source_recipe_name ||
        item.sourceRecipeId !== srv.source_recipe_id;
      if (contentChanged) {
        // PATCH carries is_checked too, so a combined edit needs only one call.
        await this.api.patchItem(item.serverId, {
          name: item.name,
          quantity: item.quantity,
          unit: item.unit,
          category: item.category,
          is_checked: item.isChecked,
        });
      } else if (item.isChecked !== srv.is_checked) {
        // Only the checkbox differs → the dedicated toggle endpoint.
        await this.api.toggleItem(item.serverId);
      }
    }

    // Server items no local item points at → deleted locally → DELETE remotely.
    for (const srv of server.items) {
      if (!matched.has(srv.id)) {
        await this.api.deleteItem(srv.id);
      }
    }
  }

  /** Sync archive state via the archive/restore endpoints (no whole-list PUT). */
  private async reconcileArchive(local: GroceryList, server: GroceryListDto): Promise<void> {
    if (local.archivedAt && !server.archived_at) {
      await this.api.archiveGroceryList(local.serverId!);
    } else if (!local.archivedAt && server.archived_at) {
      await this.api.restoreGroceryList(local.serverId!);
    }
  }

  private async processListDeletions(
    localLists: GroceryList[],
    result: GrocerySyncResult,
  ): Promise<void> {
    for (const local of localLists) {
      if (!local.locallyDeleted) continue;
      if (!local.pendingRemoteDelete) continue; // server-detected delete → just aged out

      if (!local.serverId) {
        await this.repo.removeList(local.id);
        result.localDeletesPushed += 1;
        continue;
      }
      try {
        await this.api.deleteGroceryList(local.serverId);
        await this.repo.removeList(local.id);
        result.localDeletesPushed += 1;
      } catch (e) {
        if (e instanceof ApiError && e.kind === 'notFound') {
          await this.repo.removeList(local.id);
          result.localDeletesPushed += 1;
        } else {
          result.writeFailures += 1;
        }
      }
    }
  }

  // ------------------------------------------------------------- templates ---

  private async syncTemplates(result: GrocerySyncResult): Promise<void> {
    const serverList = await this.api.listTemplateIds();
    const serverIds = new Set(serverList.map((i) => i.id));
    const serverMap = new Map(serverList.map((i) => [i.id, i.updated_at]));
    const localTemplates = await this.repo.getAllTemplates();

    const isFirstSync =
      serverList.length === 0 &&
      localTemplates.some((t) => t.serverId === null && !t.locallyDeleted);

    if (isFirstSync) {
      await this.performFirstSyncTemplates(localTemplates, result);
    } else {
      await this.pullTemplates(localTemplates, serverList, serverIds, serverMap, result);
      await this.pushTemplates(localTemplates, result);
      await this.processTemplateDeletions(localTemplates, result);
    }
  }

  private async pullTemplates(
    localTemplates: ShoppingTemplate[],
    serverList: GrocerySyncListItem[],
    serverIds: Set<string>,
    serverMap: Map<string, string>,
    result: GrocerySyncResult,
  ): Promise<void> {
    const localByServerId = new Map<string, ShoppingTemplate>();
    for (const t of localTemplates) {
      if (t.serverId) localByServerId.set(t.serverId, t);
    }

    for (const item of serverList) {
      if (localByServerId.has(item.id)) continue;
      try {
        const dto = await this.api.getTemplate(item.id);
        await this.repo.insertTemplate(serverToLocalTemplate(dto, this.env));
        result.pulledNew += 1;
      } catch {
        // transient — retry next sync
      }
    }

    for (const [serverId, local] of localByServerId) {
      if (!serverIds.has(serverId)) {
        if (!local.locallyDeleted) {
          local.locallyDeleted = true;
          local.pendingRemoteDelete = false;
          local.deletedAt = this.env.now().toISOString();
          await this.repo.updateTemplate(local);
          result.serverDeleted += 1;
        }
        continue;
      }
      const serverUpdatedAt = serverMap.get(serverId);
      if (!serverUpdatedAt) continue;
      if (ms(serverUpdatedAt) <= ms(local.lastSyncedAt)) continue;

      // Same local-edit guard as lists: a server-newer template must not
      // clobber unpushed local changes — let the push reconcile them up.
      if (local.needsSync) continue;

      try {
        const dto = await this.api.getTemplate(serverId);
        applyServerTemplate(local, dto, this.env);
        await this.repo.updateTemplate(local);
        result.pulledUpdated += 1;
      } catch {
        // transient — retry next sync
      }
    }
  }

  private async pushTemplates(
    localTemplates: ShoppingTemplate[],
    result: GrocerySyncResult,
  ): Promise<void> {
    const dirty = localTemplates.filter((t) => t.needsSync && !t.locallyDeleted);
    for (const local of dirty) {
      try {
        await this.pushOneTemplate(local);
        result.pushed += 1;
      } catch {
        result.writeFailures += 1;
      }
    }
  }

  private async performFirstSyncTemplates(
    localTemplates: ShoppingTemplate[],
    result: GrocerySyncResult,
  ): Promise<void> {
    const unsynced = localTemplates.filter((t) => t.serverId === null && !t.locallyDeleted);
    for (const local of unsynced) {
      try {
        await this.pushOneTemplate(local);
        result.pushed += 1;
      } catch {
        result.writeFailures += 1;
      }
    }
  }

  /** Create (POST) or full-replace (PUT) a template as an aggregate. */
  private async pushOneTemplate(local: ShoppingTemplate): Promise<void> {
    const baseUpdatedAt = local.updatedAt;
    const input = toTemplateInput(local);
    const dto = local.serverId
      ? await this.api.updateTemplate(local.serverId, input)
      : await this.api.createTemplate(input);

    // Same CAS write-back as pushOneList (#18): a template edit during the PUT
    // must not be reverted, nor its dirty flag cleared.
    const current = (await this.repo.getAllTemplates()).find((t) => t.id === local.id);
    if (!current) return;
    const concurrentEdit = current.updatedAt !== baseUpdatedAt;
    await this.repo.updateTemplate({
      ...current,
      serverId: dto.id,
      createdAt: concurrentEdit ? current.createdAt : dto.created_at,
      updatedAt: concurrentEdit ? current.updatedAt : dto.updated_at,
      lastSyncedAt: concurrentEdit ? current.lastSyncedAt : dto.updated_at,
      needsSync: concurrentEdit,
    });
  }

  private async processTemplateDeletions(
    localTemplates: ShoppingTemplate[],
    result: GrocerySyncResult,
  ): Promise<void> {
    for (const local of localTemplates) {
      if (!local.locallyDeleted) continue;
      if (!local.pendingRemoteDelete) continue;

      if (!local.serverId) {
        await this.repo.removeTemplate(local.id);
        result.localDeletesPushed += 1;
        continue;
      }
      try {
        await this.api.deleteTemplate(local.serverId);
        await this.repo.removeTemplate(local.id);
        result.localDeletesPushed += 1;
      } catch (e) {
        if (e instanceof ApiError && e.kind === 'notFound') {
          await this.repo.removeTemplate(local.id);
          result.localDeletesPushed += 1;
        } else {
          result.writeFailures += 1;
        }
      }
    }
  }

  // --------------------------------------------------------------- purge ---

  private async purgeExpiredDeletions(): Promise<void> {
    const cutoff = this.env.now().getTime() - THIRTY_DAYS_MS;
    for (const l of await this.repo.getAllLists()) {
      if (l.locallyDeleted && l.deletedAt && Date.parse(l.deletedAt) < cutoff) {
        await this.repo.removeList(l.id);
      }
    }
    for (const t of await this.repo.getAllTemplates()) {
      if (t.locallyDeleted && t.deletedAt && Date.parse(t.deletedAt) < cutoff) {
        await this.repo.removeTemplate(t.id);
      }
    }
  }
}
