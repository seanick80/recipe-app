import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import * as Application from 'expo-application';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { useSync } from '../contexts/SyncContext';
import type { SettingsStackParamList } from '../navigation/SettingsStack';
import { colors } from '../theme/tokens';

/** `Version 1.0.0 (build 102)` — build number is the CI-stamped CFBundleVersion. */
function appVersionLabel(): string {
  const version = Application.nativeApplicationVersion ?? '—';
  const build = Application.nativeBuildVersion ?? '—';
  return `Version ${version} (build ${build})`;
}

/** Local-time display of the last-synced ISO timestamp (rule: view formats UTC → local). */
function formatSynced(iso: string | null): string {
  if (!iso) return 'Never';
  const d = new Date(iso);
  return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <View className="mt-6">
      <Text className="mb-2 px-4 text-xs font-semibold uppercase tracking-wide text-app-text-muted">{title}</Text>
      <View className="border-y border-app-border-subtle bg-app-surface">{children}</View>
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
    <View className="flex-row items-center justify-between border-b border-app-border-subtle px-4 py-3">
      <View className="flex-row items-center">
        {icon ? <Ionicons name={icon} size={18} color={destructive ? colors.danger : colors.textSecondary} style={{ marginRight: 8 }} /> : null}
        <Text className={destructive ? 'text-base text-app-danger' : 'text-base text-app-text-primary'}>{label}</Text>
      </View>
      {value !== undefined ? <Text className="text-base text-app-text-muted">{value}</Text> : null}
      {onPress && value === undefined && !destructive ? (
        <Ionicons name="chevron-forward" size={18} color={colors.textDisabled} />
      ) : null}
    </View>
  );
  return onPress ? (
    <Pressable accessibilityRole="button" onPress={onPress} className="active:bg-app-background">
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
  const navigation = useNavigation<NativeStackNavigationProp<SettingsStackParamList>>();
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
    <ScrollView className="flex-1 bg-app-background" contentContainerStyle={{ paddingBottom: 32 }}>
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
              <Text className="text-sm text-app-danger">{error}</Text>
            </View>
          ) : hasWriteFailures ? (
            <View className="px-4 py-2">
              <Text className="text-sm text-app-warning-text-soft">Some changes haven’t synced — will retry.</Text>
            </View>
          ) : lastResult ? (
            <View className="px-4 py-2">
              <Text className="text-xs text-app-text-muted">
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
                className="flex-row items-center justify-between border-b border-app-border-subtle px-4 py-3"
              >
                <Text className="flex-1 text-base text-app-text-secondary-strong" numberOfLines={1}>
                  {r.name || 'Untitled'}
                </Text>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel={`Restore ${r.name}`}
                  onPress={() => void restoreRecipe(r.localId)}
                  className="ml-3 flex-row items-center active:opacity-60"
                >
                  <Ionicons name="arrow-undo-outline" size={18} color={colors.primary} />
                  <Text className="ml-1 text-sm font-semibold text-app-primary">Restore</Text>
                </Pressable>
              </View>
            ))
          )}
        </Section>
      ) : null}

      <Section title="About">
        <Row label="Version" value={appVersionLabel()} />
        <Row label="App logs" icon="document-text-outline" onPress={() => navigation.navigate('Logs')} />
      </Section>
    </ScrollView>
  );
}
