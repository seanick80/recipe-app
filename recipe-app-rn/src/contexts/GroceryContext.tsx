import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

import { createGrocerySyncApi } from '../api/grocery';
import { getDatabase } from '../db/database';
import {
  generateFromRecipes,
  makeGroceryItem,
  mergeInto,
  staplesToAdd,
} from '../grocery/groceryLogic';
import { GrocerySyncService } from '../grocery/grocerySyncService';
import { SqliteGroceryRepo } from '../grocery/groceryRepo';
import type {
  GenerateRecipe,
  GroceryItem,
  GroceryList,
  GrocerySyncEnv,
  GrocerySyncMeta,
  ShoppingTemplate,
  TemplateItem,
} from '../grocery/types';
import { debugLog } from '../lib/debugLog';
import { newLocalId } from '../lib/ids';
import { useAuth } from './AuthContext';

const DEFAULT_TEMPLATE_NAME = 'Weekly Staples';
const nowIso = (): string => new Date().toISOString();

const realEnv: GrocerySyncEnv = {
  now: () => new Date(),
  newId: () => newLocalId(),
};

/** Sync metadata for a brand-new local record — unsynced and dirty (needs push). */
function newRecordMeta(iso: string): GrocerySyncMeta {
  return {
    serverId: null,
    updatedAt: iso,
    needsSync: true,
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
  };
}

/**
 * Owns the offline-first Shopping + Grocery store and drives
 * {@link GrocerySyncService}. Grocery lives on-device (SQLite) and stays fully
 * usable for guests (no auth gate on the local reads/writes); when signed in the
 * server is reconciled in the background on the same triggers as recipes — on
 * auth, on foreground / pull-to-refresh (via SyncContext's `syncNow`, which calls
 * {@link GroceryContextValue.syncGrocery}), and after every local mutation.
 *
 * Every mutation sets `needsSync` + bumps `updatedAt` (mirroring the recipe
 * store) so the next sync pushes it; for a guest the record simply keeps its
 * dirty flags and syncs once they sign in. State is only set after an `await`
 * inside effects (React 19 `set-state-in-effect` rule).
 */
type GroceryContextValue = {
  initializing: boolean;
  lists: GroceryList[];
  activeLists: GroceryList[];
  archivedLists: GroceryList[];
  templates: ShoppingTemplate[];
  getList: (id: string) => GroceryList | undefined;

  createList: (name: string) => Promise<string>;
  renameList: (id: string, name: string) => Promise<void>;
  deleteList: (id: string) => Promise<void>;
  setArchived: (id: string, archived: boolean) => Promise<void>;
  mergeLists: (sourceIds: string[], targetId: string) => Promise<void>;

  addItem: (listId: string, name: string, quantity: number, unit: string) => Promise<void>;
  updateItem: (listId: string, item: GroceryItem) => Promise<void>;
  toggleItem: (listId: string, itemId: string) => Promise<void>;
  deleteItem: (listId: string, itemId: string) => Promise<void>;
  uncheckAll: (listId: string) => Promise<void>;
  removeChecked: (listId: string) => Promise<void>;
  clearItems: (listId: string) => Promise<void>;

  /** Copy a template's staples onto a list (name-deduped); returns count added. */
  addStaples: (listId: string, templateId: string) => Promise<number>;
  /** Generate/merge recipe ingredients into a new or existing list; returns list id. */
  generate: (
    recipes: GenerateRecipe[],
    target: { listId: string } | { newListName: string },
  ) => Promise<string>;

  ensureDefaultTemplate: () => Promise<ShoppingTemplate>;
  renameTemplate: (id: string, name: string) => Promise<void>;
  setTemplateItems: (templateId: string, items: TemplateItem[]) => Promise<void>;

  /** Reconcile grocery with the server (no-op for guests). Called by SyncContext. */
  syncGrocery: () => Promise<void>;
  /** Clear watermarks + re-download everything (no-op for guests). */
  forceSyncGrocery: () => Promise<void>;
};

