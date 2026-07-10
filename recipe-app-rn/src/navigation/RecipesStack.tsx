import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { RecipeDetailScreen } from '../screens/RecipeDetailScreen';
import { RecipeListScreen } from '../screens/RecipeListScreen';

/** Route params for the Recipes tab's native stack. */
export type RecipesStackParamList = {
  RecipesHome: undefined;
  RecipeDetail: { localId: string; name: string };
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
    </Stack.Navigator>
  );
}
