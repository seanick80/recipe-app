/**
 * App-level navigation ref for imperative navigation from outside the React
 * component tree — specifically the Android/iOS share-sheet import handler,
 * which fires from an app-level effect and has no `navigation` prop of its own.
 *
 * Attached to the root `NavigationContainer` in `App.tsx`. Screens continue to
 * use the `useNavigation` hook / route props as normal; this ref is only for
 * the share entry point.
 */
import { createNavigationContainerRef, type NavigatorScreenParams } from '@react-navigation/native';

import type { RecipesStackParamList } from './RecipesStack';

/** The bottom-tab routes (see `tabs.ts`). Params only matter for Recipes. */
export type RootTabsParamList = {
  Recipes: NavigatorScreenParams<RecipesStackParamList> | undefined;
  Shopping: undefined;
  Scan: undefined;
  Lists: undefined;
  Settings: undefined;
};

export const navigationRef = createNavigationContainerRef<RootTabsParamList>();
