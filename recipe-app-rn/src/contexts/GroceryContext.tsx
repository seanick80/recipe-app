import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';

import { getDatabase } from '../db/database';
import {
  generateFromRecipes,
  makeGroceryItem,
  mergeInto,
  staplesToAdd,
} from '../grocery/groceryLogic';
import { SqliteGroceryRepo } from '../grocery/groceryRepo';
import type {
  GenerateRecipe,
  GroceryItem,
  GroceryList,
  ShoppingTemplate,
  TemplateItem,
} from '../grocery/types';
import { newLocalId } from '../lib/ids';

const DEFAULT_TEMPLATE_NAME = 'Weekly Staples';
const nowIso = (): string => new Date().toISOString();

/**
 * Owns the local-only Shopping + Grocery store (Phase 4 slice 3). No auth
 * gating and no server sync — grocery lives entirely on-device, so guests use
 * it too. All the reconciliation rules live in the pure `groceryLogic` module;
 * this context wires them to the SQLite repo and React state. State is only set
 * after an `await` inside effects (React 19 `set-state-in-effect` rule).
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
};

const GroceryContext = createContext<GroceryContextValue | undefined>(undefined);

export function GroceryProvider({ children }: { children: React.ReactNode }) {
  const [lists, setLists] = useState<GroceryList[]>([]);
  const [templates, setTemplates] = useState<ShoppingTemplate[]>([]);
  const [initializing, setInitializing] = useState(true);
  const repoRef = useRef<SqliteGroceryRepo | null>(null);

  const refresh = useCallback(async () => {
    const repo = repoRef.current;
    if (!repo) return;
    setLists(await repo.getAllLists());
    setTemplates(await repo.getAllTemplates());
  }, []);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!repoRef.current) repoRef.current = new SqliteGroceryRepo(await getDatabase());
      await refresh();
      if (!cancelled) setInitializing(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [refresh]);

  const requireRepo = () => {
    const repo = repoRef.current;
    if (!repo) throw new Error('Grocery store not ready');
    return repo;
  };

  const findList = useCallback((id: string) => lists.find((l) => l.id === id), [lists]);

  // --- lists ---
  const createList = useCallback(
    async (name: string) => {
      const repo = requireRepo();
      const id = newLocalId();
      await repo.insertList({ id, name: name.trim() || 'Grocery List', createdAt: nowIso(), archivedAt: null, items: [] });
      await refresh();
      return id;
    },
    [refresh],
  );

  const renameList = useCallback(
    async (id: string, name: string) => {
      const list = findList(id);
      if (!list) return;
      await requireRepo().updateListMeta(id, name.trim() || list.name, list.archivedAt);
      await refresh();
    },
    [findList, refresh],
  );

  const deleteList = useCallback(
    async (id: string) => {
      await requireRepo().deleteList(id);
      await refresh();
    },
    [refresh],
  );

  const setArchived = useCallback(
    async (id: string, archived: boolean) => {
      const list = findList(id);
      if (!list) return;
      await requireRepo().updateListMeta(id, list.name, archived ? nowIso() : null);
      await refresh();
    },
    [findList, refresh],
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
      await repo.replaceListItems(targetId, merged);
      for (const s of sources) await repo.updateListMeta(s.id, s.name, nowIso()); // archive sources
      await refresh();
    },
    [findList, refresh],
  );

  // --- items (mutate the list's array, persist wholesale) ---
  const persistItems = useCallback(
    async (listId: string, items: GroceryItem[]) => {
      await requireRepo().replaceListItems(listId, items);
      await refresh();
    },
    [refresh],
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
      let listId: string;
      let existing: GroceryItem[];
      if ('listId' in target) {
        listId = target.listId;
        existing = findList(listId)?.items ?? [];
      } else {
        listId = newLocalId();
        await repo.insertList({
          id: listId,
          name: target.newListName.trim() || 'Grocery List',
          createdAt: nowIso(),
          archivedAt: null,
          items: [],
        });
        existing = [];
      }
      const merged = generateFromRecipes(recipes, existing, newLocalId);
      await repo.replaceListItems(listId, merged);
      await refresh();
      return listId;
    },
    [findList, refresh],
  );

  // --- templates ---
  const ensureDefaultTemplate = useCallback(async () => {
    const existing = templates.find((t) => t.name === DEFAULT_TEMPLATE_NAME) ?? templates[0];
    if (existing) return existing;
    const template: ShoppingTemplate = {
      id: newLocalId(),
      name: DEFAULT_TEMPLATE_NAME,
      sortOrder: 0,
      createdAt: nowIso(),
      items: [],
    };
    await requireRepo().insertTemplate(template);
    await refresh();
    return template;
  }, [templates, refresh]);

  const renameTemplate = useCallback(
    async (id: string, name: string) => {
      await requireRepo().updateTemplateMeta(id, name.trim() || DEFAULT_TEMPLATE_NAME);
      await refresh();
    },
    [refresh],
  );

  const setTemplateItems = useCallback(
    async (templateId: string, items: TemplateItem[]) => {
      await requireRepo().replaceTemplateItems(
        templateId,
        items.map((it, index) => ({ ...it, sortOrder: index })),
      );
      await refresh();
    },
    [refresh],
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
    ],
  );

  return <GroceryContext.Provider value={value}>{children}</GroceryContext.Provider>;
}

export function useGrocery(): GroceryContextValue {
  const ctx = useContext(GroceryContext);
  if (!ctx) throw new Error('useGrocery must be used within a GroceryProvider');
  return ctx;
}
