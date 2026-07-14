import { createNativeStackNavigator } from '@react-navigation/native-stack';

import type { ImportedRecipe } from '../lib/recipeSchemaParser';
import { ImportReviewScreen } from '../screens/ImportReviewScreen';
import { RecipeDetailScreen } from '../screens/RecipeDetailScreen';
import { RecipeEditScreen } from '../screens/RecipeEditScreen';
import { RecipeListScreen } from '../screens/RecipeListScreen';

/** Route params for the Recipes tab's native stack. */
export type RecipesStackParamList = {
  RecipesHome: undefined;
  RecipeDetail: { localId: string; name: string };
  /** `localId` present = edit an existing recipe; absent = create a new one. */
  RecipeEdit: { localId?: string };
  /**
   * Review a recipe parsed from a URL before saving. This is the shared target
   * for the manual "Import from URL" flow and, in a later phase, the platform
   * share entry points (iOS Share Extension / Android share-intent), which will
   * navigate here with an already-parsed recipe.
   */
  ImportReview: { recipe: ImportedRecipe };
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
      <Stack.Screen name="ImportReview" component={ImportReviewScreen} options={{ title: 'Import Recipe' }} />
    </Stack.Navigator>
  );
}
