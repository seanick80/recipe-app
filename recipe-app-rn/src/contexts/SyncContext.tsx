import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { AppState, type AppStateStatus } from 'react-native';

import { createSyncApi } from '../api/recipes';
import { getDatabase } from '../db/database';
import { SqliteRecipeRepo } from '../db/sqliteRecipeRepo';
import { ApiError } from '../lib/apiClient';
import { SyncService } from '../sync/syncService';
import type { LocalRecipe, SyncEnv, SyncResult } from '../sync/types';
import { useAuth } from './AuthContext';

/**
 * Owns the offline-first recipe store and drives {@link SyncService}. Recipes
 * are always read from the local SQLite store; the server is reconciled in the
 * background (on auth, on app foreground, on pull-to-refresh), matching the
 * SwiftUI app's "sync on `.active` scene phase + pull-to-refresh" triggers.
 *
 * State is only ever set *after* an `await` inside effects (never synchronously
 * during effect commit) to satisfy React 19's `react-hooks/set-state-in-effect`
 * rule — see the Phase 2 notes in MIGRATION_STATUS.md. User-triggered syncs run
 * from callbacks, where a synchronous `setState` (the spinner) is allowed.
 */
type SyncContextValue = {
  /** Active (non-deleted) recipes, newest first. The single source for the UI. */
  recipes: LocalRecipe[];
  /** True until the first local read completes (show a spinner). */
  initializing: boolean;
  /** True while a sync is in flight. */
  syncing: boolean;
  /** Session-expired / generic sync error (non-fatal; local view stays usable). */
  error: string | null;
  /** True when the last sync left unpushed writes (persistent warning banner). */
  hasWriteFailures: boolean;
  /** Result of the most recent sync, or null before the first. */
  lastResult: SyncResult | null;
  /** Kick off a foreground sync (pull-to-refresh / Sync Now). */
  syncNow: () => Promise<void>;
  /** Look up a single recipe from the in-memory store by local id. */
  getByLocalId: (localId: string) => LocalRecipe | undefined;
};

const SyncContext = createContext<SyncContextValue | undefined>(undefined);

const realEnv: SyncEnv = {
  now: () => new Date(),
  newId: () => newLocalId(),
};

/** UUID v4 for local ids — uses the platform CSPRNG when present, else Math.random. */
function newLocalId(): string {
  const c = (globalThis as { crypto?: { randomUUID?: () => string } }).crypto;
  if (c?.randomUUID) return c.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (ch) => {
    const r = (Math.random() * 16) | 0;
    const v = ch === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function activeSorted(recipes: LocalRecipe[]): LocalRecipe[] {
  return recipes
    .filter((r) => !r.locallyDeleted)
    .sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
}

/** Map a sync throw onto a user-facing, non-fatal message. */
function messageFor(e: unknown): string {
  if (e instanceof ApiError && e.kind === 'unauthorized') {
    return 'Your session expired. Sign in again from Settings.';
  }
  return 'Could not sync recipes — will retry.';
}

export function SyncProvider({ children }: { children: React.ReactNode }) {
  const { token, isGuest } = useAuth();

  const [recipes, setRecipes] = useState<LocalRecipe[]>([]);
  const [initializing, setInitializing] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasWriteFailures, setHasWriteFailures] = useState(false);
  const [lastResult, setLastResult] = useState<SyncResult | null>(null);

  const repoRef = useRef<SqliteRecipeRepo | null>(null);
  const serviceRef = useRef<SyncService | null>(null);
  const inFlight = useRef(false);

  /** Run one sync, fold the outcome into state. Guards against overlap. */
  const runSync = useCallback(async () => {
    const service = serviceRef.current;
    const repo = repoRef.current;
    if (!service || !repo || inFlight.current) return;
    inFlight.current = true;
    try {
      const result = await service.sync();
      setLastResult(result);
      setHasWriteFailures(result.writeFailures > 0);
      setError(null);
      setRecipes(activeSorted(await repo.getAll()));
    } catch (e) {
      setError(messageFor(e));
      // keep whatever local recipes we already have
    } finally {
      inFlight.current = false;
    }
  }, []);

  // (Re)initialize the store + service whenever the token changes. All setState
  // happens after an await, never synchronously during effect commit.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!repoRef.current) {
        repoRef.current = new SqliteRecipeRepo(await getDatabase());
      }
      const repo = repoRef.current;
      const initial = activeSorted(await repo.getAll());
      if (cancelled) return;
      setRecipes(initial);
      setInitializing(false);

      if (token) {
        serviceRef.current = new SyncService({ repo, api: createSyncApi(token), env: realEnv });
        setSyncing(true);
        await runSync();
        if (cancelled) return;
        setSyncing(false);
      } else {
        serviceRef.current = null;
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [token, runSync]);

  // Sync when the app returns to the foreground (if signed in).
  useEffect(() => {
    const onChange = (state: AppStateStatus) => {
      if (state === 'active' && serviceRef.current) {
        setSyncing(true);
        void runSync().finally(() => setSyncing(false));
      }
    };
    const sub = AppState.addEventListener('change', onChange);
    return () => sub.remove();
  }, [runSync]);

  const syncNow = useCallback(async () => {
    if (!serviceRef.current) return;
    setSyncing(true);
    await runSync();
    setSyncing(false);
  }, [runSync]);

  const getByLocalId = useCallback(
    (localId: string) => recipes.find((r) => r.localId === localId),
    [recipes],
  );

  const value: SyncContextValue = {
    recipes: isGuest ? [] : recipes,
    initializing,
    syncing,
    error,
    hasWriteFailures,
    lastResult,
    syncNow,
    getByLocalId,
  };

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncContextValue {
  const ctx = useContext(SyncContext);
  if (!ctx) throw new Error('useSync must be used within a SyncProvider');
  return ctx;
}
