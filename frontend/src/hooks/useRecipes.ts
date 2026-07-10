import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  createRecipe,
  deleteRecipe,
  fetchPublicRecipe,
  fetchRecipe,
  fetchRecipes,
  updateRecipe,
  type RecipeCreate,
} from "../api/recipes";
import { useAuth } from "./useAuth";

export function useRecipes() {
  const { data: user } = useAuth();
  return useQuery({
    queryKey: ["recipes"],
    queryFn: fetchRecipes,
    enabled: !!user,
  });
}

export function useRecipe(id: string) {
  return useQuery({
    queryKey: ["recipe", id],
    queryFn: () => fetchRecipe(id),
  });
}

// Picks the authenticated recipe endpoint for signed-in viewers (so owners see
// unpublished recipes) and the public endpoint for everyone else (which only
// resolves published recipes). Keeps hook calls unconditional.
export function useRecipeForViewer(
  id: string,
  isAuthenticated: boolean,
  enabled = true,
) {
  return useQuery({
    queryKey: ["recipe", id, isAuthenticated ? "auth" : "public"],
    queryFn: () => (isAuthenticated ? fetchRecipe(id) : fetchPublicRecipe(id)),
    enabled,
  });
}

export function useCreateRecipe() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: RecipeCreate) => createRecipe(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["recipes"] });
    },
  });
}

export function useUpdateRecipe() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RecipeCreate }) =>
      updateRecipe(id, data),
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: ["recipes"] });
      queryClient.invalidateQueries({ queryKey: ["recipe", variables.id] });
    },
  });
}

export function useDeleteRecipe() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => deleteRecipe(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["recipes"] });
    },
  });
}
