import { Ionicons } from '@expo/vector-icons';
import TextRecognition from '@react-native-ml-kit/text-recognition';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { CameraView, useCameraPermissions } from 'expo-camera';
import { useCallback, useRef, useState } from 'react';
import { ActivityIndicator, Modal, Pressable, ScrollView, Text, View } from 'react-native';

import { useGrocery } from '../contexts/GroceryContext';
import { debugLog } from '../lib/debugLog';
import type { ParsedListItem } from '../lib/listLineParser';
import { mlKitToOCRLines, type MLKitResult } from '../lib/ocrAdapter';
import { runOCRPipeline, type OCRPipelineResult } from '../lib/ocrPipeline';
import { navigationRef } from '../navigation/navigationRef';
import type { ScanStackParamList } from '../navigation/ScanStack';

type Props = NativeStackScreenProps<ScanStackParamList, 'PhotoScan'>;

/**
 * Photo/OCR scan mode (Phase 5). Captures a still with `expo-camera`, runs
 * Google ML Kit on-device text recognition on the image, adapts the result into
 * the ported `OCRLine[]` pipeline ({@link mlKitToOCRLines} → {@link runOCRPipeline}),
 * and routes:
 *   - a recognized **recipe** → the Recipes tab's `ImportReview` screen (via the
 *     app {@link navigationRef}, same path the URL/share import uses);
 *   - a recognized **shopping list** → an in-screen review sheet where the user
 *     drops every parsed item onto the single persistent shopping list.
 *
 * When the pipeline judges the capture low-quality it surfaces a "retake?" sheet
 * first; the user can retake or use the result anyway.
 *
 * The camera capture + real OCR are only exercisable on a device; the adapter
 * and pipeline are unit-tested in `src/lib/ocrAdapter.test.ts` /
 * `src/lib/ocrPipeline.test.ts`.
 */
