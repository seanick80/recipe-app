/**
 * GrocerySyncService — the correctness proof for grocery/shopping/template sync.
 * Exercises first-sync, pull-new, push-create (list + items), push-update, the
 * per-item reconcile (create/patch/toggle/delete), server-deletion detection,
 * local-delete push, write-failure retention, template round-trips, purge, and
 * forceFullSync — headlessly, with an in-memory repo + a fake server (mirroring
 * `sync/syncService.test.ts`).
 */
import { ApiError } from '../lib/apiClient';
import { GrocerySyncService, serverToLocalList, toTemplateInput } from './grocerySyncService';
import { MemoryGroceryRepo } from './memoryGroceryRepo';
import type {
  GroceryItem,
  GroceryItemDto,
  GroceryItemInput,
  GroceryItemPatch,
  GroceryList,
  GroceryListDto,
  GrocerySyncApi,
  GrocerySyncEnv,
  GrocerySyncListItem,
  ShoppingTemplate,
  TemplateDto,
  TemplateInput,
} from './types';

const OLD = '2026-01-01T00:00:00.000Z';
const NEW = '2026-06-01T00:00:00.000Z';
const SERVER_NOW = '2026-07-10T11:59:00.000Z';
const FIXED_NOW = new Date('2026-07-10T12:00:00.000Z');

function makeEnv(): GrocerySyncEnv {
  let n = 0;
  return { now: () => FIXED_NOW, newId: () => `new-${(n += 1)}` };
}

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

// --- builders ---------------------------------------------------------------

function serverItem(over: Partial<GroceryItemDto> = {}): GroceryItemDto {
  return {
    id: 'item',
    name: '',
    quantity: 1,
    unit: '',
    category: 'Other',
    is_checked: false,
    source_recipe_name: '',
    source_recipe_id: '',
    updated_at: OLD,
    ...over,
  };
}

function serverList(over: Partial<GroceryListDto> = {}): GroceryListDto {
  return {
    id: 'srv',
    name: '',
    items: [],
    created_at: OLD,
    updated_at: OLD,
    archived_at: null,
    ...over,
  };
}

function localItem(over: Partial<GroceryItem> = {}): GroceryItem {
  return {
    id: 'li',
    name: '',
    quantity: 1,
    unit: '',
    category: 'Other',
    isChecked: false,
    sourceRecipeName: '',
    sourceRecipeId: '',
    serverId: null,
    ...over,
  };
}

function localList(over: Partial<GroceryList> = {}): GroceryList {
  return {
    id: 'loc',
    name: '',
    createdAt: OLD,
    updatedAt: OLD,
    archivedAt: null,
    items: [],
    serverId: null,
    needsSync: false,
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    ...over,
  };
}

function serverTemplate(over: Partial<TemplateDto> = {}): TemplateDto {
  return {
    id: 'tsrv',
    name: '',
    sort_order: 0,
    items: [],
    created_at: OLD,
    updated_at: OLD,
    ...over,
  };
}

function localTemplate(over: Partial<ShoppingTemplate> = {}): ShoppingTemplate {
  return {
    id: 'tloc',
    name: '',
    sortOrder: 0,
    createdAt: OLD,
    updatedAt: OLD,
    items: [],
    serverId: null,
    needsSync: false,
    lastSyncedAt: null,
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    ...over,
  };
}

/** A fake grocery server: list + template stores with per-item mutation. */
class FakeApi implements GrocerySyncApi {
  lists = new Map<string, GroceryListDto>();
  templates = new Map<string, TemplateDto>();
  private nextList = 1;
  private nextItem = 1;
  private nextTemplate = 1;
  failCreateList = false;
  failCreateTemplate = false;

  constructor(lists: GroceryListDto[] = [], templates: TemplateDto[] = []) {
    for (const l of lists) this.lists.set(l.id, clone(l));
    for (const t of templates) this.templates.set(t.id, clone(t));
  }

