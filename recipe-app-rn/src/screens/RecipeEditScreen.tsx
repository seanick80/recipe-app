import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useMemo, useState } from 'react';
import { ActivityIndicator } from 'react-native';

import { Box } from '../../components/ui/box';
import { Button, ButtonText } from '../../components/ui/button';
import { HStack } from '../../components/ui/hstack';
import { Input, InputField } from '../../components/ui/input';
import { Pressable } from '../../components/ui/pressable';
import { ScrollView } from '../../components/ui/scroll-view';
import { Switch } from '../../components/ui/switch';
import { Text } from '../../components/ui/text';
import { Textarea, TextareaInput } from '../../components/ui/textarea';
import { CategoryPicker } from '../components/CategoryPicker';
import { UnitPicker } from '../components/UnitPicker';
import { useSync } from '../contexts/SyncContext';
import { fetchAndParseRecipe, importedRecipeToDraft } from '../lib/recipeImport';
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
    <Box className="mb-4">
      <Text className="mb-1 text-xs font-semibold uppercase tracking-wide text-muted-foreground">{label}</Text>
      {multiline ? (
        <Textarea className="min-h-[80px]">
          <TextareaInput
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor="#9ca3af"
            {...rest}
          />
        </Textarea>
      ) : (
        <Input className="h-11">
          <InputField
            value={value}
            onChangeText={onChangeText}
            placeholder={placeholder}
            placeholderTextColor="#9ca3af"
            className="text-base"
            {...rest}
          />
        </Input>
      )}
    </Box>
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
    <HStack className="mb-4 items-center justify-between">
      <Text className="text-base text-foreground">
        {label}: <Text className="font-semibold text-foreground">{value}</Text>
      </Text>
      <HStack className="items-center gap-2">
        <Button
          size="icon"
          variant="outline"
          className="rounded-full"
          accessibilityRole="button"
          accessibilityLabel={`Decrease ${label}`}
          onPress={() => set(value - step)}
        >
          <Ionicons name="remove" size={20} color="#111827" />
        </Button>
        <Button
          size="icon"
          variant="outline"
          className="rounded-full"
          accessibilityRole="button"
          accessibilityLabel={`Increase ${label}`}
          onPress={() => set(value + step)}
        >
          <Ionicons name="add" size={20} color="#111827" />
        </Button>
      </HStack>
    </HStack>
  );
}

