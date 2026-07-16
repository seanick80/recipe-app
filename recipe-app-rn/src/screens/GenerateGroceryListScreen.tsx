import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { FlatList, Pressable, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import { useSync } from '../contexts/SyncContext';
import type { GenerateRecipe } from '../grocery/types';
import type { ShoppingStackParamList } from '../navigation/ShoppingStack';
import type { LocalRecipe } from '../sync/types';
import { colors } from '../theme/tokens';

type Props = NativeStackScreenProps<ShoppingStackParamList, 'GenerateGroceryList'>;

/** LocalRecipe → the generate input shape (server id preferred as stable id). */
function toGenerateRecipe(r: LocalRecipe): GenerateRecipe {
  return {
    id: r.serverId ?? r.localId,
    name: r.name,
    ingredients: r.ingredients.map((i) => ({
      name: i.name,
      quantity: i.quantity,
      unit: i.unit,
      category: i.category,
    })),
  };
}

/**
 * Generate-from-recipes: pick recipes, and their ingredients are consolidated
 * (prep-note-stripped, categorized, quantity-summed) and appended into the
 * single persistent shopping list. Ported from SwiftUI `GenerateGroceryListView`.
 */
export function GenerateGroceryListScreen({ navigation }: Props) {
  const { recipes } = useSync();
  const { generate } = useGrocery();
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const toggle = useCallback((localId: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(localId)) next.delete(localId);
      else next.add(localId);
      return next;
    });
  }, []);

  const chosen = useMemo(() => recipes.filter((r) => selected.has(r.localId)), [recipes, selected]);

  const onGenerate = useCallback(async () => {
    if (chosen.length === 0) return;
    await generate(chosen.map(toGenerateRecipe));
    navigation.goBack();
  }, [chosen, generate, navigation]);

  useLayoutEffect(() => {
    const canGenerate = chosen.length > 0;
    navigation.setOptions({
      headerRight: () => (
        <Pressable accessibilityRole="button" disabled={!canGenerate} onPress={onGenerate}>
          <Text className={canGenerate ? 'text-base font-semibold text-app-primary' : 'text-base text-app-text-disabled'}>
            Generate
          </Text>
        </Pressable>
      ),
    });
  }, [navigation, chosen.length, onGenerate]);

  if (recipes.length === 0) {
    return (
      <View className="flex-1 items-center justify-center bg-app-surface px-8">
        <Text className="text-center text-base text-app-text-secondary">
          No recipes to generate from. Add recipes first (sign in to sync them).
        </Text>
      </View>
    );
  }

  return (
    <FlatList
      className="bg-app-surface"
      data={recipes}
      keyExtractor={(item) => item.localId}
      ListHeaderComponent={
        <Text className="px-4 py-3 text-sm text-app-text-secondary">
          Select recipes to add their ingredients to your shopping list.
        </Text>
      }
      renderItem={({ item }) => {
        const isSelected = selected.has(item.localId);
        return (
          <Pressable
            accessibilityRole="checkbox"
            accessibilityState={{ checked: isSelected }}
            onPress={() => toggle(item.localId)}
            className="flex-row items-center border-b border-app-border-subtle px-4 py-3 active:bg-app-background"
          >
            <Ionicons
              name={isSelected ? 'checkbox' : 'square-outline'}
              size={22}
              color={isSelected ? colors.primary : colors.textDisabled}
            />
            <Text className="ml-3 flex-1 text-base text-app-text-primary" numberOfLines={1}>
              {item.name}
            </Text>
            <Text className="ml-2 text-xs text-app-text-muted">
              {item.ingredients.length} ingredient{item.ingredients.length === 1 ? '' : 's'}
            </Text>
          </Pressable>
        );
      }}
    />
  );
}
