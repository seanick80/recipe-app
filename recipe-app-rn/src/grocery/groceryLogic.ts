/**
 * Pure Shopping/Grocery logic (Phase 4 slice 3) — category grouping, merge,
 * add-staples, and generate-from-recipes consolidation. Ports the rules from the
 * SwiftUI `ShoppingViewModel` / `GenerateGroceryListView`. No React, no DB, no
 * global time/id — ids are injected — so every rule is unit-testable.
 */
import { categorizeGroceryItem } from '../lib/groceryCategorizer';
import { stripPrepNotes } from '../lib/prepNoteStripper';
import type { CategorySection, GenerateRecipe, GroceryItem, TemplateItem } from './types';

/**
 * Canonical display order of categories (SwiftUI `ShoppingViewModel.categoryOrder`).
 * NOTE: this is the store-aisle *display* order, deliberately different from the
 * classifier's type-union order. Unknown categories sort after everything.
 */
export const CATEGORY_ORDER: string[] = [
  'Produce',
  'Dairy',
  'Meat',
  'Dry & Canned',
  'Household',
  'Frozen',
  'Bakery',
  'Snacks',
  'Beverages',
  'Condiments',
  'Spices',
  'Other',
];

/** Index of a category in {@link CATEGORY_ORDER}; unknown → length (sorts last). */
export function categorySortIndex(category: string): number {
  const i = CATEGORY_ORDER.indexOf(category);
  return i === -1 ? CATEGORY_ORDER.length : i;
}

function nameCompare(a: string, b: string): number {
  return a.localeCompare(b, undefined, { sensitivity: 'base' });
}

/**
 * Group items into category sections in {@link CATEGORY_ORDER}; within a section,
 * unchecked items first, then case-insensitive alphabetical by name.
 */
export function groupByCategory(items: GroceryItem[]): CategorySection[] {
  const byCategory = new Map<string, GroceryItem[]>();
  for (const item of items) {
    const list = byCategory.get(item.category) ?? [];
    list.push(item);
    byCategory.set(item.category, list);
  }
  return [...byCategory.entries()]
    .sort((a, b) => categorySortIndex(a[0]) - categorySortIndex(b[0]) || nameCompare(a[0], b[0]))
    .map(([category, list]) => ({
      category,
      items: [...list].sort(
        (a, b) => Number(a.isChecked) - Number(b.isChecked) || nameCompare(a.name, b.name),
      ),
    }));
}

/**
 * Whether every item in a (non-empty) list is checked. Drives the header's
 * single check-all/uncheck-all toggle: an empty list, or any unchecked item,
 * means the next bulk action should *check* all; only a fully-checked list
 * flips the action to *uncheck* all.
 */
export function allItemsChecked(items: GroceryItem[]): boolean {
  return items.length > 0 && items.every((i) => i.isChecked);
}

/** A new grocery item from a manual add — category auto-assigned by the classifier. */
export function makeGroceryItem(
  id: string,
  name: string,
  quantity: number,
  unit: string,
): GroceryItem {
  return {
    id,
    name,
    quantity,
    unit,
    category: categorizeGroceryItem(name),
    isChecked: false,
    sourceRecipeName: '',
    sourceRecipeId: '',
  };
}

/**
 * Template staples to add to a list: only those whose name (case-insensitive)
 * isn't already present. Dedup is by name only (unit ignored), matching iOS.
 */
export function staplesToAdd(
  existing: GroceryItem[],
  template: TemplateItem[],
  newId: () => string,
): GroceryItem[] {
  const have = new Set(existing.map((i) => i.name.toLowerCase()));
  const added: GroceryItem[] = [];
  for (const t of template) {
    if (have.has(t.name.toLowerCase())) continue;
    have.add(t.name.toLowerCase());
    added.push({
      id: newId(),
      name: t.name,
      quantity: t.quantity,
      unit: t.unit,
      category: t.category || 'Other',
      isChecked: false,
      sourceRecipeName: '',
      sourceRecipeId: '',
    });
  }
  return added;
}

const key = (name: string, unit: string): string => `${name.toLowerCase()}|${unit.toLowerCase()}`;

/**
 * Merge `sources` into `target`, returning the merged item list. Dedup by
 * `name|unit`: matching items sum quantity; an unchecked incoming duplicate
 * forces the merged item unchecked (only `false` ever wins — matches iOS). New
 * keys are cloned in (preserving `isChecked`) with a fresh id.
 */
