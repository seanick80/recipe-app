import { apiRequest } from '../lib/apiClient';
import type {
  GroceryItemDto,
  GroceryItemInput,
  GroceryItemPatch,
  GroceryListDto,
  GrocerySyncApi,
  GrocerySyncListItem,
  TemplateDto,
  TemplateInput,
} from '../grocery/types';

/**
 * Grocery endpoints, mirroring `api/recipes.ts` — thin `apiRequest` wrappers
 * that attach the Bearer token, plus a {@link createGrocerySyncApi} factory that
 * binds the token into a {@link GrocerySyncApi} for the sync service.
 *
 * Paths are relative to `API_BASE_URL` (which already includes `/api/v1`), so
 * they read as `grocery/…`. Unlike the recipe collection route, the grocery
 * routes are registered WITHOUT a trailing slash, so none is added here.
 *
 * NOTE (per-item list model): item responses carry no `list_id` — an item is
 * created under a list via the URL (`/grocery/lists/{listId}/items`) and
 * thereafter addressed by its own id (`/grocery/items/{id}`). The client tracks
 * the parent locally (the item's server id lives on the local list's item row).
 */

// --- grocery lists ---

export function fetchGroceryListIds(token: string): Promise<GrocerySyncListItem[]> {
  return apiRequest<GrocerySyncListItem[]>('grocery/lists?fields=id,updated_at', { token });
}

export function fetchGroceryList(token: string, id: string): Promise<GroceryListDto> {
  return apiRequest<GroceryListDto>(`grocery/lists/${id}`, { token });
}

export function createGroceryList(token: string, name: string): Promise<GroceryListDto> {
  return apiRequest<GroceryListDto>('grocery/lists', { method: 'POST', body: { name }, token });
}

export function deleteGroceryList(token: string, id: string): Promise<void> {
  return apiRequest<void>(`grocery/lists/${id}`, { method: 'DELETE', token });
}

export function archiveGroceryList(token: string, id: string): Promise<GroceryListDto> {
  return apiRequest<GroceryListDto>(`grocery/lists/${id}/archive`, { method: 'PATCH', token });
}

export function restoreGroceryList(token: string, id: string): Promise<GroceryListDto> {
  return apiRequest<GroceryListDto>(`grocery/lists/${id}/restore`, { method: 'PATCH', token });
}

// --- grocery items ---

export function createGroceryItem(
  token: string,
  listId: string,
  input: GroceryItemInput,
): Promise<GroceryItemDto> {
  return apiRequest<GroceryItemDto>(`grocery/lists/${listId}/items`, {
    method: 'POST',
    body: input,
    token,
  });
}

export function toggleGroceryItem(token: string, itemId: string): Promise<GroceryItemDto> {
  return apiRequest<GroceryItemDto>(`grocery/items/${itemId}/toggle`, { method: 'PATCH', token });
}

export function patchGroceryItem(
  token: string,
  itemId: string,
  patch: GroceryItemPatch,
): Promise<GroceryItemDto> {
  return apiRequest<GroceryItemDto>(`grocery/items/${itemId}`, {
    method: 'PATCH',
    body: patch,
    token,
  });
}

export function deleteGroceryItem(token: string, itemId: string): Promise<void> {
  return apiRequest<void>(`grocery/items/${itemId}`, { method: 'DELETE', token });
}

// --- shopping templates ---

export function fetchTemplateIds(token: string): Promise<GrocerySyncListItem[]> {
  return apiRequest<GrocerySyncListItem[]>('grocery/templates?fields=id,updated_at', { token });
}

export function fetchTemplate(token: string, id: string): Promise<TemplateDto> {
  return apiRequest<TemplateDto>(`grocery/templates/${id}`, { token });
}

export function createTemplate(token: string, input: TemplateInput): Promise<TemplateDto> {
  return apiRequest<TemplateDto>('grocery/templates', { method: 'POST', body: input, token });
}

export function updateTemplate(
  token: string,
  id: string,
  input: TemplateInput,
): Promise<TemplateDto> {
  return apiRequest<TemplateDto>(`grocery/templates/${id}`, { method: 'PUT', body: input, token });
}

export function deleteTemplate(token: string, id: string): Promise<void> {
  return apiRequest<void>(`grocery/templates/${id}`, { method: 'DELETE', token });
}

/**
 * Bind the current auth token into a {@link GrocerySyncApi} for the
 * GrocerySyncService. The caller recreates this whenever the token changes.
 */
export function createGrocerySyncApi(token: string): GrocerySyncApi {
  return {
    listGroceryListIds: () => fetchGroceryListIds(token),
    getGroceryList: (id) => fetchGroceryList(token, id),
    createGroceryList: (name) => createGroceryList(token, name),
    deleteGroceryList: (id) => deleteGroceryList(token, id),
    archiveGroceryList: (id) => archiveGroceryList(token, id),
    restoreGroceryList: (id) => restoreGroceryList(token, id),
    createItem: (listId, input) => createGroceryItem(token, listId, input),
    toggleItem: (itemId) => toggleGroceryItem(token, itemId),
    patchItem: (itemId, patch) => patchGroceryItem(token, itemId, patch),
    deleteItem: (itemId) => deleteGroceryItem(token, itemId),
    listTemplateIds: () => fetchTemplateIds(token),
    getTemplate: (id) => fetchTemplate(token, id),
    createTemplate: (input) => createTemplate(token, input),
    updateTemplate: (id, input) => updateTemplate(token, id, input),
    deleteTemplate: (id) => deleteTemplate(token, id),
  };
}
