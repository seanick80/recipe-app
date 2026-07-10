import { createNativeStackNavigator } from '@react-navigation/native-stack';

import { SettingsScreen } from '../screens/SettingsScreen';

export type SettingsStackParamList = {
  SettingsHome: undefined;
};

const Stack = createNativeStackNavigator<SettingsStackParamList>();

/** Settings tab stack — a single screen with a header (Phase 4). */
export function SettingsStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="SettingsHome" component={SettingsScreen} options={{ title: 'Settings' }} />
    </Stack.Navigator>
  );
}
