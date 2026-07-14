/**
 * Recipe URL-import core: fetch a web page, parse a Schema.org Recipe out of it
 * (via {@link parseRecipeFromHTML}), and map the parsed {@link ImportedRecipe}
 * into the local create payload ({@link RecipeInput}).
 *
 * This is the *shared* import core. The manual "Import from URL" entry point on
 * the recipe list uses it today; the future platform share entry points — the
 * iOS Share Extension and the Android share-intent handler (later phases) —
 * will route into this same code: they call {@link fetchAndParseRecipe} (or
 * receive an already-parsed recipe) and navigate to `ImportReview`, which
 * finishes the import through {@link importedRecipeToDraft} +
 * `useSync().createRecipe`. Keep it framework-free and testable.
 *
 * The ImportedRecipe → RecipeInput mapping mirrors the SwiftUI app's
 * `PendingImportService.confirmImport`: each ingredient STRING is run through
 * {@link parseListLine} for quantity/unit/name and {@link categorizeGroceryItem}
 * for its aisle category, preserving order; instructions are joined into one
 * numbered block.
 */
import { emptyDraft } from '../sync/recipeDraft';
import type { LocalIngredient, RecipeInput } from '../sync/types';
import { categorizeGroceryItem } from './groceryCategorizer';
import { parseListLine } from './listLineParser';
import { parseRecipeFromHTML } from './recipeSchemaParser';
import type { ImportedRecipe, RecipeImportError } from './recipeSchemaParser';

/** Why an import failed. `parse` wraps the underlying {@link RecipeImportError}. */
export type RecipeFetchError =
  | { kind: 'invalidURL' }
  | { kind: 'network'; message: string }
  | { kind: 'http'; status: number }
  | { kind: 'parse'; error: RecipeImportError };

/** A failed fetch-and-parse, with a user-facing message ready for the UI. */
export type FetchParseFailure = { success: false; error: RecipeFetchError; message: string };

/** Result of {@link fetchAndParseRecipe}. */
export type FetchParseResult = { success: true; recipe: ImportedRecipe } | FetchParseFailure;

/** Map a parser error onto a short, user-facing sentence. */
function messageForParseError(error: RecipeImportError): string {
  switch (error) {
    case 'noHTML':
      return 'That page was empty.';
    case 'missingTitle':
      return 'We found a recipe but it had no title.';
    case 'missingIngredients':
      return 'We found a recipe but it had no ingredients.';
    case 'noRecipeFound':
    default:
      return "We couldn't find a recipe on that page.";
  }
}

function fail(error: RecipeFetchError, message: string): FetchParseFailure {
  return { success: false, error, message };
}

/**
 * Fetch a URL, read its HTML, and parse a recipe out of it. `fetchImpl` is
 * injected so tests can supply a mock; it defaults to the global `fetch`.
 * Network and HTTP errors are folded into a {@link FetchParseFailure} with a
 * user-facing `message` — this never throws.
 */
export async function fetchAndParseRecipe(
  url: string,
  fetchImpl: typeof fetch = fetch,
): Promise<FetchParseResult> {
  const trimmed = url.trim();
  if (trimmed.length === 0 || !/^https?:\/\//i.test(trimmed)) {
    return fail({ kind: 'invalidURL' }, 'Enter a valid recipe URL (starting with http:// or https://).');
  }

  let response: Response;
  try {
    response = await fetchImpl(trimmed, {
      headers: {
        Accept: 'text/html,application/xhtml+xml',
        'User-Agent': 'RecipeApp-RN/0.1.0',
      },
    });
  } catch (e) {
    return fail(
      { kind: 'network', message: String(e) },
      "Couldn't reach that page. Check your connection and the URL.",
    );
  }

  if (!response.ok) {
    return fail({ kind: 'http', status: response.status }, `That page returned an error (${response.status}).`);
  }

  let html: string;
  try {
    html = await response.text();
  } catch (e) {
    return fail({ kind: 'network', message: String(e) }, "Couldn't read that page.");
  }

  const parsed = parseRecipeFromHTML(html, trimmed);
  if (!parsed.success) {
    return fail({ kind: 'parse', error: parsed.error }, messageForParseError(parsed.error));
  }
  return { success: true, recipe: parsed.recipe };
}

/**
 * Map a parsed {@link ImportedRecipe} onto the create payload ({@link RecipeInput}).
 *
 * Mirrors the SwiftUI `PendingImportService.confirmImport`:
 * - `title` → `name`
 * - `instructions[]` → a single numbered block ("1. …\n\n2. …")
 * - `servings`/`prepTimeMinutes`/`cookTimeMinutes` → their fields, defaulting
 *   (null → 1 serving / 0 minutes) exactly like the Swift `?? …` fallbacks
 * - `cuisine`/`course`/`sourceURL` passed through (`sourceURL` → `source_url`)
 * - each ingredient STRING → structured via {@link parseListLine}
 *   (quantity/unit/name) + {@link categorizeGroceryItem} (aisle category),
 *   `display_order` following the original order. Unparseable lines fall back
 *   to the raw string as the name, quantity 1, no unit.
 */
export function importedRecipeToDraft(imported: ImportedRecipe): RecipeInput {
  const instructions = imported.instructions.map((step, i) => `${i + 1}. ${step}`).join('\n\n');

  const ingredients: LocalIngredient[] = imported.ingredients.map((raw, index) => {
    const parsed = parseListLine(raw);
    const name = parsed?.name ?? raw;
    return {
      name,
      quantity: parsed?.quantity ?? 1,
      unit: parsed?.unit ?? '',
      category: categorizeGroceryItem(name),
      display_order: index,
      notes: '',
    };
  });

  return {
    ...emptyDraft(),
    name: imported.title,
    instructions,
    servings: imported.servings ?? 1,
    prep_time_minutes: imported.prepTimeMinutes ?? 0,
    cook_time_minutes: imported.cookTimeMinutes ?? 0,
    cuisine: imported.cuisine,
    course: imported.course,
    source_url: imported.sourceURL,
    ingredients,
  };
}