export function mergeInto(
  target: GroceryItem[],
  sources: GroceryItem[][],
  newId: () => string,
): GroceryItem[] {
  const result = target.map((i) => ({ ...i }));
  const byKey = new Map<string, GroceryItem>();
  for (const it of result) byKey.set(key(it.name, it.unit), it);

  for (const source of sources) {
    for (const item of source) {
      const k = key(item.name, item.unit);
      const existing = byKey.get(k);
      if (existing) {
        existing.quantity += item.quantity;
        if (!item.isChecked) existing.isChecked = false;
      } else {
        // A new item in the target list — a fresh local record, so it must not
        // inherit the source item's server id (it will be created server-side).
        const clone = { ...item, id: newId(), serverId: null };
        result.push(clone);
        byKey.set(k, clone);
      }
    }
  }
  return result;
}

/** Title-case a cleaned ingredient name for display ("white flour" → "White Flour"). */
function titleCase(s: string): string {
  return s.replace(/\S+/g, (w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase());
}

type Consolidated = {
  name: string;
  quantity: number;
  unit: string;
  category: string;
  recipeNames: string[];
  recipeIds: string[];
};

/**
 * Generate/merge recipe ingredients into an existing list's items, returning the
 * new full item set (existing items updated in place, new items appended).
 *
 * Two stages (SwiftUI `GenerateGroceryListView.generate`):
 *  A) consolidate across recipes by cleaned-name (stripPrepNotes), summing only
 *     when units match; attribute contributing recipes (deduped by name);
 *  B) merge into the list by `name|unit`, summing quantity and unioning recipe
 *     provenance. (We dedup provenance — a small improvement over iOS.)
 */
export function generateFromRecipes(
  recipes: GenerateRecipe[],
  existing: GroceryItem[],
  newId: () => string,
): GroceryItem[] {
  // Stage A — consolidate across the selected recipes.
  const consolidated = new Map<string, Consolidated>();
  for (const recipe of recipes) {
    for (const ing of recipe.ingredients) {
      const stripped = stripPrepNotes(ing.name).name.trim();
      const cleanName = stripped.length > 0 ? stripped : ing.name;
      const k = cleanName.toLowerCase();
      const category = ing.category.trim().length > 0 ? ing.category : categorizeGroceryItem(cleanName);
      const entry = consolidated.get(k);
      if (entry) {
        if (entry.unit.toLowerCase() === ing.unit.toLowerCase()) entry.quantity += ing.quantity;
        if (!entry.recipeNames.includes(recipe.name)) {
          entry.recipeNames.push(recipe.name);
          entry.recipeIds.push(recipe.id);
        }
      } else {
        consolidated.set(k, {
          name: cleanName,
          quantity: ing.quantity,
          unit: ing.unit,
          category,
          recipeNames: [recipe.name],
          recipeIds: [recipe.id],
        });
      }
    }
  }

  // Stage B — merge into the existing list by name|unit.
  const result = existing.map((i) => ({ ...i }));
  const byKey = new Map<string, GroceryItem>();
  for (const it of result) byKey.set(key(it.name, it.unit), it);

  for (const entry of consolidated.values()) {
    const k = key(entry.name, entry.unit);
    const existingItem = byKey.get(k);
    if (existingItem) {
      existingItem.quantity += entry.quantity;
      existingItem.sourceRecipeName = unionCsv(existingItem.sourceRecipeName, entry.recipeNames);
      existingItem.sourceRecipeId = unionCsv(existingItem.sourceRecipeId, entry.recipeIds);
    } else {
      const item: GroceryItem = {
        id: newId(),
        name: titleCase(entry.name),
        quantity: entry.quantity,
        unit: entry.unit,
        category: entry.category,
        isChecked: false,
        sourceRecipeName: entry.recipeNames.join(', '),
        sourceRecipeId: entry.recipeIds.join(', '),
      };
      result.push(item);
      byKey.set(k, item);
    }
  }
  return result;
}

/** Append `additions` to an existing comma-joined string, de-duplicated. */
function unionCsv(existing: string, additions: string[]): string {
  const have = existing.length > 0 ? existing.split(',').map((s) => s.trim()) : [];
  const set = new Set(have);
  for (const a of additions) {
    if (!set.has(a)) {
      have.push(a);
      set.add(a);
    }
  }
  return have.join(', ');
}
