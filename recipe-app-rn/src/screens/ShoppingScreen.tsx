import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect } from 'react';
import { ActivityIndicator, Alert, Pressable, View } from 'react-native';

import { GroceryListBody } from '../components/GroceryListBody';
import { useGrocery } from '../contexts/GroceryContext';
import { allItemsChecked } from '../grocery/groceryLogic';
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
  const { list, initializing, ensureDefaultTemplate, addStaples, setAllChecked, removeChecked, clearItems } =
    useGrocery();
  const allChecked = allItemsChecked(list?.items ?? []);

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

  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: () => (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Shopping actions"
          onPress={() => {
            const buttons: { text: string; style?: 'cancel' | 'destructive'; onPress?: () => void }[] = [];
            if (list) {
              buttons.push({
                text: allChecked ? 'Uncheck all' : 'Check all',
                onPress: () => void setAllChecked(list.id, !allChecked),
              });
              buttons.push({ text: 'Remove checked', onPress: () => void removeChecked(list.id) });
              buttons.push({
                text: 'Clear all',
                style: 'destructive',
                onPress: () =>
                  Alert.alert('Clear all items?', undefined, [
                    { text: 'Cancel', style: 'cancel' },
                    { text: 'Clear', style: 'destructive', onPress: () => void clearItems(list.id) },
                  ]),
              });
            }
            buttons.push({ text: 'Generate from Recipes', onPress: () => navigation.navigate('GenerateGroceryList') });
            buttons.push({ text: 'Add staples', onPress: () => void addStaplesToList() });
            buttons.push({ text: 'Edit staples', onPress: () => void editStaples() });
            buttons.push({ text: 'Cancel', style: 'cancel' });
            Alert.alert('Shopping', undefined, buttons);
          }}
          className="active:opacity-60"
        >
          <Ionicons name="ellipsis-horizontal" size={22} color="#2563eb" />
        </Pressable>
      ),
    });
  }, [navigation, list, allChecked, setAllChecked, removeChecked, clearItems, addStaplesToList, editStaples]);

  if (initializing || !list) {
    return (
      <View className="flex-1 items-center justify-center bg-gray-50">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  return <GroceryListBody />;
}
