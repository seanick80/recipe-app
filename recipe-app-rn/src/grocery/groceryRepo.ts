/**
 * expo-sqlite–backed store for the Shopping + Grocery domain.
 *
 * Lists and templates are read as aggregates (with their items) and written
 * atomically inside a transaction: the parent row + a wholesale item replace
 * (delete-all + re-insert) — lists are small and the UI/sync layer always hand
 * back the full item array, so this is simpler than per-row diffing (the same
 * strategy the recipe store uses for ingredients).
 *
 * Each row carries the grocery-sync metadata added in schema v3 (server_id +
 * needs_sync + last_synced_at + soft-delete flags on the aggregate roots;
 * server_id on grocery items so the sync layer can target the per-item API).
 * `getAll*` return EVERYTHING including locally-deleted records — the sync
 * algorithm needs them; the UI filters.
 */
import type { SQLiteDatabase } from 'expo-sqlite';

import type {
  GroceryItem,
  GroceryList,
  GroceryRepository,
  ShoppingTemplate,
  TemplateItem,
} from './types';

type ListRow = {
  id: string;
  name: string;
  created_at: string;
  updated_at: string | null;
  archived_at: string | null;
  server_id: string | null;
  needs_sync: number;
  last_synced_at: string | null;
  locally_deleted: number;
  pending_remote_delete: number;
  deleted_at: string | null;
};
type ItemRow = {
  id: string;
  list_id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  is_checked: number;
  source_recipe_name: string;
  source_recipe_id: string;
  server_id: string | null;
};
type TemplateRow = {
  id: string;
  name: string;
  sort_order: number;
  created_at: string;
  updated_at: string | null;
  server_id: string | null;
  needs_sync: number;
  last_synced_at: string | null;
  locally_deleted: number;
  pending_remote_delete: number;
  deleted_at: string | null;
};
type TemplateItemRow = {
  id: string;
  template_id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  sort_order: number;
};

export class SqliteGroceryRepo implements GroceryRepository {
  constructor(private readonly db: SQLiteDatabase) {}

  // --- grocery lists ---

  async getAllLists(): Promise<GroceryList[]> {
    const lists = await this.db.getAllAsync<ListRow>(
      'SELECT * FROM grocery_lists ORDER BY created_at DESC',
    );
    const itemRows = await this.db.getAllAsync<ItemRow>('SELECT * FROM grocery_items');
    const byList = new Map<string, GroceryItem[]>();
    for (const r of itemRows) {
      const list = byList.get(r.list_id) ?? [];
      list.push({
        id: r.id,
        name: r.name,
        quantity: r.quantity,
        unit: r.unit,
        category: r.category,
        isChecked: r.is_checked === 1,
        sourceRecipeName: r.source_recipe_name,
        sourceRecipeId: r.source_recipe_id,
        serverId: r.server_id,
      });
      byList.set(r.list_id, list);
    }
    return lists.map((l) => ({
      id: l.id,
      name: l.name,
      createdAt: l.created_at,
      updatedAt: l.updated_at ?? l.created_at,
      archivedAt: l.archived_at,
      items: byList.get(l.id) ?? [],
      serverId: l.server_id,
      needsSync: l.needs_sync === 1,
      lastSyncedAt: l.last_synced_at,
      locallyDeleted: l.locally_deleted === 1,
      pendingRemoteDelete: l.pending_remote_delete === 1,
      deletedAt: l.deleted_at,
    }));
  }

