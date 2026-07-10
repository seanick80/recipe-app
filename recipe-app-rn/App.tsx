import './global.css';

import { NavigationContainer } from '@react-navigation/native';
import { StatusBar } from 'expo-status-bar';
import { ActivityIndicator, Text, View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { AuthProvider, useAuth } from './src/contexts/AuthContext';
import { SyncProvider } from './src/contexts/SyncContext';
import { RootTabs } from './src/navigation/RootTabs';
import { LoginScreen } from './src/screens/LoginScreen';

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
        <SyncProvider>
          <NavigationContainer>
            <RootTabs />
          </NavigationContainer>
        </SyncProvider>
      </View>
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <AuthProvider>
        <AppContent />
        <StatusBar style="auto" />
      </AuthProvider>
    </SafeAreaProvider>
  );
}
