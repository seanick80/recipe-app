import { Ionicons } from '@expo/vector-icons';
import { useState } from 'react';
import { Modal, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { colors } from '../theme/tokens';

/**
 * A compact tap-to-open dropdown built from RN primitives + NativeWind (no
 * gluestack). Ports the SwiftUI `Menu`-based picker look: a small trigger
 * showing the current value + chevron, opening a modal list of options.
 *
 * When `allowOther` is set, the list ends with an "Other…" row that switches
 * the field into a free-text {@link TextInput}; a value that isn't one of the
 * `options` also renders as free text (matching `UnitPicker.swift`). A small
 * list icon returns free-text mode to the preset menu.
 *
 * The base for {@link ./UnitPicker} and {@link ./CategoryPicker}.
 */
export type PickerFieldProps = {
  value: string;
  onChange: (value: string) => void;
  /** Preset options; an empty string renders as the `noneLabel` "(none)" row. */
  options: readonly string[];
  /** Add an "Other…" row + free-text fallback for values outside `options`. */
  allowOther?: boolean;
  /** Trigger/placeholder text when the value is empty. */
  placeholder?: string;
  /** Label for the empty ('') option in the list. */
  noneLabel?: string;
  /** Whether the current value is "outside" the preset list (free-text). */
  isCustomValue?: boolean;
  /** Width/spacing classes for the trigger (e.g. "w-20"). */
  triggerClassName?: string;
  /** Modal sheet title. */
  title?: string;
  accessibilityLabel?: string;
  autoCapitalize?: 'none' | 'sentences';
};

export function PickerField({
  value,
  onChange,
  options,
  allowOther = false,
  placeholder = 'Select',
  noneLabel = '(none)',
  isCustomValue = false,
  triggerClassName = '',
  title,
  accessibilityLabel,
  autoCapitalize,
}: PickerFieldProps) {
  const [open, setOpen] = useState(false);
  const [customMode, setCustomMode] = useState(false);

  const showText = allowOther && (customMode || isCustomValue);

  if (showText) {
    return (
      <View className={`h-9 flex-row items-center rounded border border-app-border bg-app-surface px-2 ${triggerClassName}`}>
        <TextInput
          value={value}
          onChangeText={onChange}
          placeholder={placeholder}
          placeholderTextColor={colors.textMuted}
          autoCapitalize={autoCapitalize}
          accessibilityLabel={accessibilityLabel}
          className="flex-1 text-base text-app-text-primary"
        />
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Pick from list"
          onPress={() => {
            setCustomMode(false);
            onChange('');
            setOpen(true);
          }}
          className="ml-1 active:opacity-60"
        >
          <Ionicons name="list" size={16} color={colors.textMuted} />
        </Pressable>
      </View>
    );
  }

  return (
    <View className={triggerClassName}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        onPress={() => setOpen(true)}
        className="h-9 flex-row items-center justify-between rounded border border-app-border bg-app-surface px-2 active:bg-app-background"
      >
        <Text className={`flex-1 text-base ${value ? 'text-app-text-primary' : 'text-app-text-muted'}`} numberOfLines={1}>
          {value || placeholder}
        </Text>
        <Ionicons name="chevron-expand" size={14} color={colors.textMuted} />
      </Pressable>

      <Modal visible={open} transparent animationType="fade" onRequestClose={() => setOpen(false)}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Dismiss"
          onPress={() => setOpen(false)}
          className="flex-1 justify-center bg-black/40 px-8"
        >
          <Pressable className="max-h-[70%] overflow-hidden rounded-xl bg-app-surface" onPress={() => {}}>
            {title ? (
              <Text className="border-b border-app-border-subtle px-4 py-3 text-xs font-semibold uppercase tracking-wide text-app-text-muted">
                {title}
              </Text>
            ) : null}
            <ScrollView>
              {options.map((opt) => {
                const selected = opt === value;
                return (
                  <Pressable
                    key={opt || '__none__'}
                    accessibilityRole="button"
                    onPress={() => {
                      onChange(opt);
                      setCustomMode(false);
                      setOpen(false);
                    }}
                    className="flex-row items-center justify-between px-4 py-3 active:bg-app-background"
                  >
                    <Text className={`text-base ${opt ? 'text-app-text-primary' : 'text-app-text-muted'}`}>{opt || noneLabel}</Text>
                    {selected ? <Ionicons name="checkmark" size={18} color={colors.primary} /> : null}
                  </Pressable>
                );
              })}
              {allowOther ? (
                <Pressable
                  accessibilityRole="button"
                  onPress={() => {
                    setCustomMode(true);
                    setOpen(false);
                  }}
                  className="flex-row items-center border-t border-app-border-subtle px-4 py-3 active:bg-app-background"
                >
                  <Ionicons name="create-outline" size={16} color={colors.primary} />
                  <Text className="ml-2 text-base font-semibold text-app-primary">Other…</Text>
                </Pressable>
              ) : null}
            </ScrollView>
          </Pressable>
        </Pressable>
      </Modal>
    </View>
  );
}
