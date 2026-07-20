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

/** The one active (non-archived, non-locally-deleted) list, or null. */
function activeList(lists: GroceryList[]): GroceryList | null {
  return lists.find((l) => !l.archivedAt && !l.locallyDeleted) ?? null;
}

/**
 * Owns the offline-first Shopping + Grocery store and drives
 * {@link GrocerySyncService}. Grocery lives on-device (SQLite) and stays fully
 * usable for guests (no auth gate on the local reads/writes); when signed in the
 * server is reconciled in the background on the same triggers as recipes — on
 * auth, on foreground / pull-to-refresh (via SyncContext's `syncNow`, which calls
 * {@link GroceryContextValue.syncGrocery}), and after every local mutation.
 *
 * **One-list policy (client-side).** The app keeps a single persistent, rolling
 * shopping list — there are no multiple lists, no archive/history, no
 * create/rename/merge from the UI. `ensureSingleList()` runs on init: it creates
 * the list if none exists and consolidates any strays (e.g. left by an older
 * multi-list build, or produced by sync) into one. This is purely a client
 * convention layered over the unchanged multi-list DB/sync schema — the sync
 * layer reconciles the single list like any other record.
 *
 * Every mutation sets `needsSync` + bumps `updatedAt` (mirroring the recipe
 * store) so the next sync pushes it; for a guest the record simply keeps its
 * dirty flags and syncs once they sign in. State is only set after an `await`
 * inside effects (React 19 `set-state-in-effect` rule).
 */
