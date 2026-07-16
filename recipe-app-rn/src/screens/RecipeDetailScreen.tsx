import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect } from 'react';
import { Alert, Linking, Pressable, ScrollView, Share, Text, View } from 'react-native';

import { WEB_BASE_URL } from '../config';
import { useSync } from '../contexts/SyncContext';
import { formatIngredient, isHttpUrl, parseTags, sortedIngredients } from '../lib/recipeFormat';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import { localToDraft } from '../sync/recipeDraft';
import { colors } from '../theme/tokens';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipeDetail'>;

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View className="mt-6">
      <Text className="mb-2 text-xs font-semibold uppercase tracking-wide text-app-text-muted">
        {title}
      </Text>
      {children}
    </View>
  );
}

/**
 * Read-only recipe detail (Phase 3). Reads from the local store via
 * {@link useSync} — no network fetch — so it works offline and reflects the
 * last sync. Editing lands in Phase 4.
 */
export function RecipeDetailScreen({ route, navigation }: Props) {
  const { localId } = route.params;
  const { getByLocalId, deleteRecipe, updateRecipe } = useSync();
  const recipe = getByLocalId(localId);

  // Share a public link to the recipe. Sharing makes the recipe publicly
  // viewable (unauthenticated) at ${WEB_BASE_URL}/recipes/{serverId}: on first
  // share we flip is_published=true through the normal update/sync path so it
  // propagates to the server. A recipe with no serverId hasn't synced yet — the
  // public link can't exist, so we block with a clear message.
  const onShare = useCallback(async () => {
    if (!recipe) return;
    if (!recipe.serverId) {
      Alert.alert(
        'Sync required',
        'This recipe hasn’t synced to the cloud yet, so it has no shareable link. Pull to refresh on the recipe list to sync, then try sharing again.',
      );
      return;
    }
    try {
      if (!recipe.is_published) {
        await updateRecipe(localId, { ...localToDraft(recipe), is_published: true });
      }
      const url = `${WEB_BASE_URL}/recipes/${recipe.serverId}`;
      await Share.share({ url, message: `${recipe.name}\n${url}` });
    } catch {
      Alert.alert('Could not share', 'Something went wrong preparing the share link.');
    }
  }, [recipe, localId, updateRecipe]);

  const onDelete = useCallback(() => {
    Alert.alert('Delete recipe?', `“${recipe?.name ?? 'This recipe'}” will be removed.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await deleteRecipe(localId);
          navigation.goBack();
        },
      },
    ]);
  }, [deleteRecipe, localId, navigation, recipe?.name]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: recipe
        ? () => (
            <View className="flex-row items-center">
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Share recipe"
                onPress={onShare}
                className="mr-4 active:opacity-60"
              >
                <Ionicons name="share-outline" size={24} color={colors.primary} />
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Edit recipe"
                onPress={() => navigation.navigate('RecipeEdit', { localId })}
                className="mr-4 active:opacity-60"
              >
                <Ionicons name="create-outline" size={24} color={colors.primary} />
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Delete recipe"
                onPress={onDelete}
                className="active:opacity-60"
              >
                <Ionicons name="trash-outline" size={22} color={colors.danger} />
              </Pressable>
            </View>
          )
        : undefined,
    });
  }, [navigation, recipe, localId, onDelete, onShare]);

  if (!recipe) {
    return (
      <View className="flex-1 items-center justify-center bg-app-surface px-8">
        <Text className="text-center text-base text-app-text-secondary">This recipe is no longer available.</Text>
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
    <ScrollView className="flex-1 bg-app-surface" contentContainerStyle={{ padding: 16 }}>
      {recipe.summary.trim().length > 0 ? (
        <Text className="text-base leading-6 text-app-text-secondary-strong">{recipe.summary}</Text>
      ) : null}

      {meta.length > 0 ? <Text className="mt-3 text-sm text-app-text-secondary">{meta.join(' · ')}</Text> : null}

      {sourceUrl.length > 0 ? (
        isHttpUrl(sourceUrl) ? (
          <Pressable
            accessibilityRole="link"
            onPress={() => Linking.openURL(sourceUrl)}
            className="mt-2 active:opacity-60"
          >
            <Text className="text-sm text-app-primary">Source: {sourceUrl}</Text>
          </Pressable>
        ) : (
          <Text className="mt-2 text-sm text-app-text-secondary">Source: {sourceUrl}</Text>
        )
      ) : null}

      {tags.length > 0 ? (
        <View className="mt-3 flex-row flex-wrap">
          {tags.map((tag) => (
            <Text
              key={tag}
              className="mb-2 mr-2 rounded-full bg-app-chip-bg px-3 py-1 text-xs text-app-text-secondary-mid"
            >
              {tag}
            </Text>
          ))}
        </View>
      ) : null}

      {ingredients.length > 0 ? (
        <Section title="Ingredients">
          {ingredients.map((ing, i) => (
            <View key={`${ing.display_order}-${i}`} className="flex-row py-1">
              <Text className="mr-2 text-app-text-muted">•</Text>
              <Text className="flex-1 text-base text-app-text-body">{formatIngredient(ing)}</Text>
            </View>
          ))}
        </Section>
      ) : null}

      {recipe.instructions.trim().length > 0 ? (
        <Section title="Instructions">
          <Text className="text-base leading-6 text-app-text-body">{recipe.instructions}</Text>
        </Section>
      ) : null}
    </ScrollView>
  );
}
