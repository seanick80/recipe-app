/**
 * In-memory {@link GroceryRepository} for unit tests. Clones on read and write
 * (like {@link import('../sync/memoryRepo').MemoryRecipeRepo}) so a mutation is
 * only visible after an explicit `update*()` — catching "forgot to persist" bugs
 * in the sync algorithm that a shared-reference fake would hide.
 */
import type { GroceryList, GroceryRepository, ShoppingTemplate } from './types';

function clone<T>(v: T): T {
  return JSON.parse(JSON.stringify(v)) as T;
}

export class MemoryGroceryRepo implements GroceryRepository {
  private readonly lists = new Map<string, GroceryList>();
  private readonly templates = new Map<string, ShoppingTemplate>();

  constructor(seed: { lists?: GroceryList[]; templates?: ShoppingTemplate[] } = {}) {
    for (const l of seed.lists ?? []) this.lists.set(l.id, clone(l));
    for (const t of seed.templates ?? []) this.templates.set(t.id, clone(t));
  }

  async getAllLists(): Promise<GroceryList[]> {
    return [...this.lists.values()].map(clone);
  }

  async insertList(list: GroceryList): Promise<void> {
    if (this.lists.has(list.id)) throw new Error(`insertList: id ${list.id} already exists`);
    this.lists.set(list.id, clone(list));
  }

  async updateList(list: GroceryList): Promise<void> {
    if (!this.lists.has(list.id)) throw new Error(`updateList: id ${list.id} not found`);
    this.lists.set(list.id, clone(list));
  }

  async removeList(id: string): Promise<void> {
    this.lists.delete(id);
  }

  async getAllTemplates(): Promise<ShoppingTemplate[]> {
    return [...this.templates.values()].map(clone);
  }

  async insertTemplate(template: ShoppingTemplate): Promise<void> {
    if (this.templates.has(template.id)) {
      throw new Error(`insertTemplate: id ${template.id} already exists`);
    }
    this.templates.set(template.id, clone(template));
  }

  async updateTemplate(template: ShoppingTemplate): Promise<void> {
    if (!this.templates.has(template.id)) {
      throw new Error(`updateTemplate: id ${template.id} not found`);
    }
    this.templates.set(template.id, clone(template));
  }

  async removeTemplate(id: string): Promise<void> {
    this.templates.delete(id);
  }
}
