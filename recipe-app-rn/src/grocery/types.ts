/**
 * Local-only Shopping + Grocery domain types (Phase 4 slice 3). Ported from the
 * SwiftUI `ShoppingTemplate`/`TemplateItem`/`GroceryList`/`GroceryItem` models.
 * These are NOT server-synced (decision 2026-07-10) — they live only in the
 * device's SQLite store, so there is no sync metadata here.
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

/** A named, ordered set of staples (e.g. "Weekly Staples"). */
export type ShoppingTemplate = {
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
};

/** A grocery list; `archivedAt` non-null means it's archived (kept, read-only). */
export type GroceryList = {
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
