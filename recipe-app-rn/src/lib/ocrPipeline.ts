/**
 * The pure, testable core of the photo-scan (OCR) feature: turns adapted
 * {@link OCRLine}[] into a routed result — either an {@link ImportedRecipe}
 * (for the recipe review screen) or a list of {@link ParsedListItem}s (to drop
 * onto a grocery list) — with an image-quality assessment attached so the UI can
 * suggest a retake.
 *
 * Flow (all steps reuse the ported SharedLogic parsers):
 *   1. `assessImageQuality`   — median-confidence / blank-page check → retake hint
 *   2. `separateHandwritten`  — keep the printed lines, drop handwriting
 *   3. join printed line text → `detectContentType`
 *   4. route:
 *        - shoppingList → `parseShoppingListText`
 *        - recipe / unknown → `parseRecipeText`, adapted to `ImportedRecipe`
 *
 * "unknown" content defaults to the recipe path: a photographed page with no
 * clear shopping-list markers is far more likely to be a recipe, and the recipe
 * review screen lets the user fix up anything the parser got wrong.
 *
 * No camera or native module is touched here — feed it fixture `OCRLine[]` in
 * tests.
 */

import type { ContentType } from './contentDetector';
import { detectContentType } from './contentDetector';
import type { ParsedListItem } from './listLineParser';
import { parseShoppingListText } from './listLineParser';
import type { ParsedIngredient, ParsedRecipe } from './ocrParser';
import { parseRecipeText } from './ocrParser';
import type { ImageQualityAssessment, OCRLine } from './qualityGate';
import { assessImageQuality, separateHandwritten } from './qualityGate';
import type { ImportedRecipe } from './recipeSchemaParser';

/** Result of running the OCR pipeline over recognized lines. */
export type OCRPipelineResult = {
  /** Overall image-quality assessment; drives the "retake?" hint in the UI. */
  quality: ImageQualityAssessment;
  /** What the content was detected as (recipe/shoppingList/unknown). */
  detected: ContentType;
} & (
  | { kind: 'recipe'; recipe: ImportedRecipe }
  | { kind: 'shoppingList'; items: ParsedListItem[] }
);

/**
 * Formats a structured {@link ParsedIngredient} back into a single "qty unit
 * name" display string for {@link ImportedRecipe.ingredients} (which is a
 * `string[]`; `importedRecipeToDraft` re-parses these downstream).
 *
 * Drops a redundant leading "1" when there's no unit (so "salt" doesn't become
 * "1 salt"), but keeps explicit quantities and units ("2 cups flour", "3 eggs").
 */
export function formatIngredient(ing: ParsedIngredient): string {
  const parts: string[] = [];
  const hasUnit = ing.unit.trim().length > 0;
  // Show the quantity unless it's a bare default of 1 with no unit.
  if (hasUnit || ing.quantity !== 1) {
    parts.push(String(ing.quantity));
  }
  if (hasUnit) parts.push(ing.unit.trim());
  if (ing.name.trim().length > 0) parts.push(ing.name.trim());
  return parts.join(' ');
}

/** Adapts a heuristically-parsed {@link ParsedRecipe} into an {@link ImportedRecipe}. */
export function parsedRecipeToImported(recipe: ParsedRecipe): ImportedRecipe {
  return {
    title: recipe.title,
    ingredients: recipe.ingredients.map(formatIngredient),
    instructions: recipe.instructions,
    servings: recipe.servings,
    prepTimeMinutes: recipe.prepTimeMinutes,
    cookTimeMinutes: recipe.cookTimeMinutes,
    totalTimeMinutes: null,
    cuisine: '',
    course: '',
    // Photographed recipes have no source URL/image.
    sourceURL: '',
    imageURL: '',
    ingredientNormalizations: [],
  };
}

/**
 * Runs the full OCR pipeline over recognized lines and returns a routed result.
 *
 * @param lines OCR lines, already adapted via `mlKitToOCRLines`
 *   (normalized boxes, bottom-left origin).
 */
export function runOCRPipeline(lines: OCRLine[]): OCRPipelineResult {
  const quality = assessImageQuality(lines);

  // Keep printed text; handwriting is dropped (it parses poorly).
  const { printed } = separateHandwritten(lines);
  const text = printed.map((l) => l.text).join('\n');

  const detected = detectContentType(text);

  if (detected === 'shoppingList') {
    return { kind: 'shoppingList', items: parseShoppingListText(text), quality, detected };
  }

  // recipe or unknown → recipe path.
  return { kind: 'recipe', recipe: parsedRecipeToImported(parseRecipeText(text)), quality, detected };
}
