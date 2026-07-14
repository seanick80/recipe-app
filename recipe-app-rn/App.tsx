import './global.css';

import { NavigationContainer, type NavigationState } from '@react-navigation/native';
import { StatusBar } from 'expo-status-bar';
import { ActivityIndicator, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { GluestackUIProvider } from './components/ui/gluestack-ui-provider';
import { AuthProvider, useAuth } from './src/contexts/AuthContext';
import { GroceryProvider } from './src/contexts/GroceryContext';
import { SyncProvider } from './src/contexts/SyncContext';
import { debugLog } from './src/lib/debugLog';
import { initDebugLogPersistence } from './src/lib/debugLogInit';
import { RootTabs } from './src/navigation/RootTabs';
import { LoginScreen } from './src/screens/LoginScreen';

// Make the debug log durable BEFORE anything renders: hydrate pre-crash entries,
// install the SQLite sink, and register the global JS error handler.
initDebugLogPersistence();

/** Deepest active route name in a navigation state tree (the current screen). */
function activeRouteName(state: NavigationState | undefined): string | undefined {
  if (!state || typeof state.index !== 'number') return undefined;
  const route = state.routes[state.index];
  const child = route.state as NavigationState | undefined;
  return child ? activeRouteName(child) : route.name;
}

/** Breadcrumb: record the active route so a crash trail shows where we were. */
function logRouteChange(state: NavigationState | undefined): void {
  const name = activeRouteName(state);
  if (name) debugLog.log('nav', name);
}

/**
 * Auth gate: block on the initial session restore, show the login screen when
 * signed out, otherwise render the tab shell. A non-blocking banner surfaces
 * `needsReauth` (background validation/refresh failed) without kicking the user
 * out of their local view.
 */
function AppContent() {
  const { status, needsReauth } = useAuth();

  if (status === 'loading') {
    return (
      <View className="flex-1 items-center justify-center bg-white">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  if (status === 'unauthenticated') {
    return <LoginScreen />;
  }

  return (
    <View className="flex-1">
      {needsReauth ? (
        <View className="bg-amber-100 px-4 py-2">
          <Text className="text-center text-xs text-amber-800">
            Your session needs attention — sign in again from Settings.
          </Text>
        </View>
      ) : null}
      <View className="flex-1">
        <GroceryProvider>
          <SyncProvider>
            <NavigationContainer onStateChange={logRouteChange}>
              <RootTabs />
            </NavigationContainer>
          </SyncProvider>
        </GroceryProvider>
      </View>
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <GluestackUIProvider mode="light">
        <AuthProvider>
          <AppContent />
          <StatusBar style="auto" />
        </AuthProvider>
      </GluestackUIProvider>
    </SafeAreaProvider>
  );
}
