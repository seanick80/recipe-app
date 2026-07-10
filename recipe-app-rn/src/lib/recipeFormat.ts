import type { Ingredient, Recipe } from '../types/recipe';

/**
 * Pure display helpers for the read-only Recipes UI, matching how the SwiftUI
 * `RecipeListView` / `RecipeDetailView` render each field. (The SwiftUI
 * unit-conversion toggle is intentionally deferred — v1 shows the server's
 * stored quantity/unit verbatim.)
 */

/** Total time shown as a single "N min" figure (prep + cook), like the list row. */
export function totalTimeMinutes(
  recipe: Pick<Recipe, 'prep_time_minutes' | 'cook_time_minutes'>,
): number {
  return recipe.prep_time_minutes + recipe.cook_time_minutes;
}

/**
 * Ingredients as the detail view shows them — ascending `display_order`, stable.
 * Generic over the id-bearing wire {@link Ingredient} and the id-less local
 * shape alike (only `display_order` is read).
 */
export function sortedIngredients<T extends { display_order: number }>(ingredients: T[]): T[] {
  return ingredients
    .map((ing, index) => ({ ing, index }))
    .sort((a, b) => a.ing.display_order - b.ing.display_order || a.index - b.index)
    .map(({ ing }) => ing);
}

/** Trim trailing zeros so quantities read as "2" and "1.5", not "2.0" / "1.50". */
export function formatQuantity(quantity: number): string {
  if (Number.isInteger(quantity)) return String(quantity);
  return parseFloat(quantity.toFixed(2)).toString();
}

/**
 * A single ingredient line: "<qty> <unit> <name> (<notes>)", omitting any empty
 * part — mirrors the SwiftUI detail row (quantity+unit, name, notes in parens).
 */
export function formatIngredient(
  ing: Pick<Ingredient, 'quantity' | 'unit' | 'name' | 'notes'>,
): string {
  const qty = ing.quantity > 0 ? formatQuantity(ing.quantity) : '';
  const amount = [qty, ing.unit.trim()].filter((s) => s.length > 0).join(' ');
  const base = [amount, ing.name.trim()].filter((s) => s.length > 0).join(' ');
  const notes = ing.notes.trim();
  return notes.length > 0 ? `${base} (${notes})` : base;
}

/** Split the comma-separated `tags` string into trimmed, non-empty chips. */
export function parseTags(tags: string): string[] {
  return tags
    .split(',')
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

/** True when `source_url` should be rendered as a tappable link (else plain text). */
export function isHttpUrl(url: string): boolean {
  return /^https?:\/\//i.test(url.trim());
}
