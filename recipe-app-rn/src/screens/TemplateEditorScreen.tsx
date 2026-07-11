import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, Text, TextInput, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import type { TemplateItem } from '../grocery/types';
import { newLocalId } from '../lib/ids';
import type { ShoppingStackParamList } from '../navigation/ShoppingStack';

type Props = NativeStackScreenProps<ShoppingStackParamList, 'TemplateEditor'>;

/** Editable staple row (quantity as a string buffer for decimal input). */
type Row = { id: string; name: string; quantityText: string; unit: string; category: string };

function toRow(item: TemplateItem): Row {
  return {
    id: item.id,
    name: item.name,
    quantityText: item.quantity > 0 ? String(item.quantity) : '',
    unit: item.unit,
    category: item.category || 'Other',
  };
}

/**
 * Edit a shopping template's staples (Phase 4 slice 3b) — port of SwiftUI
 * `TemplateEditorView`. Add/remove rows; Save writes back via
 * {@link useGrocery} `setTemplateItems` (blank-named rows dropped, order = index).
 */
export function TemplateEditorScreen({ route, navigation }: Props) {
  const { templateId } = route.params;
  const { templates, setTemplateItems } = useGrocery();
  const template = templates.find((t) => t.id === templateId);

  const initial = useMemo<Row[]>(() => (template ? template.items.map(toRow) : []), []); // eslint-disable-line react-hooks/exhaustive-deps
  const [rows, setRows] = useState<Row[]>(initial);
  const [saving, setSaving] = useState(false);

  const setRow = useCallback((index: number, patch: Partial<Row>) => {
    setRows((rs) => rs.map((r, i) => (i === index ? { ...r, ...patch } : r)));
  }, []);
  const addRow = useCallback(() => {
    setRows((rs) => [...rs, { id: newLocalId(), name: '', quantityText: '', unit: '', category: 'Other' }]);
  }, []);
  const removeRow = useCallback((index: number) => {
    setRows((rs) => rs.filter((_, i) => i !== index));
  }, []);

  const onSave = useCallback(async () => {
    setSaving(true);
    const items: TemplateItem[] = rows
      .filter((r) => r.name.trim().length > 0)
      .map((r, index) => ({
        id: r.id,
        name: r.name.trim(),
        quantity: parseFloat(r.quantityText) || 1,
        unit: r.unit.trim(),
        category: r.category || 'Other',
        sortOrder: index,
      }));
    await setTemplateItems(templateId, items);
    navigation.goBack();
  }, [rows, setTemplateItems, templateId, navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      title: template?.name ?? 'Staples',
      headerRight: () => (
        <Pressable accessibilityRole="button" disabled={saving} onPress={onSave}>
          <Text className="text-base font-semibold text-blue-600">Save</Text>
        </Pressable>
      ),
    });
  }, [navigation, onSave, saving, template?.name]);

  return (
    <ScrollView className="flex-1 bg-gray-50" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
      <Text className="mb-3 text-sm text-gray-500">
        Reusable staples you can add to any list in one tap.
      </Text>

      {rows.map((row, index) => (
        <View key={row.id} className="mb-2 flex-row items-center rounded-lg border border-gray-200 bg-white p-2">
          <TextInput
            value={row.quantityText}
            onChangeText={(t) => setRow(index, { quantityText: t })}
            placeholder="Qty"
            placeholderTextColor="#9ca3af"
            keyboardType="decimal-pad"
            className="mr-2 w-14 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
          />
          <TextInput
            value={row.unit}
            onChangeText={(t) => setRow(index, { unit: t })}
            placeholder="unit"
            placeholderTextColor="#9ca3af"
            autoCapitalize="none"
            className="mr-2 w-16 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
          />
          <TextInput
            value={row.name}
            onChangeText={(t) => setRow(index, { name: t })}
            placeholder="staple"
            placeholderTextColor="#9ca3af"
            className="flex-1 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
          />
          <Pressable accessibilityRole="button" accessibilityLabel="Remove" onPress={() => removeRow(index)} className="ml-2 active:opacity-50">
            <Ionicons name="close-circle" size={22} color="#dc2626" />
          </Pressable>
        </View>
      ))}

      <Pressable accessibilityRole="button" onPress={addRow} className="mt-2 flex-row items-center active:opacity-60">
        <Ionicons name="add-circle-outline" size={22} color="#2563eb" />
        <Text className="ml-1 font-semibold text-blue-600">Add staple</Text>
      </Pressable>
    </ScrollView>
  );
}
