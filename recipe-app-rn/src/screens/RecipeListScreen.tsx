import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from 'react-native';

import { fetchRecipes } from '../api/recipes';
import { useAuth } from '../contexts/AuthContext';
import { ApiError } from '../lib/apiClient';
import { totalTimeMinutes } from '../lib/recipeFormat';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import type { Recipe } from '../types/recipe';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipesHome'>;

type ListResult = { recipes: Recipe[]; error: string | null };

/** Pure loader (no setState) so the effect can set state only after `await`. */
async function loadRecipes(token: string): Promise<ListResult> {
  try {
    return { recipes: await fetchRecipes(token), error: null };
  } catch (e) {
    if (e instanceof ApiError && e.kind === 'unauthorized') {
      return { recipes: [], error: 'Your session expired. Sign in again from Settings.' };
    }
    return { recipes: [], error: 'Could not load recipes. Pull down to retry.' };
  }
}

function RecipeRow({ recipe, onPress }: { recipe: Recipe; onPress: () => void }) {
  const meta = [
    totalTimeMinutes(recipe) > 0 ? `${totalTimeMinutes(recipe)} min` : null,
    recipe.cuisine.trim() || null,
    recipe.course.trim() || null,
    recipe.servings > 0 ? `${recipe.servings} servings` : null,
  ].filter((s): s is string => s !== null);

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      className="border-b border-gray-100 px-4 py-3 active:bg-gray-50"
    >
      <View className="flex-row items-center">
        <Text className="flex-1 text-lg font-semibold text-gray-900" numberOfLines={1}>
          {recipe.name}
        </Text>
        {recipe.is_favorite ? <Ionicons name="star" size={18} color="#f59e0b" /> : null}
      </View>
      {recipe.summary.trim().length > 0 ? (
        <Text className="mt-1 text-sm text-gray-500" numberOfLines={2}>
          {recipe.summary}
        </Text>
      ) : null}
      {meta.length > 0 ? <Text className="mt-1 text-xs text-gray-400">{meta.join(' · ')}</Text> : null}
    </Pressable>
  );
}

function CenteredMessage({ children }: { children: React.ReactNode }) {
  return <View className="flex-1 items-center justify-center px-8">{children}</View>;
}

export function RecipeListScreen({ navigation }: Props) {
  const { token, isGuest } = useAuth();
  const [recipes, setRecipes] = useState<Recipe[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Initial load: set state only after the awaited fetch resolves.
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    (async () => {
      const result = await loadRecipes(token);
      if (cancelled) return;
      setRecipes(result.recipes);
      setError(result.error);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [token]);

  // Event-handler reloads (retry / pull-to-refresh) may set state synchronously.
  const reload = useCallback(
    async (mode: 'retry' | 'refresh') => {
      if (!token) return;
      if (mode === 'refresh') setRefreshing(true);
      else setLoading(true);
      const result = await loadRecipes(token);
      setRecipes(result.recipes);
      setError(result.error);
      setRefreshing(false);
      setLoading(false);
    },
    [token],
  );

  if (isGuest || !token) {
    return (
      <CenteredMessage>
        <Text className="text-center text-base text-gray-500">
          Sign in to browse recipes from the server.
        </Text>
      </CenteredMessage>
    );
  }

  if (loading) {
    return (
      <CenteredMessage>
        <ActivityIndicator size="large" color="#111827" />
      </CenteredMessage>
    );
  }

  if (error && recipes.length === 0) {
    return (
      <CenteredMessage>
        <Text className="text-center text-base text-red-600">{error}</Text>
        <Pressable
          accessibilityRole="button"
          onPress={() => reload('retry')}
          className="mt-4 rounded-lg bg-gray-900 px-5 py-2.5 active:opacity-80"
        >
          <Text className="font-semibold text-white">Retry</Text>
        </Pressable>
      </CenteredMessage>
    );
  }

  return (
    <FlatList
      data={recipes}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <RecipeRow
          recipe={item}
          onPress={() => navigation.navigate('RecipeDetail', { id: item.id, name: item.name })}
        />
      )}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => reload('refresh')} />}
      ListEmptyComponent={
        <CenteredMessage>
          <Text className="text-center text-base text-gray-500">No recipes yet.</Text>
        </CenteredMessage>
      }
      contentContainerStyle={recipes.length === 0 ? { flex: 1 } : undefined}
    />
  );
}
