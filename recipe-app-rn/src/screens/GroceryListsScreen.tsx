import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useState } from 'react';
import { ActivityIndicator, Alert, FlatList, Pressable, Text, View } from 'react-native';

import { PromptModal } from '../components/PromptModal';
import { useGrocery } from '../contexts/GroceryContext';
import { planListMerge } from '../grocery/groceryLogic';
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
 * (no auth gate). A row long-press offers Rename / Delete; a Select mode lets the
 * user pick multiple lists and merge them into one (via {@link planListMerge} +
 * `mergeLists`, mirroring the Shopping tab — the target is the first selected
 * list, the rest are archived after their items merge in).
 */
export function GroceryListsScreen({ navigation }: Props) {
  const { activeLists, initializing, createList, deleteList, renameList, mergeLists } = useGrocery();

  const [selecting, setSelecting] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [renameTarget, setRenameTarget] = useState<GroceryList | null>(null);

  const exitSelection = useCallback(() => {
    setSelecting(false);
    setSelected(new Set());
  }, []);

  const toggleSelected = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const doMerge = useCallback(() => {
    const plan = planListMerge(
      activeLists.map((l) => l.id),
      selected,
    );
    if (!plan) {
      Alert.alert('Select at least two lists', 'Pick two or more lists to merge.');
      return;
    }
    const target = activeLists.find((l) => l.id === plan.targetId);
    Alert.alert(
      'Merge lists?',
      `${plan.sourceIds.length + 1} lists will be combined into “${target?.name ?? 'the first list'}”. The others are archived.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Merge',
          onPress: () => {
            void mergeLists(plan.sourceIds, plan.targetId);
            exitSelection();
          },
        },
      ],
    );
  }, [activeLists, selected, mergeLists, exitSelection]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerLeft: selecting
        ? () => (
            <Pressable accessibilityRole="button" onPress={exitSelection} className="active:opacity-60">
              <Text className="text-base text-blue-600">Cancel</Text>
            </Pressable>
          )
        : undefined,
      headerRight: () =>
        selecting ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Merge selected lists"
            onPress={doMerge}
            className="active:opacity-60"
          >
            <Text className="text-base font-semibold text-blue-600">
              Merge{selected.size > 0 ? ` (${selected.size})` : ''}
            </Text>
          </Pressable>
        ) : (
          <View className="flex-row items-center gap-4">
            {activeLists.length > 1 ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Select lists to merge"
                onPress={() => setSelecting(true)}
                className="active:opacity-60"
              >
                <Text className="text-base text-blue-600">Select</Text>
              </Pressable>
            ) : null}
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
          </View>
        ),
    });
  }, [navigation, createList, selecting, selected.size, activeLists, doMerge, exitSelection]);

  const rowActions = useCallback(
    (list: GroceryList) => {
      Alert.alert(list.name, undefined, [
        { text: 'Rename', onPress: () => setRenameTarget(list) },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () =>
            Alert.alert('Delete list?', `“${list.name}” and its items will be removed.`, [
              { text: 'Cancel', style: 'cancel' },
              { text: 'Delete', style: 'destructive', onPress: () => void deleteList(list.id) },
            ]),
        },
        { text: 'Cancel', style: 'cancel' },
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
      {selecting ? (
        <View className="bg-gray-100 px-4 py-2">
          <Text className="text-center text-sm text-gray-500">
            Select lists to merge into the first chosen list.
          </Text>
        </View>
      ) : (
        <Pressable
          accessibilityRole="button"
          onPress={() => navigation.navigate('GenerateGroceryList')}
          className="m-4 flex-row items-center justify-center rounded-lg bg-gray-900 px-4 py-3 active:opacity-80"
        >
          <Ionicons name="sparkles-outline" size={18} color="#fff" />
          <Text className="ml-2 font-semibold text-white">Generate from Recipes</Text>
        </Pressable>
      )}

      <FlatList
        data={activeLists}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => {
          const isSelected = selected.has(item.id);
          return (
            <Pressable
              accessibilityRole={selecting ? 'checkbox' : 'button'}
              accessibilityState={selecting ? { checked: isSelected } : undefined}
              onPress={() => {
                if (selecting) toggleSelected(item.id);
                else navigation.navigate('GroceryListDetail', { listId: item.id, name: item.name });
              }}
              onLongPress={() => {
                if (!selecting) rowActions(item);
              }}
              className={`mx-4 mb-2 rounded-lg border bg-white px-4 py-3 active:bg-gray-50 ${
                isSelected ? 'border-blue-500' : 'border-gray-100'
              }`}
            >
              <View className="flex-row items-center justify-between">
                {selecting ? (
                  <Ionicons
                    name={isSelected ? 'checkmark-circle' : 'ellipse-outline'}
                    size={22}
                    color={isSelected ? '#2563eb' : '#d1d5db'}
                  />
                ) : null}
                <Text
                  className={`flex-1 text-base font-semibold text-gray-900 ${selecting ? 'ml-3' : ''}`}
                  numberOfLines={1}
                >
                  {item.name}
                </Text>
                {selecting ? null : <Ionicons name="chevron-forward" size={18} color="#d1d5db" />}
              </View>
              <Text className={`mt-0.5 text-xs text-gray-400 ${selecting ? 'ml-9' : ''}`}>{subtitle(item)}</Text>
            </Pressable>
          );
        }}
        ListEmptyComponent={
          <View className="items-center px-8 pt-10">
            <Text className="text-center text-base text-gray-500">
              No lists yet. Add one with + or generate from your recipes.
            </Text>
          </View>
        }
      />

      <PromptModal
        visible={renameTarget !== null}
        title="Rename list"
        initialValue={renameTarget?.name ?? ''}
        placeholder="List name"
        onSubmit={(name) => {
          if (renameTarget) void renameList(renameTarget.id, name);
          setRenameTarget(null);
        }}
        onCancel={() => setRenameTarget(null)}
      />
    </View>
  );
}
