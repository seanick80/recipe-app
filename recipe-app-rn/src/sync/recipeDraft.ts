/**
 * Pure helpers for the recipe create/edit form (Phase 4). Kept free of React and
 * native modules so the draft↔record mapping and validation are unit-testable
 * (component render tests are still deferred — see MIGRATION_STATUS.md).
 *
 * The editable payload is exactly {@link RecipeInput} (the server write shape),
 * so a draft round-trips to the API with no extra mapping. Sync metadata
 * (localId, needsSync, timestamps, delete flags) is applied here when a draft is
 * turned into / merged onto a {@link LocalRecipe}.
 */
import type { LocalIngredient, LocalRecipe, RecipeInput, SyncEnv } from './types';

/** A blank editable ingredient row. */
export function emptyIngredient(): LocalIngredient {
  return { name: '', quantity: 0, unit: '', category: 'Other', display_order: 0, notes: '' };
}

/** Defaults for a brand-new recipe, mirroring the server `RecipeCreate` field defaults. */
export function emptyDraft(): RecipeInput {
  return {
    name: '',
    summary: '',
    instructions: '',
    prep_time_minutes: 0,
    cook_time_minutes: 0,
    servings: 1,
    cuisine: '',
    course: '',
    tags: '',
    source_url: '',
    difficulty: '',
    is_favorite: false,
    is_published: false,
    ingredients: [],
  };
}

/** Extract the editable fields from a stored recipe (deep-copied for safe editing). */
export function localToDraft(recipe: LocalRecipe): RecipeInput {
  return {
    name: recipe.name,
    summary: recipe.summary,
    instructions: recipe.instructions,
    prep_time_minutes: recipe.prep_time_minutes,
    cook_time_minutes: recipe.cook_time_minutes,
    servings: recipe.servings,
    cuisine: recipe.cuisine,
    course: recipe.course,
    tags: recipe.tags,
    source_url: recipe.source_url,
    difficulty: recipe.difficulty,
    is_favorite: recipe.is_favorite,
    is_published: recipe.is_published,
    ingredients: recipe.ingredients.map((i) => ({ ...i })),
  };
}

/** Renumber `display_order` to match list position — the form manages order by row index. */
function normalizeIngredients(ingredients: LocalIngredient[]): LocalIngredient[] {
  return ingredients.map((ing, index) => ({ ...ing, display_order: index }));
}

export type DraftErrors = { name?: string };

/** Validate a draft. Save is enabled only when there are no errors. */
export function validateDraft(draft: RecipeInput): DraftErrors {
  const errors: DraftErrors = {};
  const name = draft.name.trim();
  if (name.length === 0) errors.name = 'Name is required.';
  else if (name.length > 500) errors.name = 'Name is too long.';
  return errors;
}

export function isDraftValid(draft: RecipeInput): boolean {
  return Object.keys(validateDraft(draft)).length === 0;
}

/** Trim strings the server bounds; drop blank-named ingredients; renumber order. */
export function cleanDraft(draft: RecipeInput): RecipeInput {
  return {
    ...draft,
    name: draft.name.trim(),
    ingredients: normalizeIngredients(draft.ingredients.filter((i) => i.name.trim().length > 0)),
  };
}

/** A new, never-synced local record from a draft (create path). Sets needsSync. */
export function draftToNewLocal(draft: RecipeInput, env: SyncEnv): LocalRecipe {
  const clean = cleanDraft(draft);
  const nowIso = env.now().toISOString();
  return {
    localId: env.newId(),
    serverId: null,
    ...clean,
    createdAt: nowIso,
    updatedAt: nowIso,
    needsSync: true,
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    isConflictedCopy: false,
  };
}

/** Merge a draft's content onto an existing record (edit path). Sets needsSync. */
export function applyDraft(recipe: LocalRecipe, draft: RecipeInput, nowIso: string): LocalRecipe {
  const clean = cleanDraft(draft);
  return {
    ...recipe,
    ...clean,
    updatedAt: nowIso,
    needsSync: true,
  };
}

/** Mark a record locally deleted + queued for a server DELETE (user swipe/delete). */
export function markDeleted(recipe: LocalRecipe, nowIso: string): LocalRecipe {
  return {
    ...recipe,
    locallyDeleted: true,
    pendingRemoteDelete: true,
    deletedAt: nowIso,
  };
}
