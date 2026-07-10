/**
 * In-memory {@link RecipeRepository} for unit tests. Clones on read and write so
 * it behaves like a real serializing store — a mutation is only visible after
 * an explicit `update()`, which catches "forgot to persist" bugs in the sync
 * algorithm that a shared-reference fake would hide.
 */
import type { LocalRecipe, RecipeRepository } from './types';

function clone(r: LocalRecipe): LocalRecipe {
  return JSON.parse(JSON.stringify(r)) as LocalRecipe;
}

export class MemoryRecipeRepo implements RecipeRepository {
  private readonly byLocalId = new Map<string, LocalRecipe>();

  /** Seed the store directly (test setup) without going through sync. */
  constructor(seed: LocalRecipe[] = []) {
    for (const r of seed) this.byLocalId.set(r.localId, clone(r));
  }

  async getAll(): Promise<LocalRecipe[]> {
    return [...this.byLocalId.values()].map(clone);
  }

  async getByLocalId(localId: string): Promise<LocalRecipe | null> {
    const r = this.byLocalId.get(localId);
    return r ? clone(r) : null;
  }

  async getByServerId(serverId: string): Promise<LocalRecipe | null> {
    for (const r of this.byLocalId.values()) {
      if (r.serverId === serverId) return clone(r);
    }
    return null;
  }

  async insert(recipe: LocalRecipe): Promise<void> {
    if (this.byLocalId.has(recipe.localId)) {
      throw new Error(`insert: localId ${recipe.localId} already exists`);
    }
    this.byLocalId.set(recipe.localId, clone(recipe));
  }

  async update(recipe: LocalRecipe): Promise<void> {
    if (!this.byLocalId.has(recipe.localId)) {
      throw new Error(`update: localId ${recipe.localId} not found`);
    }
    this.byLocalId.set(recipe.localId, clone(recipe));
  }

  async remove(localId: string): Promise<void> {
    this.byLocalId.delete(localId);
  }
}
