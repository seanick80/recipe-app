import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { GenerateGroceryListScreen } from '../screens/GenerateGroceryListScreen';
import { ShoppingScreen } from '../screens/ShoppingScreen';
import { TemplateEditorScreen } from '../screens/TemplateEditorScreen';

/** Route params for the Shopping tab's native stack (single-list shopping). */
export type ShoppingStackParamList = {
  ShoppingHome: undefined;
  TemplateEditor: { templateId: string };
  GenerateGroceryList: undefined;
};

const Stack = createNativeStackNavigator<ShoppingStackParamList>();

export function ShoppingStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="ShoppingHome" component={ShoppingScreen} options={{ title: 'Shopping' }} />
      <Stack.Screen name="TemplateEditor" component={TemplateEditorScreen} options={{ title: 'Staples' }} />
      <Stack.Screen
        name="GenerateGroceryList"
        component={GenerateGroceryListScreen}
        options={{ presentation: 'modal', title: 'From Recipes' }}
      />
    </Stack.Navigator>
  );
}
