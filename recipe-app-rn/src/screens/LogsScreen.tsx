import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';

import { debugLog, type LogEntry } from '../lib/debugLog';
import { colors } from '../theme/tokens';

/** Local-time display of an ISO timestamp (rule: view formats UTC → local). */
function formatTime(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })}`;
}

/** One-line rendering of an entry's optional details payload. */
function formatDetails(details?: LogEntry['details']): string | null {
  if (!details) return null;
  const parts = Object.keys(details)
    .sort()
    .map((k) => `${k}=${details[k]}`);
  return parts.length ? parts.join('  ') : null;
}

/**
 * Debug logs viewer (Settings → App logs). Renders the durable {@link debugLog}
 * store newest-first with a Clear action and an empty state. Reads via
 * `readPersisted()` so pre-crash entries from earlier launches show up too, and
 * re-reads on focus so entries emitted elsewhere in the app appear on return.
 */
export function LogsScreen() {
  const [entries, setEntries] = useState<LogEntry[]>([]);

  const refresh = useCallback(() => {
    // Durable store, newest first (falls back to the in-memory buffer).
    setEntries(debugLog.readPersisted());
  }, []);

  useFocusEffect(refresh);

  const confirmClear = () =>
    Alert.alert('Clear logs?', 'This removes all debug log entries on this device.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Clear',
        style: 'destructive',
        onPress: () => {
          debugLog.clear();
          refresh();
        },
      },
    ]);

  return (
    <View className="flex-1 bg-app-background">
      <View className="flex-row items-center justify-between border-b border-app-border-subtle bg-app-surface px-4 py-3">
        <Text className="text-sm text-app-text-secondary">
          {entries.length} {entries.length === 1 ? 'entry' : 'entries'}
        </Text>
        <View className="flex-row items-center">
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Refresh logs"
            onPress={refresh}
            className="mr-4 flex-row items-center active:opacity-60"
          >
            <Ionicons name="refresh-outline" size={18} color={colors.primary} />
            <Text className="ml-1 text-sm font-semibold text-app-primary">Refresh</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Clear logs"
            onPress={confirmClear}
            disabled={entries.length === 0}
            className="flex-row items-center active:opacity-60"
          >
            <Ionicons name="trash-outline" size={18} color={entries.length === 0 ? colors.textDisabled : colors.danger} />
            <Text
              className={`ml-1 text-sm font-semibold ${entries.length === 0 ? 'text-app-text-disabled' : 'text-app-danger'}`}
            >
              Clear
            </Text>
          </Pressable>
        </View>
      </View>

      {entries.length === 0 ? (
        <View className="flex-1 items-center justify-center px-8">
          <Ionicons name="document-text-outline" size={40} color={colors.textDisabled} />
          <Text className="mt-3 text-center text-base text-app-text-muted">No logs yet</Text>
          <Text className="mt-1 text-center text-sm text-app-text-muted">
            App activity (sync, sign-in, API errors) will appear here.
          </Text>
        </View>
      ) : (
        <ScrollView className="flex-1" contentContainerStyle={{ paddingBottom: 32 }}>
          {entries.map((entry, index) => {
            const details = formatDetails(entry.details);
            return (
              <View key={`${entry.ts}-${index}`} className="border-b border-app-border-subtle bg-app-surface px-4 py-2">
                <View className="flex-row items-center justify-between">
                  <Text className="text-xs font-semibold uppercase tracking-wide text-app-primary-light">{entry.cat}</Text>
                  <Text className="text-xs text-app-text-muted">{formatTime(entry.ts)}</Text>
                </View>
                <Text className="mt-1 text-sm text-app-text-primary">{entry.msg}</Text>
                {details ? (
                  <Text className="mt-0.5 font-mono text-xs text-app-text-secondary">{details}</Text>
                ) : null}
              </View>
            );
          })}
        </ScrollView>
      )}
    </View>
  );
}
