import { useState } from 'react';
import { Modal, Pressable, Text, TextInput, View } from 'react-native';

import type { GroceryItem } from '../grocery/types';
import { categorizeGroceryItem } from '../lib/groceryCategorizer';
import { CategoryPicker } from './CategoryPicker';
import { UnitPicker } from './UnitPicker';
import { colors } from '../theme/tokens';

/**
 * Add/edit sheet for a single grocery-list item (name / quantity / unit /
 * category). Built from RN primitives + NativeWind, reusing {@link UnitPicker}
 * (shopping units) and {@link CategoryPicker}. Controlled by `item` (non-null =
 * open); `onSubmit` fires with the item, `onCancel` dismisses. An empty name is
 * treated as cancel.
 *
 * `mode` switches the presentation: `'edit'` (default) shows an "Edit item"
 * title and a Delete button and is reached by tapping an existing row; `'add'`
 * shows an "Add item" title with no Delete, opened from the list's add bar with
 * a blank item. Either way the checkbox toggle lives on the row itself.
 */
export function GroceryItemEditModal({
  item,
  mode = 'edit',
  onSubmit,
  onCancel,
  onDelete,
}: {
  item: GroceryItem | null;
  mode?: 'add' | 'edit';
  onSubmit: (updated: GroceryItem) => void;
  onCancel: () => void;
  /** Remove this item from the list (parent confirms + deletes + closes). Edit mode only. */
  onDelete: (item: GroceryItem) => void;
}) {
  const [name, setName] = useState('');
  const [qty, setQty] = useState('');
  const [unit, setUnit] = useState('');
  // Empty = unset → auto-detected from the name on submit. A blank add-draft
  // seeds this empty so new items get categorized instead of all landing in
  // "Other" (#19); an existing item seeds to its stored category.
  const [category, setCategory] = useState('');

  // Seed the fields when the sheet opens for a (new) item, by adjusting state
  // during render on the open transition — the React-recommended alternative to
  // an effect (https://react.dev/learn/you-might-not-need-an-effect).
  const [editingId, setEditingId] = useState<string | null>(null);
  const targetId = item?.id ?? null;
  if (targetId !== editingId) {
    setEditingId(targetId);
    if (item) {
      setName(item.name);
      setQty(item.quantity > 0 ? String(item.quantity) : '');
      setUnit(item.unit);
      setCategory(item.category); // '' for a blank add-draft → auto-detect
    }
  }

  const submit = () => {
    if (!item) return;
    const trimmed = name.trim();
    if (trimmed.length === 0) {
      onCancel();
      return;
    }
    // Unset category → auto-detect from the name; a chosen one wins.
    const resolvedCategory = category.trim().length > 0 ? category : categorizeGroceryItem(trimmed);
    onSubmit({
      ...item,
      name: trimmed,
      quantity: parseFloat(qty) || 0,
      unit: unit.trim(),
      category: resolvedCategory,
    });
  };

  return (
    <Modal visible={item !== null} transparent animationType="fade" onRequestClose={onCancel}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Dismiss"
        onPress={onCancel}
        className="flex-1 justify-center bg-black/40 px-8"
      >
        <Pressable className="rounded-xl bg-app-surface p-4" onPress={() => {}}>
          <Text className="mb-3 text-base font-semibold text-app-text-primary">
            {mode === 'add' ? 'Add item' : 'Edit item'}
          </Text>

          <Text className="mb-1 text-xs font-semibold uppercase tracking-wide text-app-text-muted">Name</Text>
          <TextInput
            value={name}
            onChangeText={setName}
            placeholder="Item name"
            placeholderTextColor={colors.textMuted}
            autoFocus
            returnKeyType="done"
            onSubmitEditing={submit}
            className="mb-3 rounded border border-app-border bg-app-surface px-3 py-2 text-base text-app-text-primary"
          />

          <Text className="mb-1 text-xs font-semibold uppercase tracking-wide text-app-text-muted">Quantity</Text>
          <View className="mb-3 flex-row items-center">
            <TextInput
              value={qty}
              onChangeText={setQty}
              placeholder="Qty"
              placeholderTextColor={colors.textMuted}
              keyboardType="decimal-pad"
              className="w-16 rounded border border-app-border bg-app-surface px-3 py-2 text-base text-app-text-primary"
            />
            <UnitPicker value={unit} onChange={setUnit} context="shopping" triggerClassName="ml-2 flex-1" />
          </View>

          <Text className="mb-1 text-xs font-semibold uppercase tracking-wide text-app-text-muted">Category</Text>
          <CategoryPicker value={category} onChange={setCategory} triggerClassName="mb-1" />

          <View className="mt-4 flex-row items-center justify-between">
            {mode === 'edit' ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Delete item"
                onPress={() => item && onDelete(item)}
                className="px-2 py-1 active:opacity-60"
              >
                <Text className="text-base font-semibold text-app-danger">Delete</Text>
              </Pressable>
            ) : (
              <View />
            )}
            <View className="flex-row gap-4">
              <Pressable accessibilityRole="button" onPress={onCancel} className="px-2 py-1 active:opacity-60">
                <Text className="text-base text-app-text-secondary">Cancel</Text>
              </Pressable>
              <Pressable accessibilityRole="button" onPress={submit} className="px-2 py-1 active:opacity-60">
                <Text className="text-base font-semibold text-app-primary">Save</Text>
              </Pressable>
            </View>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
