/**
 * Canonical unit pick-lists for the unit picker, ported from the SwiftUI
 * `Views/UnitPicker.swift` (`recipeUnits` / `shoppingUnits`). This is the
 * pick-list only — quantity conversion lives elsewhere; we just need the
 * options the picker offers plus an "Other…" free-text affordance.
 *
 * The leading empty string is the "(none)" option (no unit).
 */

/** Units offered when editing recipe ingredients — precision matters. */
export const RECIPE_UNITS: readonly string[] = [
  '', 'tsp', 'tbsp', 'cup', 'oz', 'fl oz', 'lb', 'g', 'kg', 'ml', 'l',
  'pinch', 'dash', 'whole', 'large', 'medium', 'small',
  'clove', 'slice', 'piece', 'bunch', 'head', 'stalk', 'sprig', 'stick',
  'can', 'jar', 'bottle',
];

/** Units offered when adding shopping / template items — purchase quantities. */
export const SHOPPING_UNITS: readonly string[] = [
  '', 'lb', 'oz', 'g', 'kg',
  'gal', 'qt', 'pt', 'fl oz', 'l', 'ml',
  'dozen', 'pack', 'bag', 'box', 'can', 'jar',
  'bottle', 'carton', 'container', 'loaf', 'bunch',
  'head', 'case',
];

/** Which preset list a unit picker offers. */
export type UnitContext = 'recipe' | 'shopping';

/** The preset unit list for a picker context. */
export function unitsFor(context: UnitContext): readonly string[] {
  return context === 'shopping' ? SHOPPING_UNITS : RECIPE_UNITS;
}

/**
 * True when `unit` should be edited as free text rather than picked from the
 * preset list: a non-empty value that isn't one of the presets (mirrors the
 * SwiftUI picker, which drops into a `TextField` for custom units).
 */
export function isCustomUnit(unit: string, context: UnitContext): boolean {
  return unit.trim().length > 0 && !unitsFor(context).includes(unit);
}
