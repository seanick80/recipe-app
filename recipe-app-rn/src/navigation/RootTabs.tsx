import type { ComponentType } from 'react';
import { Ionicons } from '@expo/vector-icons';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { Placeholder } from '../components/Placeholder';
import { ListsStack } from './ListsStack';
import { RecipesStack } from './RecipesStack';
import { SettingsStack } from './SettingsStack';
import { ShoppingStack } from './ShoppingStack';
import { TABS, type TabConfig } from './tabs';

const Tab = createBottomTabNavigator();

/**
 * Each tab gets its own native-stack navigator (mirrors the SwiftUI app's
 * per-tab `NavigationStack`). For Phase 0 each stack holds a single
 * placeholder screen; real screens get pushed onto these stacks later.
 */
function createTabStack(tab: TabConfig) {
  const Stack = createNativeStackNavigator();
  return function TabStack() {
    return (
      <Stack.Navigator>
        <Stack.Screen name={tab.home} options={{ title: tab.title }}>
          {() => <Placeholder title={tab.title} subtitle={tab.subtitle} />}
        </Stack.Screen>
      </Stack.Navigator>
    );
  };
}

// Recipes, Shopping, Lists, and Settings have real screens (Phases 2/4); only
// Scan stays a placeholder until the Phase 5 camera work lands.
const REAL_STACKS: Record<string, ComponentType> = {
  Recipes: RecipesStack,
  Shopping: ShoppingStack,
  Lists: ListsStack,
  Settings: SettingsStack,
};

const TAB_STACKS = TABS.map((tab) => ({
  tab,
  Component: REAL_STACKS[tab.name] ?? createTabStack(tab),
}));

export function RootTabs() {
  return (
    <Tab.Navigator screenOptions={{ headerShown: false }}>
      {TAB_STACKS.map(({ tab, Component }) => (
        <Tab.Screen
          key={tab.name}
          name={tab.name}
          component={Component}
          options={{
            tabBarIcon: ({ color, size }) => (
              <Ionicons name={tab.icon} color={color} size={size} />
            ),
          }}
        />
      ))}
    </Tab.Navigator>
  );
}
