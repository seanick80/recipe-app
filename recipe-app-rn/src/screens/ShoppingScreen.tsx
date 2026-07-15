import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect } from 'react';
import { Alert, Pressable, Text, View } from 'react-native';

import { GroceryListBody } from '../components/GroceryListBody';
import { useGrocery } from '../contexts/GroceryContext';
import { allItemsChecked } from '../grocery/groceryLogic';
import type { ShoppingStackParamList } from '../navigation/ShoppingStack';

type Props = NativeStackScreenProps<ShoppingStackParamList, 'ShoppingHome'>;

/**
 * Shopping tab (Phase 4 slice 3b) — the staples workflow, a port of SwiftUI
 * `ShoppingListTab`. Operates on the first active list: add/edit reusable
 * staples, merge all active lists, and reach archived lists. Reuses the shared
 * {@link GroceryListBody} for the item UI.
 */
export function ShoppingScreen({ navigation }: Props) {
  const { activeLists, archivedLists, ensureDefaultTemplate, addStaples, mergeLists, createList, setAllChecked } =
    useGrocery();
  const active = activeLists[0];
  const allChecked = allItemsChecked(active?.items ?? []);

  const addStaplesTo = useCallback(
    async (listId: string) => {
      const template = await ensureDefaultTemplate();
      if (template.items.length === 0) {
        Alert.alert('No staples yet', 'Add some in "Edit Staples" first.');
        return;
      }
      const added = await addStaples(listId, template.id);
      Alert.alert(added > 0 ? `Added ${added} item${added === 1 ? '' : 's'}` : 'Already stocked', undefined);
    },
    [ensureDefaultTemplate, addStaples],
  );

  const editStaples = useCallback(async () => {
    const template = await ensureDefaultTemplate();
    navigation.navigate('TemplateEditor', { templateId: template.id });
  }, [ensureDefaultTemplate, navigation]);

  const startWithStaples = useCallback(async () => {
    const id = await createList('Groceries');
    await addStaplesTo(id);
  }, [createList, addStaplesTo]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Shopping actions"
          onPress={() => {
            const buttons: { text: string; style?: 'cancel' | 'destructive'; onPress?: () => void }[] = [];
            if (active) {
              buttons.push({ text: 'Add staples', onPress: () => void addStaplesTo(active.id) });
              buttons.push({
                text: allChecked ? 'Uncheck all' : 'Check all',
                onPress: () => void setAllChecked(active.id, !allChecked),
              });
            }
            buttons.push({ text: 'Edit staples', onPress: () => void editStaples() });
            if (activeLists.length > 1) {
              buttons.push({
                text: `Merge ${activeLists.length} active lists`,
                onPress: () => void mergeLists(activeLists.map((l) => l.id), activeLists[0].id),
              });
            }
            buttons.push({
              text: `Archived lists${archivedLists.length ? ` (${archivedLists.length})` : ''}`,
              onPress: () => navigation.navigate('ArchivedLists'),
            });
            buttons.push({ text: 'Cancel', style: 'cancel' });
            Alert.alert('Shopping', undefined, buttons);
          }}
          className="active:opacity-60"
        >
          <Ionicons name="ellipsis-horizontal" size={22} color="#2563eb" />
        </Pressable>
      ),
    });
  }, [
    navigation,
    active,
    activeLists,
    archivedLists.length,
    allChecked,
    setAllChecked,
    addStaplesTo,
    editStaples,
    mergeLists,
  ]);

  if (!active) {
    return (
      <View className="flex-1 items-center justify-center bg-gray-50 px-8">
        <Text className="mb-6 text-center text-base text-gray-500">
          No active shopping list. Start one from your weekly staples.
        </Text>
        <Pressable
          accessibilityRole="button"
          onPress={startWithStaples}
          className="mb-3 w-full items-center rounded-lg bg-gray-900 px-4 py-3 active:opacity-80"
        >
          <Text className="font-semibold text-white">Add staples to a new list</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          onPress={() => void createList('Groceries')}
          className="w-full items-center rounded-lg border border-gray-300 px-4 py-3 active:bg-gray-100"
        >
          <Text className="font-semibold text-gray-900">New empty list</Text>
        </Pressable>
        <Pressable accessibilityRole="button" onPress={() => void editStaples()} className="mt-6 active:opacity-60">
          <Text className="text-sm font-semibold text-blue-600">Edit weekly staples</Text>
        </Pressable>
      </View>
    );
  }

  return <GroceryListBody listId={active.id} />;
}
