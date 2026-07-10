import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, Text, View } from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { useSync } from '../contexts/SyncContext';
import { totalTimeMinutes } from '../lib/recipeFormat';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import type { LocalRecipe } from '../sync/types';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipesHome'>;

function RecipeRow({ recipe, onPress }: { recipe: LocalRecipe; onPress: () => void }) {
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
        {recipe.needsSync ? <Ionicons name="cloud-upload-outline" size={16} color="#9ca3af" /> : null}
        {recipe.is_favorite ? (
          <Ionicons name="star" size={18} color="#f59e0b" style={{ marginLeft: 6 }} />
        ) : null}
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

/**
 * Offline-first recipe list (Phase 3). Reads exclusively from the local store
 * via {@link useSync}; pull-to-refresh triggers a server sync. Guests see a gate
 * (no token, no sync). Banners surface a non-fatal sync error and any unpushed
 * writes without blocking the local view.
 */
export function RecipeListScreen({ navigation }: Props) {
  const { token, isGuest } = useAuth();
  const { recipes, initializing, syncing, error, hasWriteFailures, syncNow } = useSync();

  if (isGuest || !token) {
    return (
      <CenteredMessage>
        <Text className="text-center text-base text-gray-500">
          Sign in to browse recipes from the server.
        </Text>
      </CenteredMessage>
    );
  }

  if (initializing) {
    return (
      <CenteredMessage>
        <ActivityIndicator size="large" color="#111827" />
      </CenteredMessage>
    );
  }

  return (
    <View className="flex-1">
      {error ? (
        <View className="bg-red-50 px-4 py-2">
          <Text className="text-center text-xs text-red-700">{error}</Text>
        </View>
      ) : hasWriteFailures ? (
        <View className="bg-amber-50 px-4 py-2">
          <Text className="text-center text-xs text-amber-800">
            Some changes haven’t synced yet — will retry.
          </Text>
        </View>
      ) : null}
      <FlatList
        data={recipes}
        keyExtractor={(item) => item.localId}
        renderItem={({ item }) => (
          <RecipeRow
            recipe={item}
            onPress={() =>
              navigation.navigate('RecipeDetail', { localId: item.localId, name: item.name })
            }
          />
        )}
        refreshControl={<RefreshControl refreshing={syncing} onRefresh={syncNow} />}
        ListEmptyComponent={
          <CenteredMessage>
            <Text className="text-center text-base text-gray-500">
              No recipes yet. Pull down to sync.
            </Text>
          </CenteredMessage>
        }
        contentContainerStyle={recipes.length === 0 ? { flex: 1 } : undefined}
      />
    </View>
  );
}