const GroceryContext = createContext<GroceryContextValue | undefined>(undefined);

export function GroceryProvider({ children }: { children: React.ReactNode }) {
  const { token } = useAuth();

  const [lists, setLists] = useState<GroceryList[]>([]);
  const [templates, setTemplates] = useState<ShoppingTemplate[]>([]);
  const [initializing, setInitializing] = useState(true);
  const repoRef = useRef<SqliteGroceryRepo | null>(null);
  const serviceRef = useRef<GrocerySyncService | null>(null);
  const inFlight = useRef(false);

  // Locally-deleted records are hidden from the UI (they linger for the sync
  // layer to push a DELETE / age out over the 30-day purge window).
  const refresh = useCallback(async () => {
    const repo = repoRef.current;
    if (!repo) return;
    const allLists = await repo.getAllLists();
    const allTemplates = await repo.getAllTemplates();
    setLists(allLists.filter((l) => !l.locallyDeleted));
    setTemplates(allTemplates.filter((t) => !t.locallyDeleted));
  }, []);

  const syncGrocery = useCallback(async () => {
    const service = serviceRef.current;
    if (!service || inFlight.current) return;
    inFlight.current = true;
    try {
      await service.sync();
      await refresh();
    } catch (e) {
      debugLog.log('grocery.sync', 'Grocery sync failed', { error: String(e) });
    } finally {
      inFlight.current = false;
    }
  }, [refresh]);

  const forceSyncGrocery = useCallback(async () => {
    const service = serviceRef.current;
    if (!service || inFlight.current) return;
    inFlight.current = true;
    try {
      await service.forceFullSync();
      await refresh();
    } catch (e) {
      debugLog.log('grocery.sync', 'Force grocery sync failed', { error: String(e) });
    } finally {
      inFlight.current = false;
    }
  }, [refresh]);

  // (Re)initialize the store + service whenever the token changes. Local data
  // loads for everyone (guests included); the sync service is only built when
  // authenticated, and an initial reconcile runs on sign-in.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!repoRef.current) repoRef.current = new SqliteGroceryRepo(await getDatabase());
      await refresh();
      if (cancelled) return;
      setInitializing(false);
      if (token) {
        serviceRef.current = new GrocerySyncService({
          repo: repoRef.current,
          api: createGrocerySyncApi(token),
          env: realEnv,
        });
        await syncGrocery();
      } else {
        serviceRef.current = null;
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [token, refresh, syncGrocery]);

  const requireRepo = () => {
    const repo = repoRef.current;
    if (!repo) throw new Error('Grocery store not ready');
    return repo;
  };

  const findList = useCallback((id: string) => lists.find((l) => l.id === id), [lists]);
  const findTemplate = useCallback((id: string) => templates.find((t) => t.id === id), [templates]);

  // --- lists ---
  const createList = useCallback(
    async (name: string) => {
      const repo = requireRepo();
      const id = newLocalId();
      const iso = nowIso();
      await repo.insertList({
        id,
        name: name.trim() || 'Grocery List',
        createdAt: iso,
        archivedAt: null,
        items: [],
        ...newRecordMeta(iso),
      });
      await refresh();
      void syncGrocery();
      return id;
    },
    [refresh, syncGrocery],
  );

  /** Persist a list's meta/sync change (marks dirty + bumps updatedAt). */
  const persistList = useCallback(
    async (list: GroceryList, changes: Partial<GroceryList>) => {
      await requireRepo().updateList({ ...list, ...changes, updatedAt: nowIso(), needsSync: true });
      await refresh();
      void syncGrocery();
    },
    [refresh, syncGrocery],
  );

  const renameList = useCallback(
    async (id: string, name: string) => {
      const list = findList(id);
      if (!list) return;
      await persistList(list, { name: name.trim() || list.name });
    },
    [findList, persistList],
  );

  const deleteList = useCallback(
    async (id: string) => {
      const list = findList(id);
      if (!list) return;
      // Soft-delete (mirrors recipe delete): hidden from the UI + queued for a
      // server DELETE. Never-synced/guest lists just age out via the purge.
      await persistList(list, {
        locallyDeleted: true,
        pendingRemoteDelete: true,
        deletedAt: nowIso(),
      });
    },
    [findList, persistList],
  );

  const setArchived = useCallback(
    async (id: string, archived: boolean) => {
      const list = findList(id);
      if (!list) return;
      await persistList(list, { archivedAt: archived ? nowIso() : null });
    },
    [findList, persistList],
  );

  const mergeLists = useCallback(
    async (sourceIds: string[], targetId: string) => {
      const repo = requireRepo();
      const target = findList(targetId);
      if (!target) return;
      const sources = sourceIds
        .filter((id) => id !== targetId)
        .map(findList)
        .filter((l): l is GroceryList => !!l);
      const merged = mergeInto(target.items, sources.map((s) => s.items), newLocalId);
      const iso = nowIso();
      await repo.updateList({ ...target, items: merged, updatedAt: iso, needsSync: true });
      for (const s of sources) {
        await repo.updateList({ ...s, archivedAt: iso, updatedAt: iso, needsSync: true });
      }
      await refresh();
      void syncGrocery();
    },
    [findList, refresh, syncGrocery],
  );

  // --- items (mutate the list's array, persist the list wholesale) ---
  const persistItems = useCallback(
    async (listId: string, items: GroceryItem[]) => {
      const list = findList(listId);
      if (!list) return;
      await requireRepo().updateList({ ...list, items, updatedAt: nowIso(), needsSync: true });
      await refresh();
      void syncGrocery();
    },
    [findList, refresh, syncGrocery],
  );

  const addItem = useCallback(
    async (listId: string, name: string, quantity: number, unit: string) => {
      const list = findList(listId);
      if (!list || name.trim().length === 0) return;
      const item = makeGroceryItem(newLocalId(), name.trim(), quantity, unit);
      await persistItems(listId, [...list.items, item]);
    },
    [findList, persistItems],
  );

  const updateItem = useCallback(
    async (listId: string, item: GroceryItem) => {
      const list = findList(listId);
      if (!list) return;
      await persistItems(listId, list.items.map((i) => (i.id === item.id ? item : i)));
    },
    [findList, persistItems],
  );

  const toggleItem = useCallback(
    async (listId: string, itemId: string) => {
      const list = findList(listId);
      if (!list) return;
      await persistItems(
        listId,
        list.items.map((i) => (i.id === itemId ? { ...i, isChecked: !i.isChecked } : i)),
      );
    },
    [findList, persistItems],
  );

  const deleteItem = useCallback(
    async (listId: string, itemId: string) => {
      const list = findList(listId);
      if (!list) return;
      await persistItems(listId, list.items.filter((i) => i.id !== itemId));
    },
    [findList, persistItems],
  );

  const uncheckAll = useCallback(
    async (listId: string) => {
      const list = findList(listId);
      if (!list) return;
      await persistItems(listId, list.items.map((i) => ({ ...i, isChecked: false })));
    },
    [findList, persistItems],
  );

  const removeChecked = useCallback(
    async (listId: string) => {
      const list = findList(listId);
      if (!list) return;
      await persistItems(listId, list.items.filter((i) => !i.isChecked));
    },
    [findList, persistItems],
  );

  const clearItems = useCallback(
    async (listId: string) => {
      await persistItems(listId, []);
    },
    [persistItems],
  );

  const addStaples = useCallback(
    async (listId: string, templateId: string) => {
      const list = findList(listId);
      const template = templates.find((t) => t.id === templateId);
      if (!list || !template) return 0;
      const added = staplesToAdd(list.items, template.items, newLocalId);
      if (added.length > 0) await persistItems(listId, [...list.items, ...added]);
      return added.length;
    },
    [findList, templates, persistItems],
  );

  const generate = useCallback(
    async (recipes: GenerateRecipe[], target: { listId: string } | { newListName: string }) => {
      const repo = requireRepo();
      const iso = nowIso();
      if ('listId' in target) {
        const list = findList(target.listId);
        if (!list) return target.listId;
        const merged = generateFromRecipes(recipes, list.items, newLocalId);
        await repo.updateList({ ...list, items: merged, updatedAt: iso, needsSync: true });
        await refresh();
        void syncGrocery();
        return target.listId;
      }
      const id = newLocalId();
      const merged = generateFromRecipes(recipes, [], newLocalId);
      await repo.insertList({
        id,
        name: target.newListName.trim() || 'Grocery List',
        createdAt: iso,
        archivedAt: null,
        items: merged,
        ...newRecordMeta(iso),
      });
      await refresh();
      void syncGrocery();
      return id;
    },
    [findList, refresh, syncGrocery],
  );

  // --- templates ---
  const ensureDefaultTemplate = useCallback(async () => {
    const existing = templates.find((t) => t.name === DEFAULT_TEMPLATE_NAME) ?? templates[0];
    if (existing) return existing;
    const iso = nowIso();
    const template: ShoppingTemplate = {
      id: newLocalId(),
      name: DEFAULT_TEMPLATE_NAME,
      sortOrder: 0,
      createdAt: iso,
      items: [],
      ...newRecordMeta(iso),
    };
    await requireRepo().insertTemplate(template);
    await refresh();
    void syncGrocery();
    return template;
  }, [templates, refresh, syncGrocery]);

  const renameTemplate = useCallback(
    async (id: string, name: string) => {
      const template = findTemplate(id);
      if (!template) return;
      await requireRepo().updateTemplate({
        ...template,
        name: name.trim() || DEFAULT_TEMPLATE_NAME,
        updatedAt: nowIso(),
        needsSync: true,
      });
      await refresh();
      void syncGrocery();
    },
    [findTemplate, refresh, syncGrocery],
  );

  const setTemplateItems = useCallback(
    async (templateId: string, items: TemplateItem[]) => {
      const template = findTemplate(templateId);
      if (!template) return;
      await requireRepo().updateTemplate({
        ...template,
        items: items.map((it, index) => ({ ...it, sortOrder: index })),
        updatedAt: nowIso(),
        needsSync: true,
      });
      await refresh();
      void syncGrocery();
    },
    [findTemplate, refresh, syncGrocery],
  );

  const value = useMemo<GroceryContextValue>(
    () => ({
      initializing,
      lists,
      activeLists: lists.filter((l) => !l.archivedAt),
      archivedLists: lists.filter((l) => l.archivedAt),
      templates,
      getList: findList,
      createList,
      renameList,
      deleteList,
      setArchived,
      mergeLists,
      addItem,
      updateItem,
      toggleItem,
      deleteItem,
      uncheckAll,
      removeChecked,
      clearItems,
      addStaples,
      generate,
      ensureDefaultTemplate,
      renameTemplate,
      setTemplateItems,
      syncGrocery,
      forceSyncGrocery,
    }),
    [
      initializing,
      lists,
      templates,
      findList,
      createList,
      renameList,
      deleteList,
      setArchived,
      mergeLists,
      addItem,
      updateItem,
      toggleItem,
      deleteItem,
      uncheckAll,
      removeChecked,
      clearItems,
      addStaples,
      generate,
      ensureDefaultTemplate,
      renameTemplate,
      setTemplateItems,
      syncGrocery,
      forceSyncGrocery,
    ],
  );

  return <GroceryContext.Provider value={value}>{children}</GroceryContext.Provider>;
}

export function useGrocery(): GroceryContextValue {
  const ctx = useContext(GroceryContext);
  if (!ctx) throw new Error('useGrocery must be used within a GroceryProvider');
  return ctx;
}
