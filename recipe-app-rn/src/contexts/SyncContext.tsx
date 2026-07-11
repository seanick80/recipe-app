import React, { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { AppState, type AppStateStatus } from 'react-native';

import { createSyncApi } from '../api/recipes';
import { getDatabase } from '../db/database';
import { SqliteRecipeRepo } from '../db/sqliteRecipeRepo';
import { ApiError } from '../lib/apiClient';
import { newLocalId } from '../lib/ids';
import { applyDraft, draftToNewLocal, markDeleted } from '../sync/recipeDraft';
import { SyncService } from '../sync/syncService';
import type { LocalRecipe, RecipeInput, SyncEnv, SyncResult } from '../sync/types';
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
  /** Create a new local recipe from a form draft; returns its local id. */
  createRecipe: (draft: RecipeInput) => Promise<string>;
  /** Overwrite an existing recipe's content from a form draft. */
  updateRecipe: (localId: string, draft: RecipeInput) => Promise<void>;
  /** Soft-delete a recipe (queued for a server DELETE on the next sync). */
  deleteRecipe: (localId: string) => Promise<void>;
  /** ISO timestamp of the last successful sync this session, or null. */
  lastSyncedAt: string | null;
  /** Soft-deleted recipes ("Recently Deleted"), most-recently-deleted first. */
  deletedRecipes: LocalRecipe[];
  /** Un-delete a recipe from Recently Deleted (re-queues it for upload). */
  restoreRecipe: (localId: string) => Promise<void>;
  /** Clear every record's watermark and re-download everything from the server. */
  forceFullSync: () => Promise<void>;
};

const SyncContext = createContext<SyncContextValue | undefined>(undefined);

const realEnv: SyncEnv = {
  now: () => new Date(),
  newId: () => newLocalId(),
};

function activeSorted(recipes: LocalRecipe[]): LocalRecipe[] {
  return recipes
    .filter((r) => !r.locallyDeleted)
    .sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
}

function deletedSorted(recipes: LocalRecipe[]): LocalRecipe[] {
  return recipes
    .filter((r) => r.locallyDeleted)
    .sort((a, b) => Date.parse(b.deletedAt ?? '') - Date.parse(a.deletedAt ?? ''));
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
  const [deletedRecipes, setDeletedRecipes] = useState<LocalRecipe[]>([]);
  const [initializing, setInitializing] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hasWriteFailures, setHasWriteFailures] = useState(false);
  const [lastResult, setLastResult] = useState<SyncResult | null>(null);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);

  const repoRef = useRef<SqliteRecipeRepo | null>(null);
  const serviceRef = useRef<SyncService | null>(null);
  const inFlight = useRef(false);

  /** Re-read the local store into both the active + Recently-Deleted lists. */
  const refresh = useCallback(async () => {
    const repo = repoRef.current;
    if (!repo) return;
    const all = await repo.getAll();
    setRecipes(activeSorted(all));
    setDeletedRecipes(deletedSorted(all));
  }, []);

  /** Fold a completed sync's outcome into state (shared by runSync/forceFullSync). */
  const applyResult = useCallback(
    async (result: SyncResult) => {
      setLastResult(result);
      setHasWriteFailures(result.writeFailures > 0);
      setError(null);
      setLastSyncedAt(realEnv.now().toISOString());
      await refresh();
    },
    [refresh],
  );

  /** Run one sync, fold the outcome into state. Guards against overlap. */
  const runSync = useCallback(async () => {
    const service = serviceRef.current;
    if (!service || inFlight.current) return;
    inFlight.current = true;
    try {
      await applyResult(await service.sync());
    } catch (e) {
      setError(messageFor(e));
      // keep whatever local recipes we already have
    } finally {
      inFlight.current = false;
    }
  }, [applyResult]);

  // (Re)initialize the store + service whenever the token changes. All setState
  // happens after an await, never synchronously during effect commit.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (!repoRef.current) {
        repoRef.current = new SqliteRecipeRepo(await getDatabase());
      }
      const repo = repoRef.current;
      await refresh();
      if (cancelled) return;
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
  }, [token, runSync, refresh]);

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

  // Local writes: persist → refresh the list immediately → kick a background
  // sync to push (a no-op for guests / when offline; the record keeps
  // needsSync/pendingRemoteDelete and retries next sync).
  const createRecipe = useCallback(
    async (draft: RecipeInput) => {
      const repo = repoRef.current;
      if (!repo) throw new Error('Store not ready');
      const local = draftToNewLocal(draft, realEnv);
      await repo.insert(local);
      await refresh();
      void syncNow();
      return local.localId;
    },
    [refresh, syncNow],
  );

  const updateRecipe = useCallback(
    async (localId: string, draft: RecipeInput) => {
      const repo = repoRef.current;
      if (!repo) throw new Error('Store not ready');
      const existing = await repo.getByLocalId(localId);
      if (!existing) throw new Error('Recipe not found');
      await repo.update(applyDraft(existing, draft, realEnv.now().toISOString()));
      await refresh();
      void syncNow();
    },
    [refresh, syncNow],
  );

  const deleteRecipe = useCallback(
    async (localId: string) => {
      const repo = repoRef.current;
      if (!repo) throw new Error('Store not ready');
      const existing = await repo.getByLocalId(localId);
      if (!existing) return;
      await repo.update(markDeleted(existing, realEnv.now().toISOString()));
      await refresh();
      void syncNow();
    },
    [refresh, syncNow],
  );

  const restoreRecipe = useCallback(
    async (localId: string) => {
      const repo = repoRef.current;
      if (!repo) throw new Error('Store not ready');
      const existing = await repo.getByLocalId(localId);
      if (!existing) return;
      // Un-delete and re-queue for upload. If the delete was already pushed to
      // the server, the next sync re-pushes it (a PUT may 404 if the server row
      // was hard-purged — the local copy is preserved regardless).
      await repo.update({
        ...existing,
        locallyDeleted: false,
        pendingRemoteDelete: false,
        deletedAt: null,
        needsSync: true,
        updatedAt: realEnv.now().toISOString(),
      });
      await refresh();
      void syncNow();
    },
    [refresh, syncNow],
  );

  const forceFullSync = useCallback(async () => {
    const service = serviceRef.current;
    if (!service || inFlight.current) return;
    inFlight.current = true;
    setSyncing(true);
    try {
      await applyResult(await service.forceFullSync());
    } catch (e) {
      setError(messageFor(e));
    } finally {
      inFlight.current = false;
      setSyncing(false);
    }
  }, [applyResult]);

  const value: SyncContextValue = {
    recipes: isGuest ? [] : recipes,
    initializing,
    syncing,
    error,
    hasWriteFailures,
    lastResult,
    syncNow,
    getByLocalId,
    createRecipe,
    updateRecipe,
    deleteRecipe,
    lastSyncedAt,
    deletedRecipes: isGuest ? [] : deletedRecipes,
    restoreRecipe,
    forceFullSync,
  };

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncContextValue {
  const ctx = useContext(SyncContext);
  if (!ctx) throw new Error('useSync must be used within a SyncProvider');
  return ctx;
}
