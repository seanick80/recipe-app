import { Ionicons } from '@expo/vector-icons';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, TextInput, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import { groupByCategory } from '../grocery/groceryLogic';
import type { GroceryItem } from '../grocery/types';
import { formatQuantity } from '../lib/recipeFormat';

function amount(item: GroceryItem): string {
  const qty = item.quantity > 0 ? formatQuantity(item.quantity) : '';
  return [qty, item.unit.trim()].filter((s) => s.length > 0).join(' ');
}

function ItemRow({
  item,
  onToggle,
  onDelete,
}: {
  item: GroceryItem;
  onToggle: () => void;
  onDelete: () => void;
}) {
  return (
    <Pressable
      accessibilityRole="checkbox"
      accessibilityState={{ checked: item.isChecked }}
      onPress={onToggle}
      onLongPress={onDelete}
      className="flex-row items-center border-b border-gray-100 px-4 py-3 active:bg-gray-50"
    >
      <Ionicons
        name={item.isChecked ? 'checkmark-circle' : 'ellipse-outline'}
        size={22}
        color={item.isChecked ? '#16a34a' : '#d1d5db'}
      />
      <Text
        className={`ml-3 flex-1 text-base ${item.isChecked ? 'text-gray-400 line-through' : 'text-gray-900'}`}
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
  );
}

/**
 * Shared grocery-list body: an inline add bar + category-grouped, checkable
 * item rows. Used by both the Lists-tab detail screen and the Shopping-tab
 * staples view (each supplies its own header actions). Reads/writes the list
 * via {@link useGrocery}.
 */
export function GroceryListBody({ listId }: { listId: string }) {
  const { getList, addItem, toggleItem, deleteItem } = useGrocery();
  const list = getList(listId);

  const [name, setName] = useState('');
  const [qty, setQty] = useState('');
  const [unit, setUnit] = useState('');

  const onAdd = useCallback(async () => {
    if (name.trim().length === 0) return;
    await addItem(listId, name.trim(), parseFloat(qty) || 1, unit.trim());
    setName('');
    setQty('');
    setUnit('');
  }, [addItem, listId, name, qty, unit]);

  if (!list) {
    return (
      <View className="flex-1 items-center justify-center bg-white px-8">
        <Text className="text-center text-base text-gray-500">This list is no longer available.</Text>
      </View>
    );
  }

  const sections = groupByCategory(list.items);

  return (
    <View className="flex-1 bg-white">
      <View className="flex-row items-center border-b border-gray-100 bg-gray-50 px-3 py-2">
        <TextInput
          value={name}
          onChangeText={setName}
          placeholder="Add item"
          placeholderTextColor="#9ca3af"
          onSubmitEditing={onAdd}
          returnKeyType="done"
          className="flex-1 rounded border border-gray-200 bg-white px-2 py-1.5 text-base text-gray-900"
        />
        <TextInput
          value={qty}
          onChangeText={setQty}
          placeholder="Qty"
          placeholderTextColor="#9ca3af"
          keyboardType="decimal-pad"
          className="mx-2 w-12 rounded border border-gray-200 bg-white px-2 py-1.5 text-base text-gray-900"
        />
        <TextInput
          value={unit}
          onChangeText={setUnit}
          placeholder="unit"
          placeholderTextColor="#9ca3af"
          autoCapitalize="none"
          className="mr-2 w-16 rounded border border-gray-200 bg-white px-2 py-1.5 text-base text-gray-900"
        />
        <Pressable accessibilityRole="button" accessibilityLabel="Add item" onPress={onAdd} className="active:opacity-60">
          <Ionicons name="add-circle" size={30} color="#2563eb" />
        </Pressable>
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
                  onDelete={() =>
                    Alert.alert('Remove item?', `“${item.name}”`, [
                      { text: 'Cancel', style: 'cancel' },
                      { text: 'Remove', style: 'destructive', onPress: () => void deleteItem(listId, item.id) },
                    ])
                  }
                />
              ))}
            </View>
          ))
        )}
      </ScrollView>
    </View>
  );
}
