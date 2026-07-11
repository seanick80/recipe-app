/**
 * expo-sqlite–backed store for the local-only Shopping + Grocery domain
 * (Phase 4 slice 3). Lists and templates are read as aggregates (with their
 * items) and their item sets are written wholesale (delete-all + re-insert)
 * inside a transaction — lists are small and the UI always hands back the full
 * item array, so this is simpler than per-row diffing.
 */
import type { SQLiteDatabase } from 'expo-sqlite';

import type { GroceryItem, GroceryList, ShoppingTemplate, TemplateItem } from './types';

type ListRow = { id: string; name: string; created_at: string; archived_at: string | null };
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
};
type TemplateRow = { id: string; name: string; sort_order: number; created_at: string };
type TemplateItemRow = {
  id: string;
  template_id: string;
  name: string;
  quantity: number;
  unit: string;
  category: string;
  sort_order: number;
};

export interface GroceryRepository {
  getAllLists(): Promise<GroceryList[]>;
  insertList(list: GroceryList): Promise<void>;
  updateListMeta(id: string, name: string, archivedAt: string | null): Promise<void>;
  replaceListItems(listId: string, items: GroceryItem[]): Promise<void>;
  deleteList(id: string): Promise<void>;

  getAllTemplates(): Promise<ShoppingTemplate[]>;
  insertTemplate(template: ShoppingTemplate): Promise<void>;
  updateTemplateMeta(id: string, name: string): Promise<void>;
  replaceTemplateItems(templateId: string, items: TemplateItem[]): Promise<void>;
  deleteTemplate(id: string): Promise<void>;
}

export class SqliteGroceryRepo implements GroceryRepository {
  constructor(private readonly db: SQLiteDatabase) {}

  async getAllLists(): Promise<GroceryList[]> {
    const lists = await this.db.getAllAsync<ListRow>(
      'SELECT id, name, created_at, archived_at FROM grocery_lists ORDER BY created_at DESC',
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
      });
      byList.set(r.list_id, list);
    }
    return lists.map((l) => ({
      id: l.id,
      name: l.name,
      createdAt: l.created_at,
      archivedAt: l.archived_at,
      items: byList.get(l.id) ?? [],
    }));
  }

  async insertList(list: GroceryList): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        'INSERT INTO grocery_lists (id, name, created_at, archived_at) VALUES (?, ?, ?, ?)',
        [list.id, list.name, list.createdAt, list.archivedAt],
      );
      await this.insertItems(list.id, list.items);
    });
  }

  async updateListMeta(id: string, name: string, archivedAt: string | null): Promise<void> {
    await this.db.runAsync('UPDATE grocery_lists SET name = ?, archived_at = ? WHERE id = ?', [
      name,
      archivedAt,
      id,
    ]);
  }

  async replaceListItems(listId: string, items: GroceryItem[]): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync('DELETE FROM grocery_items WHERE list_id = ?', [listId]);
      await this.insertItems(listId, items);
    });
  }

  private async insertItems(listId: string, items: GroceryItem[]): Promise<void> {
    for (const i of items) {
      await this.db.runAsync(
        `INSERT INTO grocery_items
           (id, list_id, name, quantity, unit, category, is_checked, source_recipe_name, source_recipe_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
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
        ],
      );
    }
  }

  async deleteList(id: string): Promise<void> {
    await this.db.runAsync('DELETE FROM grocery_lists WHERE id = ?', [id]);
  }

  async getAllTemplates(): Promise<ShoppingTemplate[]> {
    const templates = await this.db.getAllAsync<TemplateRow>(
      'SELECT id, name, sort_order, created_at FROM shopping_templates ORDER BY sort_order ASC',
    );
    const itemRows = await this.db.getAllAsync<TemplateItemRow>('SELECT * FROM template_items ORDER BY sort_order ASC');
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
      items: byTemplate.get(t.id) ?? [],
    }));
  }

  async insertTemplate(template: ShoppingTemplate): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        'INSERT INTO shopping_templates (id, name, sort_order, created_at) VALUES (?, ?, ?, ?)',
        [template.id, template.name, template.sortOrder, template.createdAt],
      );
      await this.insertTemplateItems(template.id, template.items);
    });
  }

  async updateTemplateMeta(id: string, name: string): Promise<void> {
    await this.db.runAsync('UPDATE shopping_templates SET name = ? WHERE id = ?', [name, id]);
  }

  async replaceTemplateItems(templateId: string, items: TemplateItem[]): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync('DELETE FROM template_items WHERE template_id = ?', [templateId]);
      await this.insertTemplateItems(templateId, items);
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

  async deleteTemplate(id: string): Promise<void> {
    await this.db.runAsync('DELETE FROM shopping_templates WHERE id = ?', [id]);
  }
}
