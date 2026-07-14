import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';

import { useSync } from '../contexts/SyncContext';
import { importedRecipeToDraft } from '../lib/recipeImport';
import type { RecipesStackParamList } from '../navigation/RecipesStack';

type Props = NativeStackScreenProps<RecipesStackParamList, 'ImportReview'>;

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View className="mt-6">
      <Text className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">{title}</Text>
      {children}
    </View>
  );
}

/** A label/value row, mirroring the SwiftUI `LabeledContent` rows in the review sheet. */
function Row({ label, value }: { label: string; value: string }) {
  return (
    <View className="flex-row items-start justify-between border-b border-gray-100 py-2">
      <Text className="mr-4 text-sm text-gray-500">{label}</Text>
      <Text className="flex-1 text-right text-sm text-gray-900" numberOfLines={2}>
        {value}
      </Text>
    </View>
  );
}

/**
 * Reviews a recipe parsed from a URL before it is saved — a React Native port
 * of the SwiftUI `ImportReviewView`. Receives the already-parsed
 * {@link ImportedRecipe} via route params (the manual "Import from URL" flow
 * parses it on the list screen; future share entry points will navigate here
 * the same way). "Discard" pops back; "Import" builds the create draft via
 * {@link importedRecipeToDraft}, saves through the offline-first store
 * ({@link useSync}.createRecipe), and replaces this screen with the new
 * recipe's detail view.
 */
export function ImportReviewScreen({ route, navigation }: Props) {
  const { recipe } = route.params;
  const { createRecipe } = useSync();
  const [saving, setSaving] = useState(false);

  const onImport = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try {
      const draft = importedRecipeToDraft(recipe);
      const localId = await createRecipe(draft);
      // Replace the review with the detail so Back returns to the list, not here.
      navigation.replace('RecipeDetail', { localId, name: draft.name });
    } catch {
      setSaving(false); // stay on the review so the user can retry
    }
  }, [saving, recipe, createRecipe, navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerLeft: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Discard import"
          onPress={() => navigation.goBack()}
          className="active:opacity-60"
        >
          <Text className="text-base text-gray-500">Discard</Text>
        </Pressable>
      ),
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Import recipe"
          disabled={saving}
          onPress={onImport}
          className="active:opacity-60"
        >
          <Text className={saving ? 'text-base text-gray-400' : 'text-base font-semibold text-blue-600'}>
            {saving ? 'Importing…' : 'Import'}
          </Text>
        </Pressable>
      ),
    });
  }, [navigation, onImport, saving]);

  const detail: { label: string; value: string }[] = [
    { label: 'Name', value: recipe.title },
    recipe.cuisine.trim() ? { label: 'Cuisine', value: recipe.cuisine } : null,
    recipe.course.trim() ? { label: 'Course', value: recipe.course } : null,
    recipe.servings != null ? { label: 'Servings', value: String(recipe.servings) } : null,
    recipe.prepTimeMinutes != null ? { label: 'Prep Time', value: `${recipe.prepTimeMinutes} min` } : null,
    recipe.cookTimeMinutes != null ? { label: 'Cook Time', value: `${recipe.cookTimeMinutes} min` } : null,
    recipe.sourceURL.trim() ? { label: 'Source', value: recipe.sourceURL } : null,
  ].filter((r): r is { label: string; value: string } => r !== null);

  return (
    <ScrollView className="flex-1 bg-white" contentContainerStyle={{ padding: 16 }}>
      <Section title="Recipe">
        {detail.map((r) => (
          <Row key={r.label} label={r.label} value={r.value} />
        ))}
      </Section>

      <Section title={`Ingredients (${recipe.ingredients.length})`}>
        {recipe.ingredients.map((ing, i) => (
          <View key={i} className="flex-row py-1">
            <Text className="mr-2 text-gray-400">•</Text>
            <Text className="flex-1 text-base text-gray-800">{ing}</Text>
          </View>
        ))}
      </Section>

      {recipe.instructions.length > 0 ? (
        <Section title={`Instructions (${recipe.instructions.length} steps)`}>
          {recipe.instructions.map((step, i) => (
            <View key={i} className="flex-row py-1">
              <Text className="mr-2 w-6 text-right text-gray-400">{i + 1}.</Text>
              <Text className="flex-1 text-base text-gray-800">{step}</Text>
            </View>
          ))}
        </Section>
      ) : null}
    </ScrollView>
  );
}
