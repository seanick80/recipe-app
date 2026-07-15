import { Ionicons } from '@expo/vector-icons';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { useCallback, useLayoutEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  RefreshControl,
  Text,
  TextInput,
  View,
} from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { useSync } from '../contexts/SyncContext';
import { fetchAndParseRecipe } from '../lib/recipeImport';
import { totalTimeMinutes } from '../lib/recipeFormat';
import type { RecipesStackParamList } from '../navigation/RecipesStack';
import type { LocalRecipe } from '../sync/types';

type Props = NativeStackScreenProps<RecipesStackParamList, 'RecipesHome'>;

function RecipeRow({
  recipe,
  onPress,
  onLongPress,
}: {
  recipe: LocalRecipe;
  onPress: () => void;
  onLongPress: () => void;
}) {
  const meta = [
    totalTimeMinutes(recipe) > 0 ? `${totalTimeMinutes(recipe)} min` : null,
    recipe.cuisine.trim() || null,
    recipe.course.trim() || null,
    recipe.servings > 0 ? `${recipe.servings} servings` : null,
  ].filter((s): s is string => s !== null);

  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      onLongPress={onLongPress}
      className="border-b border-gray-100 px-4 py-3 active:bg-gray-50"
    >
      <View className="flex-row items-center">
        <Text className="flex-1 text-lg font-semibold text-gray-900" numberOfLines={1}>
          {recipe.name}
        </Text>
        {recipe.needsSync ? <Ionicons name="cloud-upload-outline" size={16} color="#9ca3af" /> : null}
        {recipe.is_favorite ? (
          <Ionicons name="star" size={18} color="#f59e0b" style={{ marginLeft: 6 }} />
        ) : null}
      </View>
      {recipe.summary.trim().length > 0 ? (
        <Text className="mt-1 text-sm text-gray-500" numberOfLines={2}>
          {recipe.summary}
        </Text>
      ) : null}
      {meta.length > 0 ? <Text className="mt-1 text-xs text-gray-400">{meta.join(' · ')}</Text> : null}
    </Pressable>
  );
}

function CenteredMessage({ children }: { children: React.ReactNode }) {
  return <View className="flex-1 items-center justify-center px-8">{children}</View>;
}

/**
 * Offline-first recipe list (Phase 3). Reads exclusively from the local store
 * via {@link useSync}; pull-to-refresh triggers a server sync. Guests see a gate
 * (no token, no sync). Banners surface a non-fatal sync error and any unpushed
 * writes without blocking the local view.
 */
