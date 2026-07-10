import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, ScrollView, Text, View } from 'react-native';

import { fetchRecipe } from '../api/recipes';
import { useAuth } from '../contexts/AuthContext';
import { ApiError } from '../lib/apiClient';
import { formatIngredient, isHttpUrl, parseTags, sortedIngredients } from '../lib/recipeFormat';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import type { Recipe } from '../types/recipe';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipeDetail'>;

type DetailResult = { recipe: Recipe | null; error: string | null };

/** Pure loader (no setState) so the effect can set state only after `await`. */
async function loadRecipe(token: string | null, id: string): Promise<DetailResult> {
  if (!token) return { recipe: null, error: 'Sign in to view this recipe.' };
  try {
    return { recipe: await fetchRecipe(token, id), error: null };
  } catch (e) {
    if (e instanceof ApiError && e.kind === 'notFound') {
      return { recipe: null, error: 'This recipe no longer exists.' };
    }
    if (e instanceof ApiError && e.kind === 'unauthorized') {
      return { recipe: null, error: 'Your session expired. Sign in again from Settings.' };
    }
    return { recipe: null, error: 'Could not load this recipe.' };
  }
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View className="mt-6">
      <Text className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
        {title}
      </Text>
      {children}
    </View>
  );
}

export function RecipeDetailScreen({ route }: Props) {
  const { id } = route.params;
  const { token } = useAuth();
  const [recipe, setRecipe] = useState<Recipe | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const result = await loadRecipe(token, id);
      if (cancelled) return;
      setRecipe(result.recipe);
      setError(result.error);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [token, id]);

  const reload = useCallback(async () => {
    setLoading(true);
    const result = await loadRecipe(token, id);
    setRecipe(result.recipe);
    setError(result.error);
    setLoading(false);
  }, [token, id]);

  if (loading) {
    return (
      <View className="flex-1 items-center justify-center bg-white">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  if (error || !recipe) {
    return (
      <View className="flex-1 items-center justify-center bg-white px-8">
        <Text className="text-center text-base text-red-600">{error ?? 'Recipe unavailable.'}</Text>
        <Pressable
          accessibilityRole="button"
          onPress={reload}
          className="mt-4 rounded-lg bg-gray-900 px-5 py-2.5 active:opacity-80"
        >
          <Text className="font-semibold text-white">Retry</Text>
        </Pressable>
      </View>
    );
  }

  const meta = [
    recipe.prep_time_minutes > 0 ? `Prep ${recipe.prep_time_minutes} min` : null,
    recipe.cook_time_minutes > 0 ? `Cook ${recipe.cook_time_minutes} min` : null,
    recipe.servings > 0 ? `${recipe.servings} servings` : null,
    recipe.cuisine.trim() || null,
    recipe.course.trim() || null,
    recipe.difficulty.trim() || null,
  ].filter((s): s is string => s !== null);

  const tags = parseTags(recipe.tags);
  const ingredients = sortedIngredients(recipe.ingredients);
  const sourceUrl = recipe.source_url.trim();

  return (
    <ScrollView className="flex-1 bg-white" contentContainerStyle={{ padding: 16 }}>
      {recipe.summary.trim().length > 0 ? (
        <Text className="text-base leading-6 text-gray-700">{recipe.summary}</Text>
      ) : null}

      {meta.length > 0 ? <Text className="mt-3 text-sm text-gray-500">{meta.join(' · ')}</Text> : null}

      {sourceUrl.length > 0 ? (
        isHttpUrl(sourceUrl) ? (
          <Pressable
            accessibilityRole="link"
            onPress={() => Linking.openURL(sourceUrl)}
            className="mt-2 active:opacity-60"
          >
            <Text className="text-sm text-blue-600">Source: {sourceUrl}</Text>
          </Pressable>
        ) : (
          <Text className="mt-2 text-sm text-gray-500">Source: {sourceUrl}</Text>
        )
      ) : null}

      {tags.length > 0 ? (
        <View className="mt-3 flex-row flex-wrap">
          {tags.map((tag) => (
            <Text
              key={tag}
              className="mb-2 mr-2 rounded-full bg-gray-100 px-3 py-1 text-xs text-gray-600"
            >
              {tag}
            </Text>
          ))}
        </View>
      ) : null}

      {ingredients.length > 0 ? (
        <Section title="Ingredients">
          {ingredients.map((ing) => (
            <View key={ing.id} className="flex-row py-1">
              <Text className="mr-2 text-gray-400">•</Text>
              <Text className="flex-1 text-base text-gray-800">{formatIngredient(ing)}</Text>
            </View>
          ))}
        </Section>
      ) : null}

      {recipe.instructions.trim().length > 0 ? (
        <Section title="Instructions">
          <Text className="text-base leading-6 text-gray-800">{recipe.instructions}</Text>
        </Section>
      ) : null}
    </ScrollView>
  );
}
