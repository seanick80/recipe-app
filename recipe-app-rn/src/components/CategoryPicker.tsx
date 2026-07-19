import { GROCERY_CATEGORIES } from '../lib/groceryCategorizer';
import { PickerField } from './PickerField';

/**
 * The picker options: an empty "Auto-detect" row first (unset = let the
 * name-based categorizer decide on save), then the fixed {@link
 * GROCERY_CATEGORIES}. There's no free-text "Other…" because "Other" is already
 * one of the categories.
 */
const CATEGORY_OPTIONS: readonly string[] = ['', ...GROCERY_CATEGORIES];

/**
 * Grocery-category selector. An empty value means "unset" — the item's category
 * is auto-detected from its name (see `groceryCategorizer`) on save; picking a
 * concrete category overrides that. The value is stored as a plain string.
 */
export function CategoryPicker({
  value,
  onChange,
  triggerClassName,
}: {
  value: string;
  onChange: (category: string) => void;
  triggerClassName?: string;
}) {
  return (
    <PickerField
      value={value}
      onChange={onChange}
      options={CATEGORY_OPTIONS}
      noneLabel="Auto-detect"
      placeholder="Auto-detect"
      title="Category"
      accessibilityLabel="Category"
      triggerClassName={triggerClassName}
    />
  );
}
