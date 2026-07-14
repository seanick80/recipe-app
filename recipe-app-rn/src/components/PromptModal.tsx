import { useState } from 'react';
import { Modal, Pressable, Text, TextInput, View } from 'react-native';

/**
 * A small single-field text prompt built from RN primitives + NativeWind.
 * Cross-platform stand-in for iOS-only `Alert.prompt` (used for list rename).
 * Controlled by `visible`; `onSubmit` fires with the trimmed text, `onCancel`
 * dismisses. Empty input is treated as cancel.
 */
export function PromptModal({
  visible,
  title,
  initialValue = '',
  placeholder,
  confirmLabel = 'Save',
  onSubmit,
  onCancel,
}: {
  visible: boolean;
  title: string;
  initialValue?: string;
  placeholder?: string;
  confirmLabel?: string;
  onSubmit: (value: string) => void;
  onCancel: () => void;
}) {
  const [text, setText] = useState(initialValue);
  // Reset the field to `initialValue` on each open, by adjusting state during
  // render on the open transition (the React-recommended alternative to an
  // effect: https://react.dev/learn/you-might-not-need-an-effect).
  const [wasVisible, setWasVisible] = useState(visible);
  if (visible !== wasVisible) {
    setWasVisible(visible);
    if (visible) setText(initialValue);
  }

  const submit = () => {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      onCancel();
      return;
    }
    onSubmit(trimmed);
  };

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCancel}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Dismiss"
        onPress={onCancel}
        className="flex-1 justify-center bg-black/40 px-8"
      >
        <Pressable className="rounded-xl bg-white p-4" onPress={() => {}}>
          <Text className="mb-3 text-base font-semibold text-gray-900">{title}</Text>
          <TextInput
            value={text}
            onChangeText={setText}
            placeholder={placeholder}
            placeholderTextColor="#9ca3af"
            autoFocus
            onSubmitEditing={submit}
            returnKeyType="done"
            className="rounded border border-gray-200 bg-white px-3 py-2 text-base text-gray-900"
          />
          <View className="mt-4 flex-row justify-end gap-4">
            <Pressable accessibilityRole="button" onPress={onCancel} className="px-2 py-1 active:opacity-60">
              <Text className="text-base text-gray-500">Cancel</Text>
            </Pressable>
            <Pressable accessibilityRole="button" onPress={submit} className="px-2 py-1 active:opacity-60">
              <Text className="text-base font-semibold text-blue-600">{confirmLabel}</Text>
            </Pressable>
          </View>
        </Pressable>
      </Pressable>
    </Modal>
  );
}
