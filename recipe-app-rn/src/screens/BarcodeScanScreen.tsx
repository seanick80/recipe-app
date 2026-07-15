import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { CameraView, useCameraPermissions, type BarcodeScanningResult } from 'expo-camera';
import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import { lookupBarcode } from '../lib/barcodeLookup';
import { formatProductDisplay, type ProductLookupResult } from '../lib/barcodeProductMapper';
import { debugLog } from '../lib/debugLog';
import type { ScanStackParamList } from '../navigation/ScanStack';

type Props = NativeStackScreenProps<ScanStackParamList, 'BarcodeScan'>;

/** Barcode symbologies we scan for (1D grocery codes + QR as a bonus). */
const BARCODE_TYPES = ['ean13', 'ean8', 'upc_a', 'upc_e', 'qr'] as const;

/** Ignore duplicate scans of the same code within this window (ms). */
const RESCAN_GUARD_MS = 2500;

/**
 * What the result sheet is showing: a resolved product, or a "not found" for a
 * raw barcode the user can still add manually.
 */
type ScanOutcome =
  | { kind: 'found'; product: ProductLookupResult }
  | { kind: 'notFound'; barcode: string };

/**
 * Live barcode scanner (Phase 5). Mounts an `expo-camera` `CameraView`, decodes
 * grocery barcodes, looks them up on Open Food Facts via {@link lookupBarcode},
 * and drops the product onto the single persistent shopping list.
 *
 * The camera preview + live decode can only be exercised on a real device; the
 * lookup/add wiring is unit-tested in `src/lib/barcodeLookup.test.ts`.
 */
export function BarcodeScanScreen({ navigation }: Props) {
  const [permission, requestPermission] = useCameraPermissions();
  const { list, addItem } = useGrocery();

  const [looking, setLooking] = useState(false);
  const [outcome, setOutcome] = useState<ScanOutcome | null>(null);

  // Scan guard: suppress the same code fired repeatedly by the camera, and
  // freeze scanning entirely while we're looking up / showing a result.
  const lastCodeRef = useRef<string | null>(null);
  const lastAtRef = useRef(0);
  const busyRef = useRef(false);

  const resetScan = useCallback(() => {
    setOutcome(null);
    setLooking(false);
    busyRef.current = false;
    // Force the guard to accept the next scan even if it's the same code.
    lastCodeRef.current = null;
  }, []);

  const onBarcodeScanned = useCallback(
    (result: BarcodeScanningResult) => {
      const code = result.data.trim();
      const now = Date.now();
      if (busyRef.current) return;
      if (code.length === 0) return;
      if (lastCodeRef.current === code && now - lastAtRef.current < RESCAN_GUARD_MS) return;
      lastCodeRef.current = code;
      lastAtRef.current = now;
      busyRef.current = true;

      setLooking(true);
      void (async () => {
        const product = await lookupBarcode(code);
        debugLog.log('scan.barcode', 'Barcode scanned', { code, found: String(product !== null) });
        setLooking(false);
        setOutcome(product ? { kind: 'found', product } : { kind: 'notFound', barcode: code });
      })();
    },
    [],
  );

  const addToList = useCallback(async () => {
    if (!outcome || !list) return;
    const name =
      outcome.kind === 'found'
        ? formatProductDisplay(outcome.product.name, outcome.product.brand)
        : outcome.barcode;
    await addItem(list.id, name, 1, '');
    resetScan();
  }, [outcome, list, addItem, resetScan]);

  // --- permission gates ---
  if (!permission) {
    return (
      <View className="flex-1 items-center justify-center bg-gray-50">
        <ActivityIndicator size="large" color="#111827" />
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View className="flex-1 items-center justify-center bg-gray-50 px-8">
        <Ionicons name="camera-outline" size={48} color="#9ca3af" />
        <Text className="mt-4 text-center text-base text-gray-600">
          {permission.canAskAgain
            ? 'Camera access is needed to scan barcodes.'
            : 'Camera access is off. Enable it in Settings to scan barcodes.'}
        </Text>
        {permission.canAskAgain ? (
          <Pressable
            accessibilityRole="button"
            onPress={() => void requestPermission()}
            className="mt-6 rounded-lg bg-gray-900 px-6 py-3 active:opacity-80"
          >
            <Text className="font-semibold text-white">Grant camera access</Text>
          </Pressable>
        ) : null}
      </View>
    );
  }

  return (
    <View className="flex-1 bg-black">
      <CameraView
        style={{ flex: 1 }}
        facing="back"
        barcodeScannerSettings={{ barcodeTypes: [...BARCODE_TYPES] }}
        // Freeze decoding while a lookup/result is in flight.
        onBarcodeScanned={outcome || looking ? undefined : onBarcodeScanned}
      />

      {/* Aiming hint overlay. */}
      <View pointerEvents="none" className="absolute inset-x-0 top-0 items-center pt-6">
        <Text className="rounded-full bg-black/50 px-4 py-2 text-sm text-white">
          Point the camera at a barcode
        </Text>
      </View>

      {looking ? (
        <View className="absolute inset-0 items-center justify-center bg-black/50">
          <ActivityIndicator size="large" color="#fff" />
          <Text className="mt-3 text-base text-white">Looking up product…</Text>
        </View>
      ) : null}

      {/* Result sheet: found product or manual-add fallback + list picker. */}
      <Modal visible={outcome !== null} transparent animationType="slide" onRequestClose={resetScan}>
        <View className="flex-1 justify-end bg-black/40">
          <View className="max-h-[80%] rounded-t-2xl bg-white p-4">
            {outcome?.kind === 'found' ? (
              <View className="mb-3">
                <Text className="text-lg font-semibold text-gray-900">
                  {formatProductDisplay(outcome.product.name, outcome.product.brand)}
                </Text>
                <Text className="mt-0.5 text-xs text-gray-400">
                  {outcome.product.category}
                  {outcome.product.quantity ? ` · ${outcome.product.quantity}` : ''} · {outcome.product.barcode}
                </Text>
              </View>
            ) : outcome?.kind === 'notFound' ? (
              <View className="mb-3">
                <Text className="text-lg font-semibold text-gray-900">Product not found</Text>
                <Text className="mt-0.5 text-sm text-gray-500">
                  No match for barcode {outcome.barcode}. Add it manually to a list?
                </Text>
              </View>
            ) : null}

            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Add to shopping list"
              onPress={() => void addToList()}
              className="mt-1 flex-row items-center justify-center rounded-lg bg-gray-900 px-4 py-3 active:opacity-80"
            >
              <Ionicons name="add" size={18} color="#fff" />
              <Text className="ml-2 font-semibold text-white">Add to shopping list</Text>
            </Pressable>

            <View className="mt-3 flex-row justify-between">
              <Pressable accessibilityRole="button" onPress={resetScan} className="px-2 py-2 active:opacity-60">
                <Text className="text-base text-blue-600">Scan another</Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  resetScan();
                  navigation.goBack();
                }}
                className="px-2 py-2 active:opacity-60"
              >
                <Text className="text-base text-gray-500">Done</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}
