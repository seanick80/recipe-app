import { Ionicons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';

import { debugLog, type LogEntry } from '../lib/debugLog';

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
 * Debug logs viewer (Settings → App logs). Renders the in-memory {@link debugLog}
 * ring buffer newest-first with a Clear action and an empty state. Re-reads on
 * focus so entries emitted while elsewhere in the app show up on return.
 */
export function LogsScreen() {
  const [entries, setEntries] = useState<LogEntry[]>([]);

  const refresh = useCallback(() => {
    // Newest first (the buffer stores oldest → newest).
    setEntries(debugLog.entries().reverse());
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
    <View className="flex-1 bg-gray-50">
      <View className="flex-row items-center justify-between border-b border-gray-100 bg-white px-4 py-3">
        <Text className="text-sm text-gray-500">
          {entries.length} {entries.length === 1 ? 'entry' : 'entries'}
        </Text>
        <View className="flex-row items-center">
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Refresh logs"
            onPress={refresh}
            className="mr-4 flex-row items-center active:opacity-60"
          >
            <Ionicons name="refresh-outline" size={18} color="#2563eb" />
            <Text className="ml-1 text-sm font-semibold text-blue-600">Refresh</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Clear logs"
            onPress={confirmClear}
            disabled={entries.length === 0}
            className="flex-row items-center active:opacity-60"
          >
            <Ionicons name="trash-outline" size={18} color={entries.length === 0 ? '#d1d5db' : '#dc2626'} />
            <Text
              className={`ml-1 text-sm font-semibold ${entries.length === 0 ? 'text-gray-300' : 'text-red-600'}`}
            >
              Clear
            </Text>
          </Pressable>
        </View>
      </View>

      {entries.length === 0 ? (
        <View className="flex-1 items-center justify-center px-8">
          <Ionicons name="document-text-outline" size={40} color="#d1d5db" />
          <Text className="mt-3 text-center text-base text-gray-400">No logs yet</Text>
          <Text className="mt-1 text-center text-sm text-gray-400">
            App activity (sync, sign-in, API errors) will appear here.
          </Text>
        </View>
      ) : (
        <ScrollView className="flex-1" contentContainerStyle={{ paddingBottom: 32 }}>
          {entries.map((entry, index) => {
            const details = formatDetails(entry.details);
            return (
              <View key={`${entry.ts}-${index}`} className="border-b border-gray-100 bg-white px-4 py-2">
                <View className="flex-row items-center justify-between">
                  <Text className="text-xs font-semibold uppercase tracking-wide text-blue-500">{entry.cat}</Text>
                  <Text className="text-xs text-gray-400">{formatTime(entry.ts)}</Text>
                </View>
                <Text className="mt-1 text-sm text-gray-900">{entry.msg}</Text>
                {details ? (
                  <Text className="mt-0.5 font-mono text-xs text-gray-500">{details}</Text>
                ) : null}
              </View>
            );
          })}
        </ScrollView>
      )}
    </View>
  );
}
