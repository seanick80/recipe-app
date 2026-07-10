import {
  applyDraft,
  cleanDraft,
  draftToNewLocal,
  emptyDraft,
  isDraftValid,
  localToDraft,
  markDeleted,
  validateDraft,
} from './recipeDraft';
import type { LocalRecipe, RecipeInput, SyncEnv } from './types';

const FIXED_NOW = new Date('2026-07-10T12:00:00.000Z');

function makeEnv(): SyncEnv {
  return { now: () => FIXED_NOW, newId: () => 'new-1' };
}

function localRecipe(over: Partial<LocalRecipe> = {}): LocalRecipe {
  return {
    localId: 'loc',
    serverId: 'srv-1',
    name: 'Soup',
    summary: 's',
    instructions: 'i',
    prep_time_minutes: 5,
    cook_time_minutes: 10,
    servings: 2,
    cuisine: 'Thai',
    course: 'Main',
    tags: 'quick',
    source_url: 'https://x.test',
    difficulty: 'Easy',
    is_favorite: false,
    is_published: false,
    ingredients: [
      { name: 'water', quantity: 2, unit: 'cup', category: 'Other', display_order: 0, notes: '' },
    ],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-02-01T00:00:00.000Z',
    needsSync: false,
    lastSyncedAt: '2026-02-01T00:00:00.000Z',
    locallyDeleted: false,
    pendingRemoteDelete: false,
    deletedAt: null,
    isConflictedCopy: false,
    ...over,
  };
}

describe('recipeDraft helpers', () => {
  it('emptyDraft defaults servings to 1 and everything else blank', () => {
    const d = emptyDraft();
    expect(d.servings).toBe(1);
    expect(d.name).toBe('');
    expect(d.ingredients).toEqual([]);
    expect(d.is_favorite).toBe(false);
  });

  it('localToDraft extracts editable fields and deep-copies ingredients', () => {
    const local = localRecipe();
    const draft = localToDraft(local);
    expect(draft.name).toBe('Soup');
    expect(draft.ingredients).toHaveLength(1);
    expect(draft.ingredients).not.toBe(local.ingredients);
    expect(draft.ingredients[0]).not.toBe(local.ingredients[0]);
    // no sync metadata leaks in
    expect(draft).not.toHaveProperty('localId');
    expect(draft).not.toHaveProperty('needsSync');
  });

  it('validateDraft requires a non-empty name', () => {
    expect(validateDraft(emptyDraft()).name).toBeDefined();
    expect(isDraftValid(emptyDraft())).toBe(false);
    expect(isDraftValid({ ...emptyDraft(), name: 'X' })).toBe(true);
  });

  it('validateDraft rejects an over-long name', () => {
    expect(validateDraft({ ...emptyDraft(), name: 'a'.repeat(501) }).name).toBeDefined();
  });

  it('cleanDraft trims name, drops blank-named ingredients, and renumbers display_order', () => {
    const draft: RecipeInput = {
      ...emptyDraft(),
      name: '  Stew  ',
      ingredients: [
        { name: 'salt', quantity: 1, unit: 'tsp', category: 'Other', display_order: 9, notes: '' },
        { name: '  ', quantity: 0, unit: '', category: 'Other', display_order: 3, notes: '' },
        { name: 'pepper', quantity: 2, unit: 'tsp', category: 'Spices', display_order: 1, notes: '' },
      ],
    };
    const clean = cleanDraft(draft);
    expect(clean.name).toBe('Stew');
    expect(clean.ingredients.map((i) => i.name)).toEqual(['salt', 'pepper']);
    expect(clean.ingredients.map((i) => i.display_order)).toEqual([0, 1]);
    // category preserved (RN keeps it; iOS dropped it)
    expect(clean.ingredients[1].category).toBe('Spices');
  });

  it('draftToNewLocal makes a new unsynced record from a draft', () => {
    const draft = { ...emptyDraft(), name: 'New' };
    const local = draftToNewLocal(draft, makeEnv());
    expect(local.localId).toBe('new-1');
    expect(local.serverId).toBeNull();
    expect(local.needsSync).toBe(true);
    expect(local.lastSyncedAt).toBeNull();
    expect(local.createdAt).toBe(FIXED_NOW.toISOString());
    expect(local.updatedAt).toBe(FIXED_NOW.toISOString());
    expect(local.locallyDeleted).toBe(false);
  });

  it('applyDraft merges content, sets needsSync, preserves identity + createdAt', () => {
    const existing = localRecipe();
    const draft = { ...localToDraft(existing), name: 'Renamed', servings: 6 };
    const updated = applyDraft(existing, draft, FIXED_NOW.toISOString());
    expect(updated.localId).toBe('loc');
    expect(updated.serverId).toBe('srv-1');
    expect(updated.createdAt).toBe('2026-01-01T00:00:00.000Z'); // unchanged
    expect(updated.name).toBe('Renamed');
    expect(updated.servings).toBe(6);
    expect(updated.needsSync).toBe(true);
    expect(updated.updatedAt).toBe(FIXED_NOW.toISOString());
    // lastSyncedAt untouched — the pending push, not this edit, updates it
    expect(updated.lastSyncedAt).toBe('2026-02-01T00:00:00.000Z');
  });

  it('markDeleted flags a user delete queued for a remote DELETE', () => {
    const deleted = markDeleted(localRecipe(), FIXED_NOW.toISOString());
    expect(deleted.locallyDeleted).toBe(true);
    expect(deleted.pendingRemoteDelete).toBe(true);
    expect(deleted.deletedAt).toBe(FIXED_NOW.toISOString());
  });
});
