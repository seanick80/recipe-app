/**
 * Wire-format types matching the FastAPI server's `RecipeResponse` /
 * `IngredientResponse` (see `server/schemas/recipe.py`). Field names are kept
 * snake_case exactly as the server sends them — no client-side transform — so
 * there is one fewer place for a mapping bug to hide. Mirrors the fields in
 * `schema/canonical.yaml` (the `typescript` surface).
 */
export type Ingredient = {
  id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  display_order: number;
  notes: string;
};

export type Recipe = {
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
  /** Server includes this; unused by the read-only RN UI but typed for completeness. */
  deleted_at?: string | null;
};
