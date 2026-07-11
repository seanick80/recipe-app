import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { RecipeDetailScreen } from '../screens/RecipeDetailScreen';
import { RecipeEditScreen } from '../screens/RecipeEditScreen';
import { RecipeListScreen } from '../screens/RecipeListScreen';

/** Route params for the Recipes tab's native stack. */
export type RecipesStackParamList = {
  RecipesHome: undefined;
  RecipeDetail: { localId: string; name: string };
  /** `localId` present = edit an existing recipe; absent = create a new one. */
  RecipeEdit: { localId?: string };
};

const Stack = createNativeStackNavigator<RecipesStackParamList>();

export function RecipesStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="RecipesHome" component={RecipeListScreen} options={{ title: 'Recipes' }} />
      <Stack.Screen
        name="RecipeDetail"
        component={RecipeDetailScreen}
        options={({ route }) => ({ title: route.params.name })}
      />
      <Stack.Screen
        name="RecipeEdit"
        component={RecipeEditScreen}
        options={{ presentation: 'modal', title: 'Recipe' }}
      />
    </Stack.Navigator>
  );
}
