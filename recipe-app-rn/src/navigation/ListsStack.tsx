import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { GenerateGroceryListScreen } from '../screens/GenerateGroceryListScreen';
import { GroceryListDetailScreen } from '../screens/GroceryListDetailScreen';
import { GroceryListsScreen } from '../screens/GroceryListsScreen';

/** Route params for the Lists (grocery) tab's native stack (Phase 4 slice 3). */
export type ListsStackParamList = {
  ListsHome: undefined;
  GroceryListDetail: { listId: string; name: string };
  GenerateGroceryList: undefined;
};

const Stack = createNativeStackNavigator<ListsStackParamList>();

export function ListsStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="ListsHome" component={GroceryListsScreen} options={{ title: 'Lists' }} />
      <Stack.Screen
        name="GroceryListDetail"
        component={GroceryListDetailScreen}
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Screen
        name="GenerateGroceryList"
        component={GenerateGroceryListScreen}
        options={{ presentation: 'modal', title: 'From Recipes' }}
      />
    </Stack.Navigator>
  );
}
