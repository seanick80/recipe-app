import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { Pressable, Text, View } from 'react-native';

import { BarcodeScanScreen } from '../screens/BarcodeScanScreen';

/**
 * Route params for the Scan tab's native stack (Phase 5).
 *
 * Only the barcode scanner is wired up for now. A future "Scan photo / OCR"
 * mode will get its own route here (see the placeholder slot on ScanHome).
 */
export type ScanStackParamList = {
  ScanHome: undefined;
  BarcodeScan: undefined;
};

const Stack = createNativeStackNavigator<ScanStackParamList>();

type HomeProps = NativeStackScreenProps<ScanStackParamList, 'ScanHome'>;

/** Mode picker for the Scan tab. Barcode today; photo/OCR later. */
function ScanHomeScreen({ navigation }: HomeProps) {
  return (
    <View className="flex-1 bg-gray-50 px-4 pt-6">
      <Text className="mb-4 text-sm text-gray-500">
        Scan a product barcode to look it up and add it to a grocery list.
      </Text>

      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Scan barcode"
        onPress={() => navigation.navigate('BarcodeScan')}
        className="flex-row items-center rounded-lg border border-gray-100 bg-white px-4 py-4 active:bg-gray-50"
      >
        <Ionicons name="barcode-outline" size={26} color="#2563eb" />
        <View className="ml-3 flex-1">
          <Text className="text-base font-semibold text-gray-900">Scan barcode</Text>
          <Text className="mt-0.5 text-xs text-gray-400">Point your camera at a product barcode.</Text>
        </View>
        <Ionicons name="chevron-forward" size={18} color="#d1d5db" />
      </Pressable>

      {/*
        Future "Scan photo / OCR" mode goes here (separate later phase). It will
        push its own route (e.g. `PhotoScan`) added to ScanStackParamList. OCR is
        deliberately NOT part of the barcode phase.
      */}
    </View>
  );
}

export function ScanStack() {
  return (
    <Stack.Navigator>
      <Stack.Screen name="ScanHome" component={ScanHomeScreen} options={{ title: 'Scan' }} />
      <Stack.Screen name="BarcodeScan" component={BarcodeScanScreen} options={{ title: 'Scan Barcode' }} />
    </Stack.Navigator>
  );
}
