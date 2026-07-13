import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { LogsScreen } from '../screens/LogsScreen';
import { SettingsScreen } from '../screens/SettingsScreen';

export type SettingsStackParamList = {
  SettingsHome: undefined;
  Logs: undefined;
};

const Stack = createNativeStackNavigator<SettingsStackParamList>();

/** Settings tab stack — the settings list plus the debug logs viewer (Phase 4). */
export function SettingsStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="SettingsHome" component={SettingsScreen} options={{ title: 'Settings' }} />
      <Stack.Screen name="Logs" component={LogsScreen} options={{ title: 'App logs' }} />
    </Stack.Navigator>
  );
}
