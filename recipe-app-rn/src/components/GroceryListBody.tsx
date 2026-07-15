import { Ionicons } from '@expo/vector-icons';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import { allItemsChecked, groupByCategory } from '../grocery/groceryLogic';
import type { GroceryItem } from '../grocery/types';
import { newLocalId } from '../lib/ids';
import { formatQuantity } from '../lib/recipeFormat';
import { GroceryItemEditModal } from './GroceryItemEditModal';

function amount(item: GroceryItem): string {
  const qty = item.quantity > 0 ? formatQuantity(item.quantity) : '';
  return [qty, item.unit.trim()].filter((s) => s.length > 0).join(' ');
}

function ItemRow({
  item,
  onToggle,
  onEdit,
  onDelete,
}: {
  item: GroceryItem;
  onToggle: () => void;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <View className="flex-row items-center border-b border-gray-100">
      {/* Distinct hit-target: the checkbox toggles complete… */}
      <Pressable
        accessibilityRole="checkbox"
        accessibilityState={{ checked: item.isChecked }}
        accessibilityLabel={`Toggle ${item.name}`}
        onPress={onToggle}
        hitSlop={8}
        className="py-3 pl-4 pr-2 active:opacity-60"
      >
        <Ionicons
          name={item.isChecked ? 'checkmark-circle' : 'ellipse-outline'}
          size={22}
          color={item.isChecked ? '#16a34a' : '#d1d5db'}
        />
      </Pressable>
      {/* …and tapping the body opens the edit sheet (long-press still deletes). */}
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={`Edit ${item.name}`}
        onPress={onEdit}
        onLongPress={onDelete}
        className="flex-1 flex-row items-center py-3 pr-4 active:bg-gray-50"
      >
        <Text
          className={`flex-1 text-base ${item.isChecked ? 'text-gray-400 line-through' : 'text-gray-900'}`}
          numberOfLines={1}
        >
          {item.name}
        </Text>
        {amount(item).length > 0 ? (
          <Text className={`ml-2 text-sm ${item.isChecked ? 'text-gray-300' : 'text-gray-500'}`}>
            {amount(item)}
          </Text>
        ) : null}
      </Pressable>
    </View>
  );
}

/** A blank item to seed the add sheet — the id is transient (addItem mints its own). */
function blankItem(id: string): GroceryItem {
  return {
    id,
    name: '',
    quantity: 0,
    unit: '',
    category: 'Other',
    isChecked: false,
    sourceRecipeName: '',
    sourceRecipeId: '',
  };
}

/**
 * Shared grocery-list body: a compact action bar (Add item + Check all/Uncheck
 * all) atop category-grouped, checkable item rows for the single persistent
 * shopping list. The Shopping tab supplies the header actions. Reads/writes the
 * list via {@link useGrocery}.
 */
export function GroceryListBody() {
  const { list, addItem, updateItem, toggleItem, deleteItem, setAllChecked } = useGrocery();
  const listId = list?.id ?? '';

  const [editingItemId, setEditingItemId] = useState<string | null>(null);
  // Non-null while the add sheet is open. A fresh blank item (with a stable id)
  // per open so the sheet reseeds its fields each time it is reopened.
  const [addDraft, setAddDraft] = useState<GroceryItem | null>(null);

  // Confirm + delete a single item (shared by the row long-press and the edit
  // sheet's Delete button). Closes the sheet if it was the one being edited.
  const confirmDelete = useCallback(
    (item: GroceryItem) => {
      Alert.alert('Remove item?', `“${item.name}”`, [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Remove',
          style: 'destructive',
          onPress: () => {
            void deleteItem(listId, item.id);
            setEditingItemId((cur) => (cur === item.id ? null : cur));
          },
        },
      ]);
    },
    [deleteItem, listId],
  );

  if (!list) {
    return (
      <View className="flex-1 items-center justify-center bg-white px-8">
        <Text className="text-center text-base text-gray-500">This list is no longer available.</Text>
      </View>
    );
  }

  const sections = groupByCategory(list.items);
  const editingItem = editingItemId ? (list.items.find((i) => i.id === editingItemId) ?? null) : null;
  const modalItem = addDraft ?? editingItem;
  const hasItems = list.items.length > 0;
  const allChecked = allItemsChecked(list.items);

  return (
    <View className="flex-1 bg-white">
      <View className="flex-row items-center justify-between border-b border-gray-100 bg-gray-50 px-3 py-2">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Add item"
          onPress={() => setAddDraft(blankItem(newLocalId()))}
          className="flex-row items-center rounded-lg bg-blue-600 px-3 py-1.5 active:opacity-80"
        >
          <Ionicons name="add" size={18} color="#ffffff" />
          <Text className="ml-1 text-base font-semibold text-white">Add item</Text>
        </Pressable>
        {hasItems ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={allChecked ? 'Uncheck all items' : 'Check all items'}
            onPress={() => void setAllChecked(listId, !allChecked)}
            className="flex-row items-center rounded-lg border border-gray-300 bg-white px-3 py-1.5 active:opacity-70"
          >
            <Ionicons
              name={allChecked ? 'ellipse-outline' : 'checkmark-circle'}
              size={18}
              color="#374151"
            />
            <Text className="ml-1 text-base font-medium text-gray-700">
              {allChecked ? 'Uncheck all' : 'Check all'}
            </Text>
          </Pressable>
        ) : null}
      </View>

      <ScrollView contentContainerStyle={list.items.length === 0 ? { flex: 1 } : { paddingBottom: 24 }}>
        {list.items.length === 0 ? (
          <View className="flex-1 items-center justify-center px-8">
            <Text className="text-center text-base text-gray-500">No items yet. Add one above.</Text>
          </View>
        ) : (
          sections.map((section) => (
            <View key={section.category}>
              <Text className="bg-gray-50 px-4 py-1.5 text-xs font-semibold uppercase tracking-wide text-gray-400">
                {section.category}
              </Text>
              {section.items.map((item) => (
                <ItemRow
                  key={item.id}
                  item={item}
                  onToggle={() => void toggleItem(listId, item.id)}
                  onEdit={() => setEditingItemId(item.id)}
                  onDelete={() => confirmDelete(item)}
                />
              ))}
            </View>
          ))
        )}
      </ScrollView>

      <GroceryItemEditModal
        item={modalItem}
        mode={addDraft ? 'add' : 'edit'}
        onSubmit={(updated) => {
          if (addDraft) {
            void addItem(listId, updated.name, updated.quantity, updated.unit);
            setAddDraft(null);
          } else {
            void updateItem(listId, updated);
            setEditingItemId(null);
          }
        }}
        onCancel={() => {
          setAddDraft(null);
          setEditingItemId(null);
        }}
        onDelete={confirmDelete}
      />
    </View>
  );
}
