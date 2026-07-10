import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { ArchivedListsScreen } from '../screens/ArchivedListsScreen';
import { ShoppingScreen } from '../screens/ShoppingScreen';
import { TemplateEditorScreen } from '../screens/TemplateEditorScreen';

/** Route params for the Shopping (staples) tab's native stack (Phase 4 slice 3b). */
export type ShoppingStackParamList = {
  ShoppingHome: undefined;
  TemplateEditor: { templateId: string };
  ArchivedLists: undefined;
};

const Stack = createNativeStackNavigator<ShoppingStackParamList>();

export function ShoppingStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="ShoppingHome" component={ShoppingScreen} options={{ title: 'Shopping' }} />
      <Stack.Screen name="TemplateEditor" component={TemplateEditorScreen} options={{ title: 'Staples' }} />
      <Stack.Screen name="ArchivedLists" component={ArchivedListsScreen} options={{ title: 'Archived Lists' }} />
    </Stack.Navigator>
  );
}
