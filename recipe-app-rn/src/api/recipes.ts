import { apiRequest } from '../lib/apiClient';
import type { RecipeInput, RecipeListItem, SyncApi } from '../sync/types';
import type { Recipe } from '../types/recipe';

/**
 * Recipe endpoints. Phase 2 shipped read-only list + detail; Phase 3 adds the
 * write + sync-diff endpoints the {@link SyncService} needs. Paths mirror the
 * SwiftUI `APIClient` (`recipes/`, `recipes/{id}`). Trailing slash on the
 * collection URL is intentional — the server registers both `""` and `"/"` and
 * the trailing form avoids a 307 redirect that strips the auth header.
 */

export function fetchRecipes(token: string, signal?: AbortSignal): Promise<Recipe[]> {
  return apiRequest<Recipe[]>('recipes/', { token, signal });
}

export function fetchRecipe(token: string, id: string, signal?: AbortSignal): Promise<Recipe> {
  return apiRequest<Recipe>(`recipes/${id}`, { token, signal });
}

/** Lightweight sync-diff list: only `{id, updated_at}` for active recipes. */
export function fetchRecipeList(token: string, signal?: AbortSignal): Promise<RecipeListItem[]> {
  return apiRequest<RecipeListItem[]>('recipes/?fields=id,updated_at', { token, signal });
}

export function createRecipe(token: string, input: RecipeInput): Promise<Recipe> {
  return apiRequest<Recipe>('recipes/', { method: 'POST', body: input, token });
}

export function updateRecipe(token: string, id: string, input: RecipeInput): Promise<Recipe> {
  return apiRequest<Recipe>(`recipes/${id}`, { method: 'PUT', body: input, token });
}

export function deleteRecipe(token: string, id: string): Promise<void> {
  return apiRequest<void>(`recipes/${id}`, { method: 'DELETE', token });
}

/**
 * Bind the current auth token into a {@link SyncApi} for the SyncService. The
 * caller (SyncContext) recreates this whenever the token changes.
 */
export function createSyncApi(token: string): SyncApi {
  return {
    listRecipeIds: () => fetchRecipeList(token),
    getRecipe: (serverId) => fetchRecipe(token, serverId),
    createRecipe: (input) => createRecipe(token, input),
    updateRecipe: (serverId, input) => updateRecipe(token, serverId, input),
    deleteRecipe: (serverId) => deleteRecipe(token, serverId),
  };
}