type GroceryContextValue = {
  initializing: boolean;
  /** The single persistent shopping list (null only briefly during init). */
  list: GroceryList | null;
  templates: ShoppingTemplate[];

  addItem: (
    listId: string,
    name: string,
    quantity: number,
    unit: string,
    category?: string,
  ) => Promise<void>;
  updateItem: (listId: string, item: GroceryItem) => Promise<void>;
  toggleItem: (listId: string, itemId: string) => Promise<void>;
  deleteItem: (listId: string, itemId: string) => Promise<void>;
  /** Set `isChecked` on every item in the list, persisting once (one sync bump). */
  setAllChecked: (listId: string, checked: boolean) => Promise<void>;
  uncheckAll: (listId: string) => Promise<void>;
  removeChecked: (listId: string) => Promise<void>;
  clearItems: (listId: string) => Promise<void>;

  /** Copy a template's staples onto the list (name-deduped); returns count added. */
  addStaples: (listId: string, templateId: string) => Promise<number>;
  /** Append recipe ingredients into the single list (consolidated + merged). */
  generate: (recipes: GenerateRecipe[]) => Promise<void>;

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
  // A mutation that fires while a sync/push is already running sets this instead
  // of racing it; the in-flight run drains it when it finishes (so no local
  // write is ever silently dropped).
  const pendingPush = useRef(false);

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

  // Push local changes UP without pulling — the trigger after every local
  // mutation. No pull means a just-checked item can't be momentarily reverted by
  // a racing download (#18), and we stop fetching from the server on every tap.
  const pushGrocery = useCallback(async () => {
    const service = serviceRef.current;
    if (!service) return;
    if (inFlight.current) {
      pendingPush.current = true;
      return;
    }
    inFlight.current = true;
    try {
      do {
        pendingPush.current = false;
        await service.pushLocalChanges();
      } while (pendingPush.current);
      await refresh();
    } catch (e) {
      debugLog.log('grocery.sync', 'Grocery push failed', { error: String(e) });
    } finally {
      inFlight.current = false;
    }
  }, [refresh]);

  // Full reconcile (pull + push). Reserved for init / foreground / pull-to-
  // refresh (driven by SyncContext) — NOT per-mutation, so server fetches are
  // infrequent rather than firing on every checkbox tap.
  const syncGrocery = useCallback(async () => {
    const service = serviceRef.current;
    if (!service) return;
    if (inFlight.current) {
      pendingPush.current = true;
      return;
    }
    inFlight.current = true;
    try {
      await service.sync();
      await refresh();
    } catch (e) {
      debugLog.log('grocery.sync', 'Grocery sync failed', { error: String(e) });
    } finally {
      inFlight.current = false;
    }
    // A mutation that raced this full sync only left a flag — drain it now.
    if (pendingPush.current) void pushGrocery();
  }, [refresh, pushGrocery]);

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

  const requireRepo = () => {
    const repo = repoRef.current;
    if (!repo) throw new Error('Grocery store not ready');
    return repo;
  };

  // Insert a fresh, empty list straight into the repo (no refresh/sync — the
  // caller drives those). Private; the UI never creates lists directly.
  const insertNewList = useCallback(async (name: string) => {
    const repo = requireRepo();
    const id = newLocalId();
    const iso = nowIso();
    await repo.insertList({
      id,
      name: name.trim() || 'Groceries',
      createdAt: iso,
      archivedAt: null,
      items: [],
      ...newRecordMeta(iso),
    });
    return id;
  }, []);

  // Combine several stray active lists into one. Keeper = the list most worth
  // preserving for sync: prefer one with a serverId, then the oldest by
  // createdAt (deterministic). Every other list's items merge into the keeper,
  // then the dup is soft-deleted (same path as a user delete: hidden + queued
  // for a server DELETE). Writes to the repo directly; caller refreshes.
  const consolidateLists = useCallback(async (active: GroceryList[]) => {
    const repo = requireRepo();
    const sorted = [...active].sort((a, b) => {
      const sa = a.serverId ? 0 : 1;
      const sb = b.serverId ? 0 : 1;
      if (sa !== sb) return sa - sb;
      return a.createdAt.localeCompare(b.createdAt);
    });
    const [keeper, ...dups] = sorted;
    const iso = nowIso();
    const merged = mergeInto(keeper.items, dups.map((d) => d.items), newLocalId);
    await repo.updateList({ ...keeper, items: merged, updatedAt: iso, needsSync: true });
    for (const dup of dups) {
      await repo.updateList({
        ...dup,
        locallyDeleted: true,
        pendingRemoteDelete: true,
        deletedAt: iso,
        updatedAt: iso,
        needsSync: true,
      });
    }
    debugLog.log('grocery.list', 'Consolidated shopping lists', {
      merged: String(dups.length + 1),
      keeper: keeper.id,
    });
  }, []);

  // Enforce the one-list policy against the repo (not React state, since this
  // runs during init before state settles): create the list if there are none,
  // or fold multiples into one. Reads/writes the repo; caller refreshes.
  const ensureSingleList = useCallback(async () => {
    const repo = requireRepo();
    const all = await repo.getAllLists();
    const active = all.filter((l) => !l.archivedAt && !l.locallyDeleted);
    if (active.length === 0) {
      await insertNewList('Groceries');
    } else if (active.length > 1) {
      await consolidateLists(active);
    }
  }, [insertNewList, consolidateLists]);

  // (Re)initialize the store + service whenever the token changes. Local data
  // loads for everyone (guests included); the sync service is only built when
  // authenticated, and an initial reconcile runs on sign-in.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!repoRef.current) repoRef.current = new SqliteGroceryRepo(await getDatabase());
      await refresh();
      if (cancelled) return;
      await ensureSingleList();
      if (cancelled) return;
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
  }, [token, refresh, syncGrocery, ensureSingleList]);

  const list = useMemo(() => activeList(lists), [lists]);
  const findTemplate = useCallback((id: string) => templates.find((t) => t.id === id), [templates]);

  // --- items (mutate the one list's array, persist the list wholesale) ---
  const persistItems = useCallback(
    async (listId: string, items: GroceryItem[]) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      await requireRepo().updateList({ ...target, items, updatedAt: nowIso(), needsSync: true });
      await refresh();
      void pushGrocery();
    },
    [lists, refresh, pushGrocery],
  );

  const addItem = useCallback(
    async (listId: string, name: string, quantity: number, unit: string, category?: string) => {
      const target = lists.find((l) => l.id === listId);
      if (!target || name.trim().length === 0) return;
      const item = makeGroceryItem(newLocalId(), name.trim(), quantity, unit);
      // Honor an explicitly chosen category; otherwise keep the name-based
      // auto-categorization from makeGroceryItem.
      const withCategory = category && category.trim().length > 0 ? { ...item, category } : item;
      await persistItems(listId, [...target.items, withCategory]);
    },
    [lists, persistItems],
  );

  const updateItem = useCallback(
    async (listId: string, item: GroceryItem) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      await persistItems(listId, target.items.map((i) => (i.id === item.id ? item : i)));
    },
    [lists, persistItems],
  );

  const toggleItem = useCallback(
    async (listId: string, itemId: string) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      await persistItems(
        listId,
        target.items.map((i) => (i.id === itemId ? { ...i, isChecked: !i.isChecked } : i)),
      );
    },
    [lists, persistItems],
  );

  const deleteItem = useCallback(
    async (listId: string, itemId: string) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      await persistItems(listId, target.items.filter((i) => i.id !== itemId));
    },
    [lists, persistItems],
  );

  const setAllChecked = useCallback(
    async (listId: string, checked: boolean) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      // One batched persist over the whole array — a single needs_sync bump.
      await persistItems(listId, target.items.map((i) => ({ ...i, isChecked: checked })));
    },
    [lists, persistItems],
  );

  const uncheckAll = useCallback((listId: string) => setAllChecked(listId, false), [setAllChecked]);

  const removeChecked = useCallback(
    async (listId: string) => {
      const target = lists.find((l) => l.id === listId);
      if (!target) return;
      await persistItems(listId, target.items.filter((i) => !i.isChecked));
    },
    [lists, persistItems],
  );

  const clearItems = useCallback(
    async (listId: string) => {
      await persistItems(listId, []);
    },
    [persistItems],
  );

  const addStaples = useCallback(
    async (listId: string, templateId: string) => {
      const target = lists.find((l) => l.id === listId);
      const template = templates.find((t) => t.id === templateId);
      if (!target || !template) return 0;
      const added = staplesToAdd(target.items, template.items, newLocalId);
      if (added.length > 0) await persistItems(listId, [...target.items, ...added]);
      return added.length;
    },
    [lists, templates, persistItems],
  );

  const generate = useCallback(
    async (recipes: GenerateRecipe[]) => {
      const target = activeList(lists);
      if (!target) return;
      const merged = generateFromRecipes(recipes, target.items, newLocalId);
      await requireRepo().updateList({ ...target, items: merged, updatedAt: nowIso(), needsSync: true });
      await refresh();
      void pushGrocery();
    },
    [lists, refresh, pushGrocery],
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
    void pushGrocery();
    return template;
  }, [templates, refresh, pushGrocery]);

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
      void pushGrocery();
    },
    [findTemplate, refresh, pushGrocery],
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
      void pushGrocery();
    },
    [findTemplate, refresh, pushGrocery],
  );

  const value = useMemo<GroceryContextValue>(
    () => ({
      initializing,
      list,
      templates,
      addItem,
      updateItem,
      toggleItem,
      deleteItem,
      setAllChecked,
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
      list,
      templates,
      addItem,
      updateItem,
      toggleItem,
      deleteItem,
      setAllChecked,
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
