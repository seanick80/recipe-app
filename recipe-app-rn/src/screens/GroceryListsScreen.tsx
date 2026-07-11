import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect } from 'react';
import { ActivityIndicator, Alert, FlatList, Pressable, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import type { GroceryList } from '../grocery/types';
import type { ListsStackParamList } from '../navigation/ListsStack';

type Props = NativeStackScreenProps<ListsStackParamList, 'ListsHome'>;

function subtitle(list: GroceryList): string {
  const total = list.items.length;
  const done = list.items.filter((i) => i.isChecked).length;
  if (total === 0) return 'Empty';
  return `${total} item${total === 1 ? '' : 's'} · ${done} done`;
}

/**
 * Grocery "Lists" tab (Phase 4 slice 3) — the full list manager. Shows all
 * active lists, creates new ones, and launches generate-from-recipes. Local-only
 * (no auth gate). Rename lives in the detail screen; long-press deletes here.
 */
export function GroceryListsScreen({ navigation }: Props) {
  const { activeLists, initializing, createList, deleteList } = useGrocery();

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="New list"
          onPress={async () => {
            const id = await createList('Grocery List');
            navigation.navigate('GroceryListDetail', { listId: id, name: 'Grocery List' });
          }}
          className="active:opacity-60"
        >
          <Ionicons name="add" size={28} color="#2563eb" />
        </Pressable>
      ),
    });
  }, [navigation, createList]);

  const confirmDelete = useCallback(
    (list: GroceryList) => {
      Alert.alert('Delete list?', `“${list.name}” and its items will be removed.`, [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: () => void deleteList(list.id) },
      ]);
    },
    [deleteList],
  );

  if (initializing) {
    return (
      <View className="flex-1 items-center justify-center">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  return (
    <View className="flex-1 bg-gray-50">
      <Pressable
        accessibilityRole="button"
        onPress={() => navigation.navigate('GenerateGroceryList')}
        className="m-4 flex-row items-center justify-center rounded-lg bg-gray-900 px-4 py-3 active:opacity-80"
      >
        <Ionicons name="sparkles-outline" size={18} color="#fff" />
        <Text className="ml-2 font-semibold text-white">Generate from Recipes</Text>
      </Pressable>

      <FlatList
        data={activeLists}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <Pressable
            accessibilityRole="button"
            onPress={() => navigation.navigate('GroceryListDetail', { listId: item.id, name: item.name })}
            onLongPress={() => confirmDelete(item)}
            className="mx-4 mb-2 rounded-lg border border-gray-100 bg-white px-4 py-3 active:bg-gray-50"
          >
            <View className="flex-row items-center justify-between">
              <Text className="flex-1 text-base font-semibold text-gray-900" numberOfLines={1}>
                {item.name}
              </Text>
              <Ionicons name="chevron-forward" size={18} color="#d1d5db" />
            </View>
            <Text className="mt-0.5 text-xs text-gray-400">{subtitle(item)}</Text>
          </Pressable>
        )}
        ListEmptyComponent={
          <View className="items-center px-8 pt-10">
            <Text className="text-center text-base text-gray-500">
              No lists yet. Add one with + or generate from your recipes.
            </Text>
          </View>
        }
      />
    </View>
  );
}