export function RecipeListScreen({ navigation }: Props) {
  const { token, isGuest } = useAuth();
  const { recipes, initializing, error, hasWriteFailures, syncNow, deleteRecipe } = useSync();

  const authed = !!token && !isGuest;

  // Pull-to-refresh spinner state, kept local + distinct from the context's
  // global `syncing` flag. The RefreshControl must only spin for a refresh the
  // user actually pulled — binding it to background syncs (app foreground /
  // post-write / initial load) left the spinner stranded when the tab regained
  // focus mid-sync, clearing only on a manual pull. It always resets when the
  // sync settles (success or error).
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await syncNow();
    } finally {
      setRefreshing(false);
    }
  }, [syncNow]);

  // "Import from URL" prompt state.
  const [importVisible, setImportVisible] = useState(false);
  const [importUrl, setImportUrl] = useState('');
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);

  const openImport = useCallback(() => {
    setImportUrl('');
    setImportError(null);
    setImporting(false);
    setImportVisible(true);
  }, []);

  const closeImport = useCallback(() => {
    if (importing) return;
    setImportVisible(false);
  }, [importing]);

  // Fetch + parse the entered URL, then hand the parsed recipe to the shared
  // ImportReview step (the same target the future share entry points will use).
  const runImport = useCallback(async () => {
    if (importing) return;
    setImporting(true);
    setImportError(null);
    const result = await fetchAndParseRecipe(importUrl);
    setImporting(false);
    if (result.success) {
      setImportVisible(false);
      navigation.navigate('ImportReview', { recipe: result.recipe });
    } else {
      setImportError(result.message);
    }
  }, [importing, importUrl, navigation]);

  // Header actions: "Import from URL" + "+" to create (authenticated users only).
  useLayoutEffect(() => {
    navigation.setOptions({
      headerRight: authed
        ? () => (
            <View className="flex-row items-center">
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Import recipe from URL"
                onPress={openImport}
                className="mr-4 active:opacity-60"
              >
                <Ionicons name="link" size={24} color="#2563eb" />
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="New recipe"
                onPress={() => navigation.navigate('RecipeEdit', {})}
                className="active:opacity-60"
              >
                <Ionicons name="add" size={28} color="#2563eb" />
              </Pressable>
            </View>
          )
        : undefined,
    });
  }, [navigation, authed, openImport]);

  const confirmDelete = useCallback(
    (recipe: LocalRecipe) => {
      Alert.alert('Delete recipe?', `“${recipe.name}” will be removed.`, [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Delete', style: 'destructive', onPress: () => void deleteRecipe(recipe.localId) },
      ]);
    },
    [deleteRecipe],
  );

  if (isGuest || !token) {
    return (
      <CenteredMessage>
        <Text className="text-center text-base text-gray-500">
          Sign in to browse recipes from the server.
        </Text>
      </CenteredMessage>
    );
  }

  if (initializing) {
    return (
      <CenteredMessage>
        <ActivityIndicator size="large" color="#111827" />
      </CenteredMessage>
    );
  }

  return (
    <View className="flex-1">
      {error ? (
        <View className="bg-red-50 px-4 py-2">
          <Text className="text-center text-xs text-red-700">{error}</Text>
        </View>
      ) : hasWriteFailures ? (
        <View className="bg-amber-50 px-4 py-2">
          <Text className="text-center text-xs text-amber-800">
            Some changes haven’t synced yet — will retry.
          </Text>
        </View>
      ) : null}
      <FlatList
        data={recipes}
        keyExtractor={(item) => item.localId}
        renderItem={({ item }) => (
          <RecipeRow
            recipe={item}
            onPress={() =>
              navigation.navigate('RecipeDetail', { localId: item.localId, name: item.name })
            }
            onLongPress={() => confirmDelete(item)}
          />
        )}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
        ListEmptyComponent={
          <CenteredMessage>
            <Text className="text-center text-base text-gray-500">
              No recipes yet. Pull down to sync.
            </Text>
          </CenteredMessage>
        }
        contentContainerStyle={recipes.length === 0 ? { flex: 1 } : undefined}
      />
      <Modal visible={importVisible} transparent animationType="fade" onRequestClose={closeImport}>
        <KeyboardAvoidingView
          className="flex-1 justify-center bg-black/40 px-6"
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <View className="rounded-2xl bg-white p-5">
            <Text className="text-lg font-semibold text-gray-900">Import from URL</Text>
            <Text className="mt-1 text-sm text-gray-500">
              Paste a link to a recipe page and we’ll pull out the ingredients and steps.
            </Text>
            <TextInput
              value={importUrl}
              onChangeText={(t) => {
                setImportUrl(t);
                if (importError) setImportError(null);
              }}
              placeholder="https://…"
              placeholderTextColor="#9ca3af"
              autoCapitalize="none"
              autoCorrect={false}
              keyboardType="url"
              editable={!importing}
              onSubmitEditing={() => void runImport()}
              className="mt-4 rounded-lg border border-gray-300 px-3 py-3 text-base text-gray-900"
            />
            {importError ? <Text className="mt-2 text-sm text-red-600">{importError}</Text> : null}
            <View className="mt-5 flex-row justify-end">
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Cancel import"
                disabled={importing}
                onPress={closeImport}
                className="mr-6 active:opacity-60"
              >
                <Text className={importing ? 'text-base text-gray-300' : 'text-base text-gray-500'}>Cancel</Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Fetch recipe"
                disabled={importing || importUrl.trim().length === 0}
                onPress={() => void runImport()}
                className="flex-row items-center active:opacity-60"
              >
                {importing ? <ActivityIndicator size="small" color="#2563eb" style={{ marginRight: 6 }} /> : null}
                <Text
                  className={
                    importing || importUrl.trim().length === 0
                      ? 'text-base text-gray-400'
                      : 'text-base font-semibold text-blue-600'
                  }
                >
                  {importing ? 'Fetching…' : 'Import'}
                </Text>
              </Pressable>
            </View>
          </View>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}
