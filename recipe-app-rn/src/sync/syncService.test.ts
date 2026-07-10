/**
 * SyncService — the P0 correctness proof for the Phase 3 spike. Exercises all 9
 * sync scenarios from `docs/sync-execution-plan.md` headlessly with an in-memory
 * repo + a fake server, plus the mappers, first-sync, purge, and forceFullSync.
 */
import { ApiError } from '../lib/apiClient';
import type { Recipe } from '../types/recipe';
import { MemoryRecipeRepo } from './memoryRepo';
import {
  conflictCopy,
  formatConflictDate,
  localToInput,
  serverToLocal,
  SyncService,
} from './syncService';
import type { LocalRecipe, RecipeInput, RecipeListItem, SyncApi, SyncEnv } from './types';

const OLD = '2026-01-01T00:00:00.000Z';
const NEW = '2026-06-01T00:00:00.000Z';
const SERVER_NOW = '2026-07-10T11:59:00.000Z';
const FIXED_NOW = new Date('2026-07-10T12:00:00.000Z');

function makeEnv(): SyncEnv {
  let n = 0;
  return { now: () => FIXED_NOW, newId: () => `new-${(n += 1)}` };
}

function serverRecipe(over: Partial<Recipe> = {}): Recipe {
  return {
    id: 'srv',
    name: '',
    summary: '',
    instructions: '',
    prep_time_minutes: 0,
    cook_time_minutes: 0,
    servings: 1,
    cuisine: '',
    course: '',
    tags: '',
    source_url: '',
    difficulty: '',
    is_favorite: false,
    is_published: false,
    ingredients: [],
    created_at: OLD,
    updated_at: OLD,
    deleted_at: null,
    ...over,
  };
}

function localRecipe(over: Partial<LocalRecipe> = {}): LocalRecipe {
  return {
    localId: 'loc',
    serverId: null,
    name: '',
    summary: '',
    instructions: '',
    prep_time_minutes: 0,
    cook_time_minutes: 0,
    servings: 1,
    cuisine: '',
    course: '',
    tags: '',
    source_url: '',
    difficulty: '',
    is_favorite: false,
    is_published: false,
    ingredients: [],
    createdAt: OLD,
    updatedAt: OLD,
    needsSync: false,
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    isConflictedCopy: false,
    ...over,
  };
}

/** The server assigns ids to ingredients on write — model that for the store. */
function toStored(input: RecipeInput): Partial<Recipe> {
  return {
    ...input,
    ingredients: input.ingredients.map((ing, i) => ({ ...ing, id: `ing-${i}` })),
  };
}

/** A fake server: a lightweight list + a full-recipe store, with fault injection. */
class FakeApi implements SyncApi {
  list: RecipeListItem[];
  store: Map<string, Recipe>;
  private nextId = 1;
  failCreate = false;
  failUpdate = false;
  deleteError: 'network' | 'notFound' | null = null;
  getErrorIds = new Set<string>();

  listRecipeIds = jest.fn(async (): Promise<RecipeListItem[]> => [...this.list]);
  getRecipe = jest.fn(async (id: string): Promise<Recipe> => {
    if (this.getErrorIds.has(id)) throw new ApiError('network', 0, 'boom');
    const r = this.store.get(id);
    if (!r) throw new ApiError('notFound', 404, 'gone');
    return r;
  });
  createRecipe = jest.fn(async (input: RecipeInput): Promise<Recipe> => {
    if (this.failCreate) throw new ApiError('network', 0, 'boom');
    const id = `srv-${this.nextId++}`;
    const r = serverRecipe({ ...toStored(input), id, created_at: SERVER_NOW, updated_at: SERVER_NOW });
    this.store.set(id, r);
    this.list.push({ id, updated_at: SERVER_NOW });
    return r;
  });
  updateRecipe = jest.fn(async (id: string, input: RecipeInput): Promise<Recipe> => {
    if (this.failUpdate) throw new ApiError('network', 0, 'boom');
    const existing = this.store.get(id);
    const r = serverRecipe({
      ...toStored(input),
      id,
      created_at: existing?.created_at ?? OLD,
      updated_at: SERVER_NOW,
    });
    this.store.set(id, r);
    return r;
  });
  deleteRecipe = jest.fn(async (id: string): Promise<void> => {
    if (this.deleteError === 'network') throw new ApiError('network', 0, 'boom');
    if (this.deleteError === 'notFound') throw new ApiError('notFound', 404, 'gone');
    this.store.delete(id);
    this.list = this.list.filter((i) => i.id !== id);
  });

  constructor(list: RecipeListItem[] = [], store: Recipe[] = []) {
    this.list = list;
    this.store = new Map(store.map((r) => [r.id, r]));
  }
}

