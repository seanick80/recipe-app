import { Ionicons } from '@expo/vector-icons';
import { Alert, FlatList, Pressable, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import type { GroceryList } from '../grocery/types';

/**
 * Archived grocery lists (Phase 4 slice 3b) — port of SwiftUI `ArchivedListsView`.
 * Lists are archived (not deleted) by merge or manually; restore returns one to
 * the active set. Long-press deletes for good.
 */
export function ArchivedListsScreen() {
  const { archivedLists, setArchived, deleteList } = useGrocery();

  const confirmDelete = (list: GroceryList) =>
    Alert.alert('Delete list?', `“${list.name}” will be removed for good.`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Delete', style: 'destructive', onPress: () => void deleteList(list.id) },
    ]);

  return (
    <FlatList
      className="bg-gray-50"
      data={archivedLists}
      keyExtractor={(item) => item.id}
      renderItem={({ item }) => (
        <View className="mx-4 mt-2 flex-row items-center justify-between rounded-lg border border-gray-100 bg-white px-4 py-3">
          <Pressable className="flex-1 active:opacity-60" onLongPress={() => confirmDelete(item)}>
            <Text className="text-base text-gray-900" numberOfLines={1}>
              {item.name}
            </Text>
            <Text className="mt-0.5 text-xs text-gray-400">{item.items.length} items</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Restore ${item.name}`}
            onPress={() => void setArchived(item.id, false)}
            className="ml-3 flex-row items-center active:opacity-60"
          >
            <Ionicons name="arrow-undo-outline" size={18} color="#2563eb" />
            <Text className="ml-1 text-sm font-semibold text-blue-600">Restore</Text>
          </Pressable>
        </View>
      )}
      ListEmptyComponent={
        <View className="items-center px-8 pt-10">
          <Text className="text-center text-base text-gray-500">No archived lists.</Text>
        </View>
      }
    />
  );
}
