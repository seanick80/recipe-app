import { GROCERY_CATEGORIES } from '../lib/groceryCategorizer';
import { PickerField } from './PickerField';

/**
 * Grocery-category selector. Lets the user override the auto-assigned category
 * (from `groceryCategorizer`) with any of the fixed {@link GROCERY_CATEGORIES}.
 * The value is stored as a plain string; there is no free-text "Other…" because
 * "Other" is already one of the categories.
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
      options={GROCERY_CATEGORIES}
      placeholder="Category"
      title="Category"
      accessibilityLabel="Category"
      triggerClassName={triggerClassName}
    />
  );
}
