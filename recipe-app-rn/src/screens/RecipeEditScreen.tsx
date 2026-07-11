import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  Switch,
  Text,
  TextInput,
  View,
} from 'react-native';

import { useSync } from '../contexts/SyncContext';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import { emptyDraft, isDraftValid, localToDraft } from '../sync/recipeDraft';
import type { RecipeInput } from '../sync/types';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipeEdit'>;

/**
 * A single ingredient row while editing. `quantityText` is a string buffer so
 * partial decimal input ("0.", "1.5") types correctly; it's parsed to a number
 * only when the draft is built (matching the SwiftUI form's row state).
 */
type IngRow = {
  name: string;
  quantityText: string;
  unit: string;
  category: string;
  notes: string;
};

type FormState = Omit<RecipeInput, 'ingredients'> & { ingredients: IngRow[] };

const TIME_STEP = 5;
const TIME_MAX = 480;

function toFormState(draft: RecipeInput): FormState {
  return {
    ...draft,
    ingredients: draft.ingredients.map((ing) => ({
      name: ing.name,
      quantityText: ing.quantity > 0 ? String(ing.quantity) : '',
      unit: ing.unit,
      category: ing.category || 'Other',
      notes: ing.notes,
    })),
  };
}

function toDraft(form: FormState): RecipeInput {
  return {
    ...form,
    ingredients: form.ingredients.map((row, index) => ({
      name: row.name,
      quantity: parseFloat(row.quantityText) || 0,
      unit: row.unit,
      category: row.category || 'Other',
      display_order: index,
      notes: row.notes,
    })),
  };
}

function emptyRow(): IngRow {
  return { name: '', quantityText: '', unit: '', category: 'Other', notes: '' };
}

function Field({
  label,
  value,
  onChangeText,
  placeholder,
  multiline,
  ...rest
}: {
  label: string;
  value: string;
  onChangeText: (t: string) => void;
  placeholder?: string;
  multiline?: boolean;
  autoCapitalize?: 'none' | 'sentences';
  autoCorrect?: boolean;
  keyboardType?: 'default' | 'url' | 'decimal-pad';
}) {
  return (
    <View className="mb-4">
      <Text className="mb-1 text-xs font-semibold uppercase tracking-wide text-gray-400">{label}</Text>
      <TextInput
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#9ca3af"
        multiline={multiline}
        className="rounded-lg border border-gray-200 bg-white px-3 py-2 text-base text-gray-900"
        style={multiline ? { minHeight: 80, textAlignVertical: 'top' } : undefined}
        {...rest}
      />
    </View>
  );
}

function Stepper({
  label,
  value,
  onChange,
  step,
  min,
  max,
}: {
  label: string;
  value: number;
  onChange: (n: number) => void;
  step: number;
  min: number;
  max: number;
}) {
  const set = (n: number) => onChange(Math.max(min, Math.min(max, n)));
  return (
    <View className="mb-4 flex-row items-center justify-between">
      <Text className="text-base text-gray-800">
        {label}: <Text className="font-semibold">{value}</Text>
      </Text>
      <View className="flex-row items-center">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Decrease ${label}`}
          onPress={() => set(value - step)}
          className="h-9 w-9 items-center justify-center rounded-full bg-gray-100 active:bg-gray-200"
        >
          <Ionicons name="remove" size={20} color="#111827" />
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Increase ${label}`}
          onPress={() => set(value + step)}
          className="ml-2 h-9 w-9 items-center justify-center rounded-full bg-gray-100 active:bg-gray-200"
        >
          <Ionicons name="add" size={20} color="#111827" />
        </Pressable>
      </View>
    </View>
  );
}

/**
 * Recipe create/edit form (Phase 4), a port of the SwiftUI `RecipeEditView`.
 * `localId` param present = edit, absent = create. Saving writes through the
 * offline-first store via {@link useSync} (sets `needsSync`, kicks a background
 * sync). Cuisine/course/difficulty are free-text like the SwiftUI form; the
 * dedicated UnitPicker is deferred (unit is a free-text field for now).
 */
