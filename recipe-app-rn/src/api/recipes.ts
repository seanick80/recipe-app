import { apiRequest } from '../lib/apiClient';
import type { Recipe } from '../types/recipe';

/**
 * Recipe endpoints. Read-only for Phase 2 (list + detail); CRUD lands with the
 * Phase 3 sync work. Paths mirror the SwiftUI `APIClient` (`recipes/`,
 * `recipes/{id}`). The plain list returns the full `RecipeResponse[]` — no
 * pagination, no `fields` param (that variant is only for sync diffing).
 */

export function fetchRecipes(token: string, signal?: AbortSignal): Promise<Recipe[]> {
  return apiRequest<Recipe[]>('recipes/', { token, signal });
}

export function fetchRecipe(token: string, id: string, signal?: AbortSignal): Promise<Recipe> {
  return apiRequest<Recipe>(`recipes/${id}`, { token, signal });
}
