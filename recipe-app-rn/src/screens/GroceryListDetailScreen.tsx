import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useLayoutEffect, useState } from 'react';
import { Alert, Pressable } from 'react-native';

import { GroceryListBody } from '../components/GroceryListBody';
import { PromptModal } from '../components/PromptModal';
import { useGrocery } from '../contexts/GroceryContext';
import type { ListsStackParamList } from '../navigation/ListsStack';

type Props = NativeStackScreenProps<ListsStackParamList, 'GroceryListDetail'>;

/**
 * A single grocery list (Phase 4 slice 3). Renders the shared
 * {@link GroceryListBody} (grouped, checkable items + inline add) and adds a
 * header menu for rename / uncheck-all / remove-checked / clear.
 */
export function GroceryListDetailScreen({ route, navigation }: Props) {
  const { listId } = route.params;
  const { getList, renameList, uncheckAll, removeChecked, clearItems } = useGrocery();
  const [renaming, setRenaming] = useState(false);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="List actions"
          onPress={() =>
            Alert.alert('List actions', undefined, [
              { text: 'Rename list', onPress: () => setRenaming(true) },
              { text: 'Uncheck all', onPress: () => void uncheckAll(listId) },
              { text: 'Remove checked', onPress: () => void removeChecked(listId) },
              {
                text: 'Clear all',
                style: 'destructive',
                onPress: () =>
                  Alert.alert('Clear all items?', undefined, [
                    { text: 'Cancel', style: 'cancel' },
                    { text: 'Clear', style: 'destructive', onPress: () => void clearItems(listId) },
                  ]),
              },
              { text: 'Cancel', style: 'cancel' },
            ])
          }
          className="active:opacity-60"
        >
          <Ionicons name="ellipsis-horizontal" size={22} color="#2563eb" />
        </Pressable>
      ),
    });
  }, [navigation, listId, uncheckAll, removeChecked, clearItems]);

  return (
    <>
      <GroceryListBody listId={listId} />
      <PromptModal
        visible={renaming}
        title="Rename list"
        initialValue={getList(listId)?.name ?? route.params.name}
        placeholder="List name"
        onSubmit={(name) => {
          void renameList(listId, name);
          navigation.setOptions({ title: name });
          setRenaming(false);
        }}
        onCancel={() => setRenaming(false)}
      />
    </>
  );
}
