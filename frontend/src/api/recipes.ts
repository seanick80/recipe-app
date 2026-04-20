import { apiFetch } from "./client";

export interface Ingredient {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  display_order: number;
  notes: string;
}

export interface Recipe {
  id: string;
  name: string;
  summary: string;
  instructions: string;
  prep_time_minutes: number;
  cook_time_minutes: number;
  servings: number;
  cuisine: string;
  course: string;
  tags: string;
  source_url: string;
  difficulty: string;
  is_favorite: boolean;
  is_published: boolean;
  ingredients: Ingredient[];
  created_at: string;
  updated_at: string;
}

export interface RecipeCreate {
  name: string;
  summary: string;
  instructions: string;
  prep_time_minutes: number;
  cook_time_minutes: number;
  servings: number;
  cuisine: string;
  course: string;
  tags: string;
  source_url: string;
  difficulty: string;
  is_favorite: boolean;
  is_published: boolean;
  ingredients: Omit<Ingredient, "id">[];
}

export function fetchRecipes(): Promise<Recipe[]> {
  return apiFetch<Recipe[]>("/recipes");
}

export function fetchRecipe(id: string): Promise<Recipe> {
  return apiFetch<Recipe>(`/recipes/${id}`);
}

export function createRecipe(data: RecipeCreate): Promise<Recipe> {
  return apiFetch<Recipe>("/recipes", {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function updateRecipe(id: string, data: RecipeCreate): Promise<Recipe> {
  return apiFetch<Recipe>(`/recipes/${id}`, {
    method: "PUT",
    body: JSON.stringify(data),
  });
}

export function deleteRecipe(id: string): Promise<void> {
  return apiFetch<void>(`/recipes/${id}`, { method: "DELETE" });
}

export function patchRecipe(
  id: string,
  data: Partial<{ is_favorite: boolean; is_published: boolean }>,
): Promise<Recipe> {
  return apiFetch<Recipe>(`/recipes/${id}`, {
    method: "PATCH",
    body: JSON.stringify(data),
  });
}