function makeService(seed: LocalRecipe[], api: FakeApi) {
  const repo = new MemoryRecipeRepo(seed);
  const service = new SyncService({ repo, api, env: makeEnv() });
  return { repo, service };
}

describe('SyncService — 9 sync scenarios', () => {
  // An anchor recipe present + current on both sides keeps the server list
  // non-empty (so first-sync doesn't fire) and is a no-op for pull.
  const anchorList: RecipeListItem[] = [{ id: 'srv-A', updated_at: OLD }];
  const anchorStore = [serverRecipe({ id: 'srv-A', updated_at: OLD })];
  const anchorLocal = localRecipe({ localId: 'A', serverId: 'srv-A', lastSyncedAt: OLD });

  it('Scenario 1: uploads a new local recipe (POST)', async () => {
    const api = new FakeApi([...anchorList], [...anchorStore]);
    const fresh = localRecipe({ localId: 'N', name: 'New', needsSync: true });
    const { repo, service } = makeService([anchorLocal, fresh], api);

    const result = await service.sync();

    expect(api.createRecipe).toHaveBeenCalledTimes(1);
    expect(api.createRecipe.mock.calls[0][0].name).toBe('New');
    expect(result.pushed).toBe(1);
    const saved = await repo.getByLocalId('N');
    expect(saved?.serverId).toBe('srv-1');
    expect(saved?.needsSync).toBe(false);
    expect(saved?.lastSyncedAt).toBe(SERVER_NOW);
  });

  it('Scenario 2: uploads an edited local recipe (PUT)', async () => {
    const api = new FakeApi([...anchorList], [...anchorStore]);
    const edited = localRecipe({
      localId: 'M',
      serverId: 'srv-M',
      name: 'Edited',
      needsSync: true,
      lastSyncedAt: OLD,
    });
    api.list.push({ id: 'srv-M', updated_at: OLD });
    api.store.set('srv-M', serverRecipe({ id: 'srv-M', updated_at: OLD }));
    const { repo, service } = makeService([anchorLocal, edited], api);

    const result = await service.sync();

    expect(api.updateRecipe).toHaveBeenCalledWith('srv-M', expect.objectContaining({ name: 'Edited' }));
    expect(result.pushed).toBe(1);
    const saved = await repo.getByLocalId('M');
    expect(saved?.needsSync).toBe(false);
    expect(saved?.lastSyncedAt).toBe(SERVER_NOW);
  });

  it('Scenario 3: downloads a server-only recipe (new local insert)', async () => {
    const api = new FakeApi(
      [{ id: 'srv-B', updated_at: OLD }],
      [serverRecipe({ id: 'srv-B', name: 'FromWeb', updated_at: OLD })],
    );
    const { repo, service } = makeService([], api);

    const result = await service.sync();

    expect(result.pulledNew).toBe(1);
    const all = await repo.getAll();
    expect(all).toHaveLength(1);
    expect(all[0].serverId).toBe('srv-B');
    expect(all[0].name).toBe('FromWeb');
    expect(all[0].needsSync).toBe(false);
    expect(all[0].lastSyncedAt).toBe(OLD); // watermark = server updated_at
  });

  it('Scenario 4: overwrites a local recipe with a newer server version', async () => {
    const api = new FakeApi(
      [{ id: 'srv-C', updated_at: NEW }],
      [serverRecipe({ id: 'srv-C', name: 'ServerWins', updated_at: NEW })],
    );
    const local = localRecipe({
      localId: 'C',
      serverId: 'srv-C',
      name: 'StaleLocal',
      lastSyncedAt: OLD,
      needsSync: false,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.sync();

    expect(result.pulledUpdated).toBe(1);
    const saved = await repo.getByLocalId('C');
    expect(saved?.name).toBe('ServerWins');
    expect(saved?.lastSyncedAt).toBe(NEW);
    expect(saved?.needsSync).toBe(false);
  });

  it('Scenario 5: conflict — keeps a local copy, server wins the original', async () => {
    const api = new FakeApi(
      [{ id: 'srv-D', updated_at: NEW }],
      [serverRecipe({ id: 'srv-D', name: 'ServerEdit', updated_at: NEW })],
    );
    const local = localRecipe({
      localId: 'D',
      serverId: 'srv-D',
      name: 'LocalEdit',
      lastSyncedAt: OLD,
      needsSync: true,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.sync();

    expect(result.conflictsResolved).toBe(1);
    expect(result.pushed).toBe(0); // the conflict copy is NOT pushed this cycle
    const all = await repo.getAll();
    expect(all).toHaveLength(2);

    const original = all.find((r) => r.localId === 'D')!;
    expect(original.name).toBe('ServerEdit');
    expect(original.needsSync).toBe(false);
    expect(original.lastSyncedAt).toBe(NEW);

    const copy = all.find((r) => r.isConflictedCopy)!;
    expect(copy.serverId).toBeNull();
    expect(copy.needsSync).toBe(true);
    expect(copy.name).toBe(`LocalEdit (conflicted copy ${formatConflictDate(FIXED_NOW)})`);
  });

  it('Scenario 6: user-deleted recipe → DELETE pushed + removed locally', async () => {
    const api = new FakeApi(
      [{ id: 'srv-E', updated_at: OLD }],
      [serverRecipe({ id: 'srv-E', updated_at: OLD })],
    );
    const local = localRecipe({
      localId: 'E',
      serverId: 'srv-E',
      lastSyncedAt: OLD,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.sync();

    expect(api.deleteRecipe).toHaveBeenCalledWith('srv-E');
    expect(result.localDeletesPushed).toBe(1);
    expect(await repo.getByLocalId('E')).toBeNull();
  });

  it('Scenario 6b: user-deleted never-synced recipe → dropped, no server call', async () => {
    const api = new FakeApi([], []); // empty server; F is locallyDeleted so no first-sync
    const local = localRecipe({
      localId: 'F',
      serverId: null,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.sync();

    expect(api.deleteRecipe).not.toHaveBeenCalled();
    expect(result.localDeletesPushed).toBe(1);
    expect(await repo.getByLocalId('F')).toBeNull();
  });

  it('Scenario 7: server-deleted recipe → soft-deleted locally, kept in Recently Deleted', async () => {
    const api = new FakeApi([], [serverRecipe({ id: 'srv-G' })]); // G absent from list
    const local = localRecipe({
      localId: 'G',
      serverId: 'srv-G',
      lastSyncedAt: OLD,
      needsSync: false,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.sync();

    expect(result.serverDeleted).toBe(1);
    // Deviation #2: not re-pushed as a DELETE.
    expect(api.deleteRecipe).not.toHaveBeenCalled();
    const saved = await repo.getByLocalId('G');
    expect(saved?.locallyDeleted).toBe(true);
    expect(saved?.deletedAt).toBe(FIXED_NOW.toISOString());
  });

  it('Scenario 8: first sync bulk-uploads all local recipes when server is empty', async () => {
    const api = new FakeApi([], []);
    const seed = [
      localRecipe({ localId: 'a', name: 'A', needsSync: true }),
      localRecipe({ localId: 'b', name: 'B', needsSync: true }),
      localRecipe({ localId: 'c', name: 'C', needsSync: true }),
    ];
    const { repo, service } = makeService(seed, api);

    const result = await service.sync();

    expect(api.createRecipe).toHaveBeenCalledTimes(3);
    expect(result.pushed).toBe(3);
    const all = await repo.getAll();
    expect(all.every((r) => r.serverId !== null && !r.needsSync)).toBe(true);
  });

  it('Scenario 9: write failure keeps the recipe dirty and counts the failure', async () => {
    const api = new FakeApi([...anchorList], [...anchorStore]);
    api.failCreate = true;
    const fresh = localRecipe({ localId: 'N', name: 'New', needsSync: true });
    const { repo, service } = makeService([anchorLocal, fresh], api);

    const result = await service.sync();

    expect(result.writeFailures).toBe(1);
    expect(result.pushed).toBe(0);
    const saved = await repo.getByLocalId('N');
    expect(saved?.needsSync).toBe(true);
    expect(saved?.serverId).toBeNull();
  });
});

describe('SyncService — delete failure handling (Scenario 9 for deletes)', () => {
  const anchorList: RecipeListItem[] = [{ id: 'srv-A', updated_at: OLD }];

  it('network error during DELETE → failure counted, recipe retained', async () => {
    const api = new FakeApi([...anchorList], [serverRecipe({ id: 'srv-A', updated_at: OLD })]);
    api.deleteError = 'network';
    const anchorLocal = localRecipe({ localId: 'A', serverId: 'srv-A', lastSyncedAt: OLD });
    const del = localRecipe({
      localId: 'E',
      serverId: 'srv-E',
      lastSyncedAt: OLD,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    api.list.push({ id: 'srv-E', updated_at: OLD });
    api.store.set('srv-E', serverRecipe({ id: 'srv-E', updated_at: OLD }));
    const { repo, service } = makeService([anchorLocal, del], api);

    const result = await service.sync();

    expect(result.writeFailures).toBe(1);
    expect(result.localDeletesPushed).toBe(0);
    expect((await repo.getByLocalId('E'))?.locallyDeleted).toBe(true);
  });

  it('404 during DELETE → treated as already-gone, removed, not a failure', async () => {
    const api = new FakeApi([...anchorList], [serverRecipe({ id: 'srv-A', updated_at: OLD })]);
    api.deleteError = 'notFound';
    const anchorLocal = localRecipe({ localId: 'A', serverId: 'srv-A', lastSyncedAt: OLD });
    const del = localRecipe({
      localId: 'E',
      serverId: 'srv-E',
      lastSyncedAt: OLD,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    api.list.push({ id: 'srv-E', updated_at: OLD });
    const { repo, service } = makeService([anchorLocal, del], api);

    const result = await service.sync();

    expect(result.writeFailures).toBe(0);
    expect(result.localDeletesPushed).toBe(1);
    expect(await repo.getByLocalId('E')).toBeNull();
  });
});

describe('SyncService — purge, forceFullSync, first-sync guard', () => {
  const anchorList: RecipeListItem[] = [{ id: 'srv-A', updated_at: OLD }];
  const anchorStore = [serverRecipe({ id: 'srv-A', updated_at: OLD })];
  const anchorLocal = localRecipe({ localId: 'A', serverId: 'srv-A', lastSyncedAt: OLD });

  it('purges soft-deletes older than 30 days, keeps recent ones', async () => {
    const api = new FakeApi([...anchorList], [...anchorStore]);
    const fortyDaysAgo = new Date(FIXED_NOW.getTime() - 40 * 86400_000).toISOString();
    const tenDaysAgo = new Date(FIXED_NOW.getTime() - 10 * 86400_000).toISOString();
    const expired = localRecipe({
      localId: 'H',
      serverId: 'srv-H',
      locallyDeleted: true,
      deletedAt: fortyDaysAgo,
    });
    const recent = localRecipe({
      localId: 'I',
      serverId: 'srv-I',
      locallyDeleted: true,
      deletedAt: tenDaysAgo,
    });
    // Server-deleted holdovers (pendingRemoteDelete === false) → never pushed,
    // just aged out by the purge.
    const { repo, service } = makeService([anchorLocal, expired, recent], api);

    await service.sync();

    expect(await repo.getByLocalId('H')).toBeNull(); // purged
    expect(await repo.getByLocalId('I')).not.toBeNull(); // kept
  });

  it('forceFullSync re-downloads even an up-to-date recipe', async () => {
    const api = new FakeApi(
      [{ id: 'srv-C', updated_at: NEW }],
      [serverRecipe({ id: 'srv-C', name: 'ServerVersion', updated_at: NEW })],
    );
    const local = localRecipe({
      localId: 'C',
      serverId: 'srv-C',
      name: 'LocalCopy',
      lastSyncedAt: NEW, // already current → normal sync is a no-op
      needsSync: false,
    });
    const { repo, service } = makeService([local], api);

    const result = await service.forceFullSync();

    expect(result.pulledUpdated).toBe(1);
    expect((await repo.getByLocalId('C'))?.name).toBe('ServerVersion');
  });

  it('does not treat an empty-server sync as first-sync when all locals are synced', async () => {
    const api = new FakeApi([], []); // server empty
    const synced = localRecipe({ localId: 'X', serverId: 'srv-X', lastSyncedAt: OLD });
    const { service } = makeService([synced], api);

    const result = await service.sync();

    // No serverId==null non-deleted local → not first-sync → X is server-deleted.
    expect(api.createRecipe).not.toHaveBeenCalled();
    expect(result.serverDeleted).toBe(1);
  });
});

describe('sync mappers', () => {
  it('localToInput drops id/timestamps and orders ingredients by display_order', () => {
    const local = localRecipe({
      name: 'Soup',
      ingredients: [
        { name: 'salt', quantity: 1, unit: 'tsp', category: 'Other', display_order: 2, notes: '' },
        { name: 'water', quantity: 2, unit: 'cup', category: 'Other', display_order: 1, notes: '' },
      ],
    });
    const input = localToInput(local);
    expect(input.ingredients.map((i) => i.name)).toEqual(['water', 'salt']);
    expect(input).not.toHaveProperty('id');
    expect(input).not.toHaveProperty('created_at');
  });

  it('serverToLocal sets the watermark to the server updated_at', () => {
    const dto = serverRecipe({ id: 'srv-Z', updated_at: NEW });
    const env = makeEnv();
    const local = serverToLocal(dto, env);
    expect(local.serverId).toBe('srv-Z');
    expect(local.lastSyncedAt).toBe(NEW);
    expect(local.needsSync).toBe(false);
    expect(local.localId).toBe('new-1');
  });

  it('conflictCopy is a new unsynced record flagged as a conflict', () => {
    const local = localRecipe({ name: 'Cake', serverId: 'srv-1' });
    const env = makeEnv();
    const copy = conflictCopy(local, env);
    expect(copy.serverId).toBeNull();
    expect(copy.isConflictedCopy).toBe(true);
    expect(copy.needsSync).toBe(true);
    expect(copy.name).toContain('Cake (conflicted copy ');
  });

  it('formatConflictDate renders local YYYY-MM-DD HH:mm', () => {
    expect(formatConflictDate(new Date('2026-07-10T09:05:00'))).toBe('2026-07-10 09:05');
  });
});