export function PhotoCaptureScreen({ navigation }: Props) {
  const [permission, requestPermission] = useCameraPermissions();
  const { list, addItem } = useGrocery();

  const cameraRef = useRef<CameraView>(null);
  const busyRef = useRef(false);

  const [busy, setBusy] = useState(false);
  // A parsed shopping list awaiting a target grocery list.
  const [shoppingItems, setShoppingItems] = useState<ParsedListItem[] | null>(null);
  // A low-quality result awaiting the user's retake/continue decision.
  const [retake, setRetake] = useState<OCRPipelineResult | null>(null);

  const reset = useCallback(() => {
    setBusy(false);
    setShoppingItems(null);
    setRetake(null);
    busyRef.current = false;
  }, []);

  // Send a routed pipeline result to its destination.
  const route = useCallback((result: OCRPipelineResult) => {
    if (result.kind === 'recipe') {
      // Hand off to the Recipes tab's review screen (typed cross-tab nav).
      if (navigationRef.isReady()) {
        navigationRef.navigate('Recipes', { screen: 'ImportReview', params: { recipe: result.recipe } });
      }
      setBusy(false);
      busyRef.current = false;
    } else {
      // Shopping: open the list picker sheet.
      setShoppingItems(result.items);
      setBusy(false);
      busyRef.current = false;
    }
  }, []);

  const capture = useCallback(async () => {
    if (busyRef.current) return;
    const camera = cameraRef.current;
    if (!camera) return;
    busyRef.current = true;
    setBusy(true);

    try {
      const photo = await camera.takePictureAsync();
      if (!photo) {
        reset();
        return;
      }
      const mlResult = (await TextRecognition.recognize(photo.uri)) as unknown as MLKitResult;
      const lines = mlKitToOCRLines(mlResult, photo.width, photo.height);
      const result = runOCRPipeline(lines);
      debugLog.log('scan.photo', 'Photo OCR', {
        detected: result.detected,
        lines: String(lines.length),
        shouldRetake: String(result.quality.shouldRetake),
      });

      if (result.quality.shouldRetake) {
        // Let the user decide: retake or use it anyway.
        setRetake(result);
        setBusy(false);
        busyRef.current = false;
        return;
      }
      route(result);
    } catch (err) {
      debugLog.log('scan.photo', 'Photo OCR failed', { error: String(err) });
      reset();
    }
  }, [reset, route]);

  const addAllToList = useCallback(async () => {
    if (!shoppingItems || !list) return;
    for (const item of shoppingItems) {
      await addItem(list.id, item.name, item.quantity, item.unit);
    }
    reset();
  }, [shoppingItems, list, addItem, reset]);

  // --- permission gates (mirror BarcodeScanScreen) ---
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
            ? 'Camera access is needed to scan recipes and lists.'
            : 'Camera access is off. Enable it in Settings to scan photos.'}
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
      <CameraView ref={cameraRef} style={{ flex: 1 }} facing="back" />

      {/* Aiming hint overlay. */}
      <View pointerEvents="none" className="absolute inset-x-0 top-0 items-center pt-6">
        <Text className="rounded-full bg-black/50 px-4 py-2 text-sm text-white">
          Frame a recipe or shopping list, then tap capture
        </Text>
      </View>

      {/* Capture button. */}
      <View className="absolute inset-x-0 bottom-0 items-center pb-10">
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Capture photo"
          disabled={busy}
          onPress={() => void capture()}
          className="items-center justify-center rounded-full border-4 border-white/80 bg-white/20 p-1 active:opacity-70"
          style={{ height: 72, width: 72 }}
        >
          <View className="h-full w-full rounded-full bg-white" />
        </Pressable>
      </View>

      {busy ? (
        <View className="absolute inset-0 items-center justify-center bg-black/50">
          <ActivityIndicator size="large" color="#fff" />
          <Text className="mt-3 text-base text-white">Reading text…</Text>
        </View>
      ) : null}

      {/* Low-quality "retake?" sheet. */}
      <Modal visible={retake !== null} transparent animationType="slide" onRequestClose={reset}>
        <View className="flex-1 justify-end bg-black/40">
          <View className="rounded-t-2xl bg-white p-4">
            <Text className="text-lg font-semibold text-gray-900">Hard to read</Text>
            <Text className="mt-1 text-sm text-gray-500">
              {retake?.quality.reason || 'The photo may be blurry or poorly lit.'} Retake for a better result?
            </Text>
            <View className="mt-4 flex-row justify-end gap-4">
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  const r = retake;
                  setRetake(null);
                  if (r) route(r);
                }}
                className="px-3 py-2 active:opacity-60"
              >
                <Text className="text-base text-gray-500">Use anyway</Text>
              </Pressable>
              <Pressable accessibilityRole="button" onPress={reset} className="px-3 py-2 active:opacity-60">
                <Text className="text-base font-semibold text-blue-600">Retake</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>

      {/* Shopping-list review + list picker. */}
      <Modal visible={shoppingItems !== null} transparent animationType="slide" onRequestClose={reset}>
        <View className="flex-1 justify-end bg-black/40">
          <View className="max-h-[85%] rounded-t-2xl bg-white p-4">
            <Text className="text-lg font-semibold text-gray-900">
              {shoppingItems?.length ?? 0} item{(shoppingItems?.length ?? 0) === 1 ? '' : 's'} found
            </Text>

            <ScrollView className="my-3 max-h-40">
              {(shoppingItems ?? []).map((item, i) => (
                <View key={`${item.name}-${i}`} className="flex-row justify-between border-b border-gray-100 py-1.5">
                  <Text className="flex-1 text-sm text-gray-800" numberOfLines={1}>
                    {item.name}
                  </Text>
                  {item.quantity !== 1 || item.unit ? (
                    <Text className="ml-3 text-sm text-gray-400">
                      {item.quantity}
                      {item.unit ? ` ${item.unit}` : ''}
                    </Text>
                  ) : null}
                </View>
              ))}
            </ScrollView>

            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Add all to shopping list"
              disabled={(shoppingItems?.length ?? 0) === 0}
              onPress={() => void addAllToList()}
              className="mt-1 flex-row items-center justify-center rounded-lg bg-gray-900 px-4 py-3 active:opacity-80"
            >
              <Ionicons name="add" size={18} color="#fff" />
              <Text className="ml-2 font-semibold text-white">Add all to shopping list</Text>
            </Pressable>

            <View className="mt-3 flex-row justify-between">
              <Pressable accessibilityRole="button" onPress={reset} className="px-2 py-2 active:opacity-60">
                <Text className="text-base text-blue-600">Scan another</Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                onPress={() => {
                  reset();
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
