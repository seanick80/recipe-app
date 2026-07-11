import { Ionicons } from '@expo/vector-icons';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { useSync } from '../contexts/SyncContext';

/** Local-time display of the last-synced ISO timestamp (rule: view formats UTC → local). */
function formatSynced(iso: string | null): string {
  if (!iso) return 'Never';
  const d = new Date(iso);
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View className="mt-6">
      <Text className="mb-2 px-4 text-xs font-semibold uppercase tracking-wide text-gray-400">{title}</Text>
      <View className="border-y border-gray-100 bg-white">{children}</View>
    </View>
  );
}

function Row({
  label,
  value,
  onPress,
  destructive,
  icon,
}: {
  label: string;
  value?: string;
  onPress?: () => void;
  destructive?: boolean;
  icon?: React.ComponentProps<typeof Ionicons>['name'];
}) {
  const body = (
    <View className="flex-row items-center justify-between border-b border-gray-100 px-4 py-3">
      <View className="flex-row items-center">
        {icon ? <Ionicons name={icon} size={18} color={destructive ? '#dc2626' : '#6b7280'} style={{ marginRight: 8 }} /> : null}
        <Text className={destructive ? 'text-base text-red-600' : 'text-base text-gray-900'}>{label}</Text>
      </View>
      {value !== undefined ? <Text className="text-base text-gray-400">{value}</Text> : null}
      {onPress && value === undefined && !destructive ? (
        <Ionicons name="chevron-forward" size={18} color="#d1d5db" />
      ) : null}
    </View>
  );
  return onPress ? (
    <Pressable accessibilityRole="button" onPress={onPress} className="active:bg-gray-50">
      {body}
    </Pressable>
  ) : (
    body
  );
}

/**
 * Settings tab (Phase 4). Surfaces account info + the Phase 3 sync engine that
 * nothing displayed until now: last-synced time, Sync Now, Force Full Sync,
 * and Recently Deleted with restore. Guests get a sign-in prompt instead of the
 * sync sections.
 */
export function SettingsScreen() {
  const { user, isGuest, signIn, signOut } = useAuth();
  const {
    syncing,
    error,
    hasWriteFailures,
    lastSyncedAt,
    lastResult,
    deletedRecipes,
    syncNow,
    forceFullSync,
    restoreRecipe,
  } = useSync();

  const confirmForceSync = () =>
    Alert.alert(
      'Force full sync?',
      'Re-downloads every recipe from the server. Local edits that haven’t synced are kept and re-uploaded.',
      [
        { text: 'Cancel', style: 'cancel' },
        { text: 'Force Sync', onPress: () => void forceFullSync() },
      ],
    );

  return (
    <ScrollView className="flex-1 bg-gray-50" contentContainerStyle={{ paddingBottom: 32 }}>
      <Section title="Account">
        {isGuest ? (
          <>
            <Row label="Browsing without an account" />
            <Row label="Sign in with Google" icon="logo-google" onPress={() => void signIn()} />
          </>
        ) : (
          <>
            <Row label="Name" value={user?.name || '—'} />
            <Row label="Email" value={user?.email || '—'} />
            {user?.role ? <Row label="Role" value={user.role} /> : null}
            <Row label="Sign out" icon="log-out-outline" destructive onPress={() => void signOut()} />
          </>
        )}
      </Section>

      {!isGuest ? (
        <Section title="Sync">
          <Row label="Last synced" value={syncing ? 'Syncing…' : formatSynced(lastSyncedAt)} />
          <Row label="Sync now" icon="sync-outline" onPress={() => void syncNow()} />
          <Row label="Force full sync" icon="cloud-download-outline" onPress={confirmForceSync} />
          {error ? (
            <View className="px-4 py-2">
              <Text className="text-sm text-red-600">{error}</Text>
            </View>
          ) : hasWriteFailures ? (
            <View className="px-4 py-2">
              <Text className="text-sm text-amber-700">Some changes haven’t synced — will retry.</Text>
            </View>
          ) : lastResult ? (
            <View className="px-4 py-2">
              <Text className="text-xs text-gray-400">
                Last sync: {lastResult.pulledNew} new, {lastResult.pulledUpdated} updated,{' '}
                {lastResult.pushed} pushed, {lastResult.conflictsResolved} conflicts.
              </Text>
            </View>
          ) : null}
        </Section>
      ) : null}

      {!isGuest ? (
        <Section title={`Recently Deleted${deletedRecipes.length ? ` (${deletedRecipes.length})` : ''}`}>
          {deletedRecipes.length === 0 ? (
            <Row label="Nothing here" />
          ) : (
            deletedRecipes.map((r) => (
              <View
                key={r.localId}
                className="flex-row items-center justify-between border-b border-gray-100 px-4 py-3"
              >
                <Text className="flex-1 text-base text-gray-700" numberOfLines={1}>
                  {r.name || 'Untitled'}
                </Text>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={`Restore ${r.name}`}
                  onPress={() => void restoreRecipe(r.localId)}
                  className="ml-3 flex-row items-center active:opacity-60"
                >
                  <Ionicons name="arrow-undo-outline" size={18} color="#2563eb" />
                  <Text className="ml-1 text-sm font-semibold text-blue-600">Restore</Text>
                </Pressable>
              </View>
            ))
          )}
        </Section>
      ) : null}
    </ScrollView>
  );
}