/**
 * Recipe create/edit form (Phase 4), a port of the SwiftUI `RecipeEditView`.
 * `localId` param present = edit, absent = create. Saving writes through the
 * offline-first store via {@link useSync} (sets `needsSync`, kicks a background
 * sync). Cuisine/course/difficulty are free-text like the SwiftUI form;
 * ingredient unit + category use the dedicated {@link UnitPicker} /
 * {@link CategoryPicker} (preset options + "Other…" free-text for units).
 *
 * UI note: this screen is the gluestack-ui look-and-feel sample. Layout uses
 * gluestack primitives (Box/HStack), form controls use Input/Textarea/Switch/
 * Button, and colors use the semantic tokens (foreground/muted-foreground/
 * border/background) driven by GluestackUIProvider.
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
  const [reimporting, setReimporting] = useState(false);
  const [reimportError, setReimportError] = useState<string | null>(null);

  const patch = useCallback((p: Partial<FormState>) => setForm((f) => ({ ...f, ...p })), []);

  // Re-fetch + re-parse the recipe from its source URL and repopulate the parsed
  // fields in-place (instructions, ingredients, times/servings, cuisine/course),
  // while keeping the user's name + identity (favorite, tags, difficulty, etc.).
  // Fixes recipes captured by the old buggy parser (e.g. incomplete steps); the
  // user reviews the refreshed fields inline and taps the existing Save.
  const onReimport = useCallback(async () => {
    const url = form.source_url.trim();
    if (url.length === 0 || reimporting) return;
    setReimporting(true);
    setReimportError(null);
    const result = await fetchAndParseRecipe(url);
    setReimporting(false);
    if (!result.success) {
      setReimportError(result.message);
      return;
    }
    const fresh = toFormState(importedRecipeToDraft(result.recipe));
    setForm((f) => ({
      ...f,
      // Keep the existing name unless it's empty; identity fields untouched.
      name: f.name.trim().length > 0 ? f.name : fresh.name,
      instructions: fresh.instructions,
      ingredients: fresh.ingredients,
      prep_time_minutes: fresh.prep_time_minutes,
      cook_time_minutes: fresh.cook_time_minutes,
      servings: fresh.servings,
      cuisine: fresh.cuisine,
      course: fresh.course,
    }));
  }, [form.source_url, reimporting]);

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
        <Button variant="link" size="sm" accessibilityRole="button" disabled={!canSave} onPress={onSave}>
          <ButtonText className={canSave ? 'text-base font-semibold text-primary' : 'text-base text-muted-foreground'}>
            Save
          </ButtonText>
        </Button>
      ),
    });
  }, [navigation, canSave, onSave, localId]);

  return (
    <ScrollView className="flex-1 bg-background" contentContainerStyle={{ padding: 16 }} keyboardShouldPersistTaps="handled">
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

      {form.source_url.trim().length > 0 ? (
        <Box className="mb-4">
          <Button
            variant="outline"
            size="sm"
            accessibilityRole="button"
            accessibilityLabel="Re-import from source"
            disabled={reimporting}
            onPress={onReimport}
            className="gap-2"
          >
            {reimporting ? (
              <ActivityIndicator size="small" color="#2563eb" />
            ) : (
              <Ionicons name="refresh" size={18} color="#2563eb" />
            )}
            <ButtonText className="text-sm font-semibold text-primary">
              {reimporting ? 'Re-importing…' : 'Re-import from source'}
            </ButtonText>
          </Button>
          <Text className="mt-1 text-xs text-muted-foreground">
            Re-fetches this recipe from its source URL and refreshes the steps, ingredients, and details below.
            Review, then Save.
          </Text>
          {reimportError ? <Text className="mt-1 text-sm text-red-600">{reimportError}</Text> : null}
        </Box>
      ) : null}

      <Stepper label="Prep (min)" value={form.prep_time_minutes} onChange={(n) => patch({ prep_time_minutes: n })} step={TIME_STEP} min={0} max={TIME_MAX} />
      <Stepper label="Cook (min)" value={form.cook_time_minutes} onChange={(n) => patch({ cook_time_minutes: n })} step={TIME_STEP} min={0} max={TIME_MAX} />
      <Stepper label="Servings" value={form.servings} onChange={(n) => patch({ servings: n })} step={1} min={1} max={50} />

      <HStack className="mb-2 mt-2 items-center justify-between">
        <Text className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Ingredients</Text>
        <Button variant="link" size="sm" accessibilityRole="button" onPress={addIngredient} className="gap-1">
          <Ionicons name="add-circle-outline" size={20} color="#2563eb" />
          <ButtonText className="text-sm font-semibold text-primary">Add</ButtonText>
        </Button>
      </HStack>

      {form.ingredients.map((row, index) => (
        <Box key={index} className="mb-3 rounded-lg border border-border bg-background p-3">
          <HStack className="gap-2">
            <Input className="h-9 w-16">
              <InputField
                value={row.quantityText}
                onChangeText={(t) => setIngredient(index, { quantityText: t })}
                placeholder="Qty"
                placeholderTextColor="#9ca3af"
                keyboardType="decimal-pad"
              />
            </Input>
            <UnitPicker
              value={row.unit}
              onChange={(u) => setIngredient(index, { unit: u })}
              context="recipe"
              triggerClassName="w-24"
            />
            <Input className="h-9 flex-1">
              <InputField
                value={row.name}
                onChangeText={(t) => setIngredient(index, { name: t })}
                placeholder="ingredient"
                placeholderTextColor="#9ca3af"
              />
            </Input>
          </HStack>
          <Input className="mt-2 h-9">
            <InputField
              value={row.notes}
              onChangeText={(t) => setIngredient(index, { notes: t })}
              placeholder="notes (optional)"
              placeholderTextColor="#9ca3af"
              className="text-sm"
            />
          </Input>
          <HStack className="mt-2 items-center gap-2">
            <Text className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Category</Text>
            <CategoryPicker
              value={row.category}
              onChange={(c) => setIngredient(index, { category: c })}
              triggerClassName="flex-1"
            />
          </HStack>
          <HStack className="mt-2 justify-end">
            <Pressable accessibilityRole="button" accessibilityLabel="Move up" onPress={() => moveIngredient(index, -1)} className="mr-3 active:opacity-50">
              <Ionicons name="arrow-up" size={18} color="#6b7280" />
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Move down" onPress={() => moveIngredient(index, 1)} className="mr-3 active:opacity-50">
              <Ionicons name="arrow-down" size={18} color="#6b7280" />
            </Pressable>
            <Pressable accessibilityRole="button" accessibilityLabel="Remove ingredient" onPress={() => removeIngredient(index)} className="active:opacity-50">
              <Ionicons name="trash-outline" size={18} color="#dc2626" />
            </Pressable>
          </HStack>
        </Box>
      ))}

      <Box className="mt-2">
        <Field
          label="Instructions"
          value={form.instructions}
          onChangeText={(t) => patch({ instructions: t })}
          placeholder="Step-by-step instructions"
          multiline
        />
      </Box>

      <HStack className="mb-8 mt-1 items-center justify-between">
        <Text className="text-base text-foreground">Favorite</Text>
        <Switch value={form.is_favorite} onValueChange={(v) => patch({ is_favorite: v })} />
      </HStack>
    </ScrollView>
  );
}