  private findItem(itemId: string): { list: GroceryListDto; item: GroceryItemDto } | null {
    for (const list of this.lists.values()) {
      const item = list.items.find((i) => i.id === itemId);
      if (item) return { list, item };
    }
    return null;
  }

  listGroceryListIds = jest.fn(async (): Promise<GrocerySyncListItem[]> =>
    [...this.lists.values()].map((l) => ({ id: l.id, updated_at: l.updated_at })),
  );
  getGroceryList = jest.fn(async (id: string): Promise<GroceryListDto> => {
    const l = this.lists.get(id);
    if (!l) throw new ApiError('notFound', 404, 'gone');
    return clone(l);
  });
  createGroceryList = jest.fn(async (name: string): Promise<GroceryListDto> => {
    if (this.failCreateList) throw new ApiError('network', 0, 'boom');
    const id = `srv-${this.nextList++}`;
    const dto = serverList({ id, name, created_at: SERVER_NOW, updated_at: SERVER_NOW });
    this.lists.set(id, dto);
    return clone(dto);
  });
  deleteGroceryList = jest.fn(async (id: string): Promise<void> => {
    if (!this.lists.has(id)) throw new ApiError('notFound', 404, 'gone');
    this.lists.delete(id);
  });
  archiveGroceryList = jest.fn(async (id: string): Promise<GroceryListDto> => {
    const l = this.lists.get(id)!;
    l.archived_at = SERVER_NOW;
    l.updated_at = SERVER_NOW;
    return clone(l);
  });
  restoreGroceryList = jest.fn(async (id: string): Promise<GroceryListDto> => {
    const l = this.lists.get(id)!;
    l.archived_at = null;
    l.updated_at = SERVER_NOW;
    return clone(l);
  });
  createItem = jest.fn(async (listId: string, input: GroceryItemInput): Promise<GroceryItemDto> => {
    const list = this.lists.get(listId)!;
    const item = serverItem({ id: `item-${this.nextItem++}`, ...input, updated_at: SERVER_NOW });
    list.items.push(item);
    list.updated_at = SERVER_NOW;
    return clone(item);
  });
  toggleItem = jest.fn(async (itemId: string): Promise<GroceryItemDto> => {
    const found = this.findItem(itemId)!;
    found.item.is_checked = !found.item.is_checked;
    found.item.updated_at = SERVER_NOW;
    found.list.updated_at = SERVER_NOW;
    return clone(found.item);
  });
  patchItem = jest.fn(async (itemId: string, patch: GroceryItemPatch): Promise<GroceryItemDto> => {
    const found = this.findItem(itemId)!;
    Object.assign(found.item, patch);
    found.item.updated_at = SERVER_NOW;
    found.list.updated_at = SERVER_NOW;
    return clone(found.item);
  });
  deleteItem = jest.fn(async (itemId: string): Promise<void> => {
    const found = this.findItem(itemId)!;
    found.list.items = found.list.items.filter((i) => i.id !== itemId);
    found.list.updated_at = SERVER_NOW;
  });

  listTemplateIds = jest.fn(async (): Promise<GrocerySyncListItem[]> =>
    [...this.templates.values()].map((t) => ({ id: t.id, updated_at: t.updated_at })),
  );
  getTemplate = jest.fn(async (id: string): Promise<TemplateDto> => {
    const t = this.templates.get(id);
    if (!t) throw new ApiError('notFound', 404, 'gone');
    return clone(t);
  });
  createTemplate = jest.fn(async (input: TemplateInput): Promise<TemplateDto> => {
    if (this.failCreateTemplate) throw new ApiError('network', 0, 'boom');
    const id = `tpl-${this.nextTemplate++}`;
    const dto = serverTemplate({
      id,
      name: input.name,
      sort_order: input.sort_order,
      items: input.items.map((it, i) => ({ id: `titem-${i}`, ...it, updated_at: SERVER_NOW })),
      created_at: SERVER_NOW,
      updated_at: SERVER_NOW,
    });
    this.templates.set(id, dto);
    return clone(dto);
  });
  updateTemplate = jest.fn(async (id: string, input: TemplateInput): Promise<TemplateDto> => {
    const dto = serverTemplate({
      id,
      name: input.name,
      sort_order: input.sort_order,
      items: input.items.map((it, i) => ({ id: `titem-${i}`, ...it, updated_at: SERVER_NOW })),
      created_at: this.templates.get(id)?.created_at ?? OLD,
      updated_at: SERVER_NOW,
    });
    this.templates.set(id, dto);
    return clone(dto);
  });
  deleteTemplate = jest.fn(async (id: string): Promise<void> => {
    if (!this.templates.has(id)) throw new ApiError('notFound', 404, 'gone');
    this.templates.delete(id);
  });
}

