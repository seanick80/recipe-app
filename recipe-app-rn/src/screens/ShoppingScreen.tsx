import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect } from 'react';
import { ActionSheetIOS, ActivityIndicator, Alert, Platform, Pressable, View } from 'react-native';

import { GroceryListBody } from '../components/GroceryListBody';
import { useGrocery } from '../contexts/GroceryContext';
import type { ShoppingStackParamList } from '../navigation/ShoppingStack';

type Props = NativeStackScreenProps<ShoppingStackParamList, 'ShoppingHome'>;

/**
 * Shopping tab — THE single persistent shopping list. Add manual items /
 * staples / recipe ingredients, check them off, then remove the checked ones;
 * unpurchased items stay for the next trip. The list is guaranteed to exist
 * (GroceryContext.ensureSingleList), so there is no create/switch/archive UI —
 * only item actions and the staples presets. Item UI is the shared
 * {@link GroceryListBody}; the header "…" menu hosts the bulk actions.
 */
export function ShoppingScreen({ navigation }: Props) {
  const { list, initializing, ensureDefaultTemplate, addStaples, removeChecked, clearItems } = useGrocery();

  const addStaplesToList = useCallback(async () => {
    if (!list) return;
    const template = await ensureDefaultTemplate();
    if (template.items.length === 0) {
      Alert.alert('No staples yet', 'Add some in "Edit staples" first.');
      return;
    }
    const added = await addStaples(list.id, template.id);
    Alert.alert(added > 0 ? `Added ${added} item${added === 1 ? '' : 's'}` : 'Already stocked', undefined);
  }, [list, ensureDefaultTemplate, addStaples]);

  const editStaples = useCallback(async () => {
    const template = await ensureDefaultTemplate();
    navigation.navigate('TemplateEditor', { templateId: template.id });
  }, [ensureDefaultTemplate, navigation]);

  // Confirm before wiping the whole list (preserved from the old menu).
  const confirmClearAll = useCallback(() => {
    if (!list) return;
    Alert.alert('Clear all items?', undefined, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Clear', style: 'destructive', onPress: () => void clearItems(list.id) },
    ]);
  }, [list, clearItems]);

  // The header "…" bulk-actions menu. Check-all/Uncheck-all now lives on the add
  // bar (GroceryListBody), so it's intentionally absent here. Native ActionSheet
  // on iOS (Clear all destructive, Cancel last); Alert fallback on Android.
  const openActions = useCallback(() => {
    if (!list) return;
    const actions: { label: string; run: () => void; destructive?: boolean }[] = [
      { label: 'Remove checked', run: () => void removeChecked(list.id) },
      { label: 'Clear all', run: confirmClearAll, destructive: true },
      { label: 'Add staples', run: () => void addStaplesToList() },
      { label: 'Edit staples', run: () => void editStaples() },
      { label: 'Generate from Recipes', run: () => navigation.navigate('GenerateGroceryList') },
    ];

    if (Platform.OS === 'ios') {
      const options = [...actions.map((a) => a.label), 'Cancel'];
      const cancelButtonIndex = actions.length;
      const destructiveButtonIndex = actions.findIndex((a) => a.destructive);
      ActionSheetIOS.showActionSheetWithOptions(
        {
          title: 'Shopping',
          options,
          cancelButtonIndex,
          destructiveButtonIndex: destructiveButtonIndex >= 0 ? destructiveButtonIndex : undefined,
        },
        (index) => {
          if (index === cancelButtonIndex) return;
          actions[index]?.run();
        },
      );
      return;
    }

    Alert.alert('Shopping', undefined, [
      ...actions.map((a) => ({
        text: a.label,
        style: a.destructive ? ('destructive' as const) : undefined,
        onPress: a.run,
      })),
      { text: 'Cancel', style: 'cancel' as const },
    ]);
  }, [list, removeChecked, confirmClearAll, addStaplesToList, editStaples, navigation]);

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Shopping actions"
          onPress={openActions}
          className="active:opacity-60"
        >
          <Ionicons name="ellipsis-horizontal" size={22} color="#2563eb" />
        </Pressable>
      ),
    });
  }, [navigation, openActions]);

  if (initializing || !list) {
    return (
      <View className="flex-1 items-center justify-center bg-gray-50">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  return <GroceryListBody />;
}
