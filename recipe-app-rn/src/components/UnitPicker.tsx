import { isCustomUnit, unitsFor, type UnitContext } from '../lib/units';
import { PickerField } from './PickerField';

/**
 * Unit selector for ingredient / grocery rows — a port of the SwiftUI
 * `UnitPicker`. Offers the context-appropriate preset units plus an "Other…"
 * free-text fallback; the unit is still stored (and reported) as a plain
 * string.
 */
export function UnitPicker({
  value,
  onChange,
  context = 'recipe',
  triggerClassName,
}: {
  value: string;
  onChange: (unit: string) => void;
  context?: UnitContext;
  triggerClassName?: string;
}) {
  return (
    <PickerField
      value={value}
      onChange={onChange}
      options={unitsFor(context)}
      allowOther
      isCustomValue={isCustomUnit(value, context)}
      placeholder="unit"
      title="Unit"
      accessibilityLabel="Unit"
      autoCapitalize="none"
      triggerClassName={triggerClassName}
    />
  );
}