function makeService(
  seed: { lists?: GroceryList[]; templates?: ShoppingTemplate[] },
  api: FakeApi,
) {
  const repo = new MemoryGroceryRepo(seed);
  const service = new GrocerySyncService({ repo, api, env: makeEnv() });
  return { repo, service };
}

describe('GrocerySyncService — lists', () => {
  it('first sync: bulk-creates a local list + its items when the server is empty', async () => {
    const api = new FakeApi();
    const list = localList({
      id: 'L',
      name: 'Groceries',
      needsSync: true,
      items: [localItem({ id: 'i1', name: 'Milk' }), localItem({ id: 'i2', name: 'Eggs' })],
    });
    const { repo, service } = makeService({ lists: [list] }, api);

    const result = await service.sync();

    expect(api.createGroceryList).toHaveBeenCalledTimes(1);
    expect(api.createItem).toHaveBeenCalledTimes(2);
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllLists())[0];
    expect(saved.serverId).toBe('srv-1');
    expect(saved.needsSync).toBe(false);
    expect(saved.lastSyncedAt).toBe(SERVER_NOW);
    expect(saved.items.every((i) => i.serverId?.startsWith('item-'))).toBe(true);
  });

  it('pull-new: downloads a server-only list', async () => {
    const api = new FakeApi([
      serverList({ id: 'srv-B', name: 'FromWeb', items: [serverItem({ id: 'x', name: 'Bread' })] }),
    ]);
    const { repo, service } = makeService({}, api);

    const result = await service.sync();

    expect(result.pulledNew).toBe(1);
    const all = await repo.getAllLists();
    expect(all).toHaveLength(1);
    expect(all[0].serverId).toBe('srv-B');
    expect(all[0].name).toBe('FromWeb');
    expect(all[0].items[0].name).toBe('Bread');
    expect(all[0].items[0].serverId).toBe('x');
    expect(all[0].lastSyncedAt).toBe(OLD);
  });

  it('push-create: a new local list (with an anchor present so it is not first-sync)', async () => {
    const api = new FakeApi([serverList({ id: 'srv-A' })]);
    const anchor = localList({ id: 'A', serverId: 'srv-A', lastSyncedAt: OLD });
    const fresh = localList({
      id: 'N',
      name: 'New',
      needsSync: true,
      items: [localItem({ id: 'n1', name: 'Rice' })],
    });
    const { repo, service } = makeService({ lists: [anchor, fresh] }, api);

    const result = await service.sync();

    expect(api.createGroceryList).toHaveBeenCalledWith('New');
    expect(api.createItem).toHaveBeenCalledTimes(1);
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllLists()).find((l) => l.id === 'N')!;
    expect(saved.serverId).toBe('srv-1');
    expect(saved.needsSync).toBe(false);
  });

  it('per-item reconcile: creates new, patches changed, toggles, deletes removed', async () => {
    const api = new FakeApi([
      serverList({
        id: 'srv-L',
        updated_at: OLD,
        items: [
          serverItem({ id: 'ia', name: 'Apple', quantity: 1 }),
          serverItem({ id: 'ib', name: 'Banana', is_checked: false }),
          serverItem({ id: 'ic', name: 'Carrot' }),
        ],
      }),
    ]);
    const local = localList({
      id: 'L',
      serverId: 'srv-L',
      lastSyncedAt: OLD,
      needsSync: true,
      items: [
        localItem({ id: 'la', serverId: 'ia', name: 'Apple', quantity: 2 }), // content change → patch
        localItem({ id: 'lb', serverId: 'ib', name: 'Banana', isChecked: true }), // only checkbox → toggle
        localItem({ id: 'ld', serverId: null, name: 'Date' }), // new → create
        // Carrot (ic) has no local item → delete
      ],
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    expect(api.patchItem).toHaveBeenCalledWith('ia', expect.objectContaining({ quantity: 2 }));
    expect(api.toggleItem).toHaveBeenCalledWith('ib');
    expect(api.createItem).toHaveBeenCalledWith('srv-L', expect.objectContaining({ name: 'Date' }));
    expect(api.deleteItem).toHaveBeenCalledWith('ic');
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllLists())[0];
    expect(saved.items.find((i) => i.name === 'Date')!.serverId).toBe('item-1');
    expect(saved.needsSync).toBe(false);
  });

  it('push-update: server not newer → reconcile runs (adds the new item only)', async () => {
    const api = new FakeApi([
      serverList({ id: 'srv-L', updated_at: OLD, items: [serverItem({ id: 'ia', name: 'Apple' })] }),
    ]);
    const local = localList({
      id: 'L',
      serverId: 'srv-L',
      lastSyncedAt: OLD,
      needsSync: true,
      items: [
        localItem({ id: 'la', serverId: 'ia', name: 'Apple' }),
        localItem({ id: 'lb', serverId: null, name: 'Pear' }),
      ],
    });
    const { service } = makeService({ lists: [local] }, api);

    await service.sync();

    expect(api.createItem).toHaveBeenCalledTimes(1);
    expect(api.patchItem).not.toHaveBeenCalled();
    expect(api.toggleItem).not.toHaveBeenCalled();
    expect(api.deleteItem).not.toHaveBeenCalled();
  });

  it('pull-overwrite: a newer server list overwrites local wholesale (server wins)', async () => {
    const api = new FakeApi([
      serverList({
        id: 'srv-C',
        name: 'ServerWins',
        updated_at: NEW,
        items: [serverItem({ id: 'sc', name: 'Kale' })],
      }),
    ]);
    const local = localList({
      id: 'C',
      serverId: 'srv-C',
      name: 'StaleLocal',
      lastSyncedAt: OLD,
      needsSync: false,
      items: [localItem({ id: 'old', serverId: 'gone', name: 'Old' })],
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    expect(result.pulledUpdated).toBe(1);
    const saved = (await repo.getAllLists())[0];
    expect(saved.name).toBe('ServerWins');
    expect(saved.items.map((i) => i.name)).toEqual(['Kale']);
    expect(saved.lastSyncedAt).toBe(NEW);
  });

  it('local-edit guard: a locally-dirty list survives a newer-server pull and is pushed', async () => {
    // The clobber regression (#28): user checks an item locally (needsSync),
    // and the server reports a NEWER updated_at (a background bump). The pull
    // must NOT overwrite the local list — the local check-off must survive and
    // get pushed up (toggled on the server).
    const api = new FakeApi([
      serverList({
        id: 'srv-L',
        name: 'Server',
        updated_at: NEW, // server is newer than the local watermark…
        items: [serverItem({ id: 'ia', name: 'Milk', is_checked: false })],
      }),
    ]);
    const local = localList({
      id: 'L',
      serverId: 'srv-L',
      name: 'Local',
      lastSyncedAt: OLD, // …but the local list is dirty since OLD
      needsSync: true,
      items: [localItem({ id: 'la', serverId: 'ia', name: 'Milk', isChecked: true })],
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    // Pull did NOT overwrite (no wholesale download of the server version)…
    expect(result.pulledUpdated).toBe(0);
    // …and the local check-off was pushed up via the toggle endpoint.
    expect(api.toggleItem).toHaveBeenCalledWith('ia');
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllLists())[0];
    expect(saved.items).toHaveLength(1);
    expect(saved.items[0].name).toBe('Milk');
    expect(saved.items[0].isChecked).toBe(true); // survived — not clobbered
    expect(saved.needsSync).toBe(false); // reconciled clean
    expect(api.lists.get('srv-L')!.items[0].is_checked).toBe(true); // server now checked
  });

  it('server-deletion: a synced list absent from the server list is soft-deleted', async () => {
    const api = new FakeApi(); // empty server list
    const local = localList({ id: 'G', serverId: 'srv-G', lastSyncedAt: OLD });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    expect(result.serverDeleted).toBe(1);
    expect(api.deleteGroceryList).not.toHaveBeenCalled();
    const saved = (await repo.getAllLists())[0];
    expect(saved.locallyDeleted).toBe(true);
    expect(saved.deletedAt).toBe(FIXED_NOW.toISOString());
  });

  it('local-delete: a user-deleted synced list is DELETEd + removed', async () => {
    const api = new FakeApi([serverList({ id: 'srv-E' })]);
    const local = localList({
      id: 'E',
      serverId: 'srv-E',
      lastSyncedAt: OLD,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    expect(api.deleteGroceryList).toHaveBeenCalledWith('srv-E');
    expect(result.localDeletesPushed).toBe(1);
    expect(await repo.getAllLists()).toHaveLength(0);
  });

  it('local-delete of a never-synced list: dropped, no server call', async () => {
    const api = new FakeApi();
    const local = localList({ id: 'F', serverId: null, locallyDeleted: true, pendingRemoteDelete: true });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.sync();

    expect(api.deleteGroceryList).not.toHaveBeenCalled();
    expect(result.localDeletesPushed).toBe(1);
    expect(await repo.getAllLists()).toHaveLength(0);
  });

  it('write failure: create fails → list stays dirty and unsynced', async () => {
    const api = new FakeApi([serverList({ id: 'srv-A' })]);
    api.failCreateList = true;
    const anchor = localList({ id: 'A', serverId: 'srv-A', lastSyncedAt: OLD });
    const fresh = localList({ id: 'N', name: 'New', needsSync: true });
    const { repo, service } = makeService({ lists: [anchor, fresh] }, api);

    const result = await service.sync();

    expect(result.writeFailures).toBe(1);
    expect(result.pushed).toBe(0);
    const saved = (await repo.getAllLists()).find((l) => l.id === 'N')!;
    expect(saved.needsSync).toBe(true);
    expect(saved.serverId).toBeNull();
  });

  it('sync-clobber (#18): a check landed DURING push survives + stays dirty', async () => {
    // The core sync-clobber bug: push snapshots the list, does slow network I/O,
    // then the user checks an item before the push finishes. The old code wrote
    // the stale snapshot back with needsSync=false, reverting the check AND
    // stranding it. The CAS write-back must keep the newer local edit + dirty flag.
    const api = new FakeApi([
      serverList({ id: 'srv-L', updated_at: OLD, items: [serverItem({ id: 'ia', name: 'Milk', is_checked: false })] }),
    ]);
    const local = localList({
      id: 'L',
      serverId: 'srv-L',
      lastSyncedAt: OLD,
      needsSync: true,
      updatedAt: NEW, // the mtime the push is snapshotting FROM
      items: [localItem({ id: 'la', serverId: 'ia', name: 'Milk', isChecked: false })],
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    // pushOneList reads the list twice: once for the reconcile, once for the
    // final watermark. Hook the SECOND read (network still "in flight") to write
    // a newer local version — simulating the user checking the item mid-push.
    const realGet = api.getGroceryList.getMockImplementation()!;
    let calls = 0;
    api.getGroceryList = jest.fn(async (id: string) => {
      const dto = await realGet(id);
      if ((calls += 1) === 2) {
        const cur = (await repo.getAllLists()).find((l) => l.id === 'L')!;
        await repo.updateList({
          ...cur,
          items: cur.items.map((i) => (i.id === 'la' ? { ...i, isChecked: true } : i)),
          updatedAt: SERVER_NOW, // newer than the pushed snapshot (NEW)
          needsSync: true,
        });
      }
      return dto;
    });

    await service.sync();

    const saved = (await repo.getAllLists())[0];
    expect(saved.items[0].isChecked).toBe(true); // survived — not clobbered
    expect(saved.needsSync).toBe(true); // still dirty → re-pushes next cycle
  });

  it('pushLocalChanges: pushes dirty records without any server pull', async () => {
    const api = new FakeApi([serverList({ id: 'srv-A' })]);
    const anchor = localList({ id: 'A', serverId: 'srv-A', lastSyncedAt: OLD }); // clean
    const fresh = localList({
      id: 'N',
      name: 'New',
      needsSync: true,
      items: [localItem({ id: 'n1', name: 'Rice' })],
    });
    const { repo, service } = makeService({ lists: [anchor, fresh] }, api);

    const result = await service.pushLocalChanges();

    expect(api.listGroceryListIds).not.toHaveBeenCalled(); // no pull
    expect(api.getGroceryList).not.toHaveBeenCalledWith('srv-A'); // clean list untouched
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllLists()).find((l) => l.id === 'N')!;
    expect(saved.serverId).toBe('srv-1');
    expect(saved.needsSync).toBe(false);
  });

  it('archive reconcile: a locally-archived synced list is archived on the server', async () => {
    const api = new FakeApi([serverList({ id: 'srv-L', updated_at: OLD, archived_at: null })]);
    const local = localList({
      id: 'L',
      serverId: 'srv-L',
      lastSyncedAt: OLD,
      needsSync: true,
      archivedAt: FIXED_NOW.toISOString(),
    });
    const { service } = makeService({ lists: [local] }, api);

    await service.sync();

    expect(api.archiveGroceryList).toHaveBeenCalledWith('srv-L');
  });
});

describe('GrocerySyncService — templates', () => {
  it('first sync: creates a local template as an aggregate (POST)', async () => {
    const api = new FakeApi();
    const t = localTemplate({
      id: 'T',
      name: 'Weekly Staples',
      needsSync: true,
      items: [{ id: 't1', name: 'Milk', quantity: 1, unit: 'gal', category: 'Dairy', sortOrder: 0 }],
    });
    const { repo, service } = makeService({ templates: [t] }, api);

    const result = await service.sync();

    expect(api.createTemplate).toHaveBeenCalledTimes(1);
    expect(api.createTemplate.mock.calls[0][0].items).toHaveLength(1);
    expect(result.pushed).toBe(1);
    const saved = (await repo.getAllTemplates())[0];
    expect(saved.serverId).toBe('tpl-1');
    expect(saved.needsSync).toBe(false);
  });

  it('push-update: an edited synced template is PUT (full replace)', async () => {
    const api = new FakeApi([], [serverTemplate({ id: 'tsrv-M', updated_at: OLD })]);
    const t = localTemplate({
      id: 'M',
      serverId: 'tsrv-M',
      name: 'Edited',
      lastSyncedAt: OLD,
      needsSync: true,
    });
    const { repo, service } = makeService({ templates: [t] }, api);

    const result = await service.sync();

    expect(api.updateTemplate).toHaveBeenCalledWith('tsrv-M', expect.objectContaining({ name: 'Edited' }));
    expect(result.pushed).toBe(1);
    expect((await repo.getAllTemplates())[0].needsSync).toBe(false);
  });

  it('pull-new: downloads a server-only template', async () => {
    const api = new FakeApi(
      [],
      [serverTemplate({ id: 'tsrv-B', name: 'Downloaded', items: [{ id: 'x', name: 'Salt', quantity: 1, unit: '', category: 'Spices', sort_order: 0, updated_at: OLD }] })],
    );
    const { repo, service } = makeService({}, api);

    const result = await service.sync();

    expect(result.pulledNew).toBe(1);
    const saved = (await repo.getAllTemplates())[0];
    expect(saved.serverId).toBe('tsrv-B');
    expect(saved.items[0].name).toBe('Salt');
  });

  it('server-deletion + local-delete for templates', async () => {
    const api = new FakeApi([], [serverTemplate({ id: 'tsrv-D' })]);
    const gone = localTemplate({ id: 'G', serverId: 'tsrv-absent', lastSyncedAt: OLD });
    const del = localTemplate({
      id: 'D',
      serverId: 'tsrv-D',
      lastSyncedAt: OLD,
      locallyDeleted: true,
      pendingRemoteDelete: true,
    });
    const { repo, service } = makeService({ templates: [gone, del] }, api);

    const result = await service.sync();

    expect(result.serverDeleted).toBe(1); // 'G' not on server → soft-deleted
    expect(api.deleteTemplate).toHaveBeenCalledWith('tsrv-D'); // 'D' pushed as delete
    expect(result.localDeletesPushed).toBe(1);
    const all = await repo.getAllTemplates();
    expect(all.map((t) => t.id)).toEqual(['G']); // D removed; G kept (soft-deleted)
    expect(all[0].locallyDeleted).toBe(true);
  });
});

describe('GrocerySyncService — purge + forceFullSync', () => {
  it('purges soft-deletes older than 30 days, keeps recent ones', async () => {
    const api = new FakeApi([serverList({ id: 'srv-A' })]);
    const anchor = localList({ id: 'A', serverId: 'srv-A', lastSyncedAt: OLD });
    const expired = localList({
      id: 'H',
      serverId: 'srv-H',
      locallyDeleted: true,
      deletedAt: new Date(FIXED_NOW.getTime() - 40 * 86400_000).toISOString(),
    });
    const recent = localList({
      id: 'I',
      serverId: 'srv-I',
      locallyDeleted: true,
      deletedAt: new Date(FIXED_NOW.getTime() - 10 * 86400_000).toISOString(),
    });
    const { repo, service } = makeService({ lists: [anchor, expired, recent] }, api);

    await service.sync();

    const ids = (await repo.getAllLists()).map((l) => l.id);
    expect(ids).not.toContain('H'); // purged
    expect(ids).toContain('I'); // kept
  });

  it('forceFullSync re-downloads an up-to-date list', async () => {
    const api = new FakeApi([
      serverList({ id: 'srv-C', name: 'ServerVersion', updated_at: NEW, items: [serverItem({ id: 'sc', name: 'Server' })] }),
    ]);
    const local = localList({
      id: 'C',
      serverId: 'srv-C',
      name: 'LocalCopy',
      lastSyncedAt: NEW, // already current → normal sync is a no-op
    });
    const { repo, service } = makeService({ lists: [local] }, api);

    const result = await service.forceFullSync();

    expect(result.pulledUpdated).toBe(1);
    expect((await repo.getAllLists())[0].name).toBe('ServerVersion');
  });
});

describe('grocery sync mappers', () => {
  it('serverToLocalList sets the watermark to the server updated_at + keeps item server ids', () => {
    const dto = serverList({ id: 'srv-Z', updated_at: NEW, items: [serverItem({ id: 'iz', name: 'Z' })] });
    const local = serverToLocalList(dto, makeEnv());
    expect(local.serverId).toBe('srv-Z');
    expect(local.lastSyncedAt).toBe(NEW);
    expect(local.needsSync).toBe(false);
    expect(local.items[0].serverId).toBe('iz');
    expect(local.id).toBe('new-1');
  });

  it('toTemplateInput maps camelCase → snake_case + orders items by sortOrder', () => {
    const t = localTemplate({
      name: 'Staples',
      items: [
        { id: 'b', name: 'B', quantity: 1, unit: '', category: 'Other', sortOrder: 2 },
        { id: 'a', name: 'A', quantity: 1, unit: '', category: 'Other', sortOrder: 1 },
      ],
    });
    const input = toTemplateInput(t);
    expect(input.name).toBe('Staples');
    expect(input.items.map((i) => i.name)).toEqual(['A', 'B']);
    expect(input.items[0].sort_order).toBe(1);
  });
});
