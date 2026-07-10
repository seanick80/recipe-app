import type { ComponentType } from 'react';
import { Ionicons } from '@expo/vector-icons';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { Placeholder } from '../components/Placeholder';
import { ListsStack } from './ListsStack';
import { RecipesStack } from './RecipesStack';
import { SettingsStack } from './SettingsStack';
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

// Recipes (Phase 2/4), Lists (Phase 4), and Settings (Phase 4) have real
// screens; Shopping and Scan stay placeholders until their phases land.
const REAL_STACKS: Record<string, ComponentType> = {
  Recipes: RecipesStack,
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