  async insertList(list: GroceryList): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `INSERT INTO grocery_lists
           (id, name, created_at, updated_at, archived_at, server_id, needs_sync,
            last_synced_at, locally_deleted, pending_remote_delete, deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        listParams(list),
      );
      await this.insertItems(list.id, list.items);
    });
  }

  async updateList(list: GroceryList): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `UPDATE grocery_lists SET
           name = ?, created_at = ?, updated_at = ?, archived_at = ?, server_id = ?,
           needs_sync = ?, last_synced_at = ?, locally_deleted = ?,
           pending_remote_delete = ?, deleted_at = ?
         WHERE id = ?`,
        [...listParams(list).slice(1), list.id],
      );
      await this.db.runAsync('DELETE FROM grocery_items WHERE list_id = ?', [list.id]);
      await this.insertItems(list.id, list.items);
    });
  }

  private async insertItems(listId: string, items: GroceryItem[]): Promise<void> {
    for (const i of items) {
      await this.db.runAsync(
        `INSERT INTO grocery_items
           (id, list_id, name, quantity, unit, category, is_checked,
            source_recipe_name, source_recipe_id, server_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          i.id,
          listId,
          i.name,
          i.quantity,
          i.unit,
          i.category,
          i.isChecked ? 1 : 0,
          i.sourceRecipeName,
          i.sourceRecipeId,
          i.serverId ?? null,
        ],
      );
    }
  }

  async removeList(id: string): Promise<void> {
    // grocery_items cascade via the FK (foreign_keys pragma is enabled on open).
    await this.db.runAsync('DELETE FROM grocery_lists WHERE id = ?', [id]);
  }

  // --- shopping templates ---

  async getAllTemplates(): Promise<ShoppingTemplate[]> {
    const templates = await this.db.getAllAsync<TemplateRow>(
      'SELECT * FROM shopping_templates ORDER BY sort_order ASC',
    );
    const itemRows = await this.db.getAllAsync<TemplateItemRow>(
      'SELECT * FROM template_items ORDER BY sort_order ASC',
    );
    const byTemplate = new Map<string, TemplateItem[]>();
    for (const r of itemRows) {
      const list = byTemplate.get(r.template_id) ?? [];
      list.push({
        id: r.id,
        name: r.name,
        quantity: r.quantity,
        unit: r.unit,
        category: r.category,
        sortOrder: r.sort_order,
      });
      byTemplate.set(r.template_id, list);
    }
    return templates.map((t) => ({
      id: t.id,
      name: t.name,
      sortOrder: t.sort_order,
      createdAt: t.created_at,
      updatedAt: t.updated_at ?? t.created_at,
      items: byTemplate.get(t.id) ?? [],
      serverId: t.server_id,
      needsSync: t.needs_sync === 1,
      lastSyncedAt: t.last_synced_at,
      locallyDeleted: t.locally_deleted === 1,
      pendingRemoteDelete: t.pending_remote_delete === 1,
      deletedAt: t.deleted_at,
    }));
  }

  async insertTemplate(template: ShoppingTemplate): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `INSERT INTO shopping_templates
           (id, name, sort_order, created_at, updated_at, server_id, needs_sync,
            last_synced_at, locally_deleted, pending_remote_delete, deleted_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        templateParams(template),
      );
      await this.insertTemplateItems(template.id, template.items);
    });
  }

  async updateTemplate(template: ShoppingTemplate): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `UPDATE shopping_templates SET
           name = ?, sort_order = ?, created_at = ?, updated_at = ?, server_id = ?,
           needs_sync = ?, last_synced_at = ?, locally_deleted = ?,
           pending_remote_delete = ?, deleted_at = ?
         WHERE id = ?`,
        [...templateParams(template).slice(1), template.id],
      );
      await this.db.runAsync('DELETE FROM template_items WHERE template_id = ?', [template.id]);
      await this.insertTemplateItems(template.id, template.items);
    });
  }

  private async insertTemplateItems(templateId: string, items: TemplateItem[]): Promise<void> {
    for (const i of items) {
      await this.db.runAsync(
        `INSERT INTO template_items (id, template_id, name, quantity, unit, category, sort_order)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [i.id, templateId, i.name, i.quantity, i.unit, i.category, i.sortOrder],
      );
    }
  }

  async removeTemplate(id: string): Promise<void> {
    await this.db.runAsync('DELETE FROM shopping_templates WHERE id = ?', [id]);
  }
}

/** Positional bind values for a grocery_lists INSERT (id first). */
function listParams(l: GroceryList): (string | number | null)[] {
  return [
    l.id,
    l.name,
    l.createdAt,
    l.updatedAt,
    l.archivedAt,
    l.serverId,
    l.needsSync ? 1 : 0,
    l.lastSyncedAt,
    l.locallyDeleted ? 1 : 0,
    l.pendingRemoteDelete ? 1 : 0,
    l.deletedAt,
  ];
}

/** Positional bind values for a shopping_templates INSERT (id first). */
function templateParams(t: ShoppingTemplate): (string | number | null)[] {
  return [
    t.id,
    t.name,
    t.sortOrder,
    t.createdAt,
    t.updatedAt,
    t.serverId,
    t.needsSync ? 1 : 0,
    t.lastSyncedAt,
    t.locallyDeleted ? 1 : 0,
    t.pendingRemoteDelete ? 1 : 0,
    t.deletedAt,
  ];
}