export function RecipeEditScreen({ route, navigation }: Props) {
  const { localId } = route.params;
  const { getByLocalId, createRecipe, updateRecipe } = useSync();

  const initial = useMemo<FormState>(() => {
    if (localId) {
      const existing = getByLocalId(localId);
      if (existing) return toFormState(localToDraft(existing));
    }
    return toFormState(emptyDraft());
    // Load once on mount; live store updates shouldn't clobber in-progress edits.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const [form, setForm] = useState<FormState>(initial);
  const [saving, setSaving] = useState(false);

  const patch = useCallback((p: Partial<FormState>) => setForm((f) => ({ ...f, ...p })), []);

  const setIngredient = useCallback((index: number, p: Partial<IngRow>) => {
    setForm((f) => ({
      ...f,
      ingredients: f.ingredients.map((row, i) => (i === index ? { ...row, ...p } : row)),
    }));
  }, []);

  const addIngredient = useCallback(() => {
    setForm((f) => ({ ...f, ingredients: [...f.ingredients, emptyRow()] }));
  }, []);

  const removeIngredient = useCallback((index: number) => {
    setForm((f) => ({ ...f, ingredients: f.ingredients.filter((_, i) => i !== index) }));
  }, []);

  const moveIngredient = useCallback((index: number, dir: -1 | 1) => {
    setForm((f) => {
      const target = index + dir;
      if (target < 0 || target >= f.ingredients.length) return f;
      const next = [...f.ingredients];
      [next[index], next[target]] = [next[target], next[index]];
      return { ...f, ingredients: next };
    });
  }, []);

  const canSave = form.name.trim().length > 0 && !saving;

  const onSave = useCallback(async () => {
    const draft = toDraft(form);
    if (!isDraftValid(draft)) return;
    setSaving(true);
    try {
      if (localId) await updateRecipe(localId, draft);
      else await createRecipe(draft);
      navigation.goBack();
    } catch {
      setSaving(false); // stay on the form so the user can retry
    }
  }, [form, localId, createRecipe, updateRecipe, navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      title: localId ? 'Edit Recipe' : 'New Recipe',
      headerRight: () => (
        <Pressable accessibilityRole="button" disabled={!canSave} onPress={onSave}>
          <Text className={canSave ? 'text-base font-semibold text-blue-600' : 'text-base text-gray-300'}>
            Save
          </Text>
        </Pressable>
      ),
    });
  }, [navigation, canSave, onSave, localId]);

  return (
    <ScrollView className="flex-1 bg-gray-50" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
      <Field label="Name" value={form.name} onChangeText={(t) => patch({ name: t })} placeholder="Recipe name" />
      <Field
        label="Summary"
        value={form.summary}
        onChangeText={(t) => patch({ summary: t })}
        placeholder="A short description"
        multiline
      />

      <Field label="Cuisine" value={form.cuisine} onChangeText={(t) => patch({ cuisine: t })} placeholder="e.g. Italian, Mexican" />
      <Field label="Course" value={form.course} onChangeText={(t) => patch({ course: t })} placeholder="e.g. Dinner, Dessert" />
      <Field label="Difficulty" value={form.difficulty} onChangeText={(t) => patch({ difficulty: t })} placeholder="e.g. Easy, Medium, Hard" />
      <Field label="Tags (comma-separated)" value={form.tags} onChangeText={(t) => patch({ tags: t })} placeholder="quick, vegetarian" />
      <Field
        label="Source URL"
        value={form.source_url}
        onChangeText={(t) => patch({ source_url: t })}
        placeholder="https://…"
        autoCapitalize="none"
        autoCorrect={false}
        keyboardType="url"
      />

      <Stepper label="Prep (min)" value={form.prep_time_minutes} onChange={(n) => patch({ prep_time_minutes: n })} step={TIME_STEP} min={0} max={TIME_MAX} />
      <Stepper label="Cook (min)" value={form.cook_time_minutes} onChange={(n) => patch({ cook_time_minutes: n })} step={TIME_STEP} min={0} max={TIME_MAX} />
      <Stepper label="Servings" value={form.servings} onChange={(n) => patch({ servings: n })} step={1} min={1} max={50} />

      <View className="mb-2 mt-2 flex-row items-center justify-between">
        <Text className="text-xs font-semibold uppercase tracking-wide text-gray-400">Ingredients</Text>
        <Pressable accessibilityRole="button" onPress={addIngredient} className="flex-row items-center active:opacity-60">
          <Ionicons name="add-circle-outline" size={20} color="#2563eb" />
          <Text className="ml-1 text-sm font-semibold text-blue-600">Add</Text>
        </Pressable>
      </View>

      {form.ingredients.map((row, index) => (
        <View key={index} className="mb-3 rounded-lg border border-gray-200 bg-white p-3">
          <View className="flex-row">
            <TextInput
              value={row.quantityText}
              onChangeText={(t) => setIngredient(index, { quantityText: t })}
              placeholder="Qty"
              placeholderTextColor="#9ca3af"
              keyboardType="decimal-pad"
              className="mr-2 w-16 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
            />
            <TextInput
              value={row.unit}
              onChangeText={(t) => setIngredient(index, { unit: t })}
              placeholder="unit"
              placeholderTextColor="#9ca3af"
              autoCapitalize="none"
              className="mr-2 w-20 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
            />
            <TextInput
              value={row.name}
              onChangeText={(t) => setIngredient(index, { name: t })}
              placeholder="ingredient"
              placeholderTextColor="#9ca3af"
              className="flex-1 rounded border border-gray-200 px-2 py-1.5 text-base text-gray-900"
            />
          </View>
          <TextInput
            value={row.notes}
            onChangeText={(t) => setIngredient(index, { notes: t })}
            placeholder="notes (optional)"
            placeholderTextColor="#9ca3af"
            className="mt-2 rounded border border-gray-200 px-2 py-1.5 text-sm text-gray-700"
          />
          <View className="mt-2 flex-row justify-end">
            <Pressable accessibilityRole="button" accessibilityLabel="Move up" onPress={() => moveIngredient(index, -1)} className="mr-3 active:opacity-50">
              <Ionicons name="arrow-up" size={18} color="#6b7280" />
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Move down" onPress={() => moveIngredient(index, 1)} className="mr-3 active:opacity-50">
              <Ionicons name="arrow-down" size={18} color="#6b7280" />
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Remove ingredient" onPress={() => removeIngredient(index)} className="active:opacity-50">
              <Ionicons name="trash-outline" size={18} color="#dc2626" />
            </Pressable>
          </View>
        </View>
      ))}

      <View className="mt-2">
        <Field
          label="Instructions"
          value={form.instructions}
          onChangeText={(t) => patch({ instructions: t })}
          placeholder="Step-by-step instructions"
          multiline
        />
      </View>

      <View className="mb-8 mt-1 flex-row items-center justify-between">
        <Text className="text-base text-gray-800">Favorite</Text>
        <Switch value={form.is_favorite} onValueChange={(v) => patch({ is_favorite: v })} />
      </View>
    </ScrollView>
  );
}
