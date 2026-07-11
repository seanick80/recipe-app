/**
 * expo-sqlite–backed {@link RecipeRepository}.
 *
 * Recipes and their ingredients are read as aggregates and written atomically
 * inside a transaction. Ingredient writes are always delete-all + re-insert
 * (matching the server + SwiftUI strategy), so callers never diff ingredient
 * rows. Booleans are stored as 0/1 and coerced back on read.
 */
import type { SQLiteDatabase } from 'expo-sqlite';

import type { LocalIngredient, LocalRecipe, RecipeRepository } from '../sync/types';
import type { IngredientRow, RecipeRow } from './schema';

const RECIPE_COLUMNS = `
  local_id, server_id, name, summary, instructions, prep_time_minutes,
  cook_time_minutes, servings, cuisine, course, tags, source_url, difficulty,
  is_favorite, is_published, created_at, updated_at, needs_sync, last_synced_at,
  locally_deleted, pending_remote_delete, deleted_at, is_conflicted_copy
`;

function rowToRecipe(row: RecipeRow, ingredients: LocalIngredient[]): LocalRecipe {
  return {
    localId: row.local_id,
    serverId: row.server_id,
    name: row.name,
    summary: row.summary,
    instructions: row.instructions,
    prep_time_minutes: row.prep_time_minutes,
    cook_time_minutes: row.cook_time_minutes,
    servings: row.servings,
    cuisine: row.cuisine,
    course: row.course,
    tags: row.tags,
    source_url: row.source_url,
    difficulty: row.difficulty,
    is_favorite: row.is_favorite === 1,
    is_published: row.is_published === 1,
    ingredients,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    needsSync: row.needs_sync === 1,
    lastSyncedAt: row.last_synced_at,
    locallyDeleted: row.locally_deleted === 1,
    pendingRemoteDelete: row.pending_remote_delete === 1,
    deletedAt: row.deleted_at,
    isConflictedCopy: row.is_conflicted_copy === 1,
  };
}

/** Positional bind values for an INSERT/UPDATE of the recipe columns above. */
function recipeParams(r: LocalRecipe): (string | number | null)[] {
  return [
    r.localId,
    r.serverId,
    r.name,
    r.summary,
    r.instructions,
    r.prep_time_minutes,
    r.cook_time_minutes,
    r.servings,
    r.cuisine,
    r.course,
    r.tags,
    r.source_url,
    r.difficulty,
    r.is_favorite ? 1 : 0,
    r.is_published ? 1 : 0,
    r.createdAt,
    r.updatedAt,
    r.needsSync ? 1 : 0,
    r.lastSyncedAt,
    r.locallyDeleted ? 1 : 0,
    r.pendingRemoteDelete ? 1 : 0,
    r.deletedAt,
    r.isConflictedCopy ? 1 : 0,
  ];
}

export class SqliteRecipeRepo implements RecipeRepository {
  constructor(private readonly db: SQLiteDatabase) {}

  private async ingredientsFor(localIds: string[]): Promise<Map<string, LocalIngredient[]>> {
    const map = new Map<string, LocalIngredient[]>();
    if (localIds.length === 0) return map;
    const placeholders = localIds.map(() => '?').join(',');
    const rows = await this.db.getAllAsync<IngredientRow>(
      `SELECT recipe_local_id, name, quantity, unit, category, display_order, notes
       FROM ingredients WHERE recipe_local_id IN (${placeholders})
       ORDER BY display_order ASC`,
      localIds,
    );
    for (const row of rows) {
      const list = map.get(row.recipe_local_id) ?? [];
      list.push({
        name: row.name,
        quantity: row.quantity,
        unit: row.unit,
        category: row.category,
        display_order: row.display_order,
        notes: row.notes,
      });
      map.set(row.recipe_local_id, list);
    }
    return map;
  }

  async getAll(): Promise<LocalRecipe[]> {
    const rows = await this.db.getAllAsync<RecipeRow>(
      `SELECT ${RECIPE_COLUMNS} FROM recipes ORDER BY updated_at DESC`,
    );
    const ings = await this.ingredientsFor(rows.map((r) => r.local_id));
    return rows.map((r) => rowToRecipe(r, ings.get(r.local_id) ?? []));
  }

  async getByLocalId(localId: string): Promise<LocalRecipe | null> {
    const row = await this.db.getFirstAsync<RecipeRow>(
      `SELECT ${RECIPE_COLUMNS} FROM recipes WHERE local_id = ?`,
      [localId],
    );
    if (!row) return null;
    const ings = await this.ingredientsFor([localId]);
    return rowToRecipe(row, ings.get(localId) ?? []);
  }

  async getByServerId(serverId: string): Promise<LocalRecipe | null> {
    const row = await this.db.getFirstAsync<RecipeRow>(
      `SELECT ${RECIPE_COLUMNS} FROM recipes WHERE server_id = ?`,
      [serverId],
    );
    if (!row) return null;
    const ings = await this.ingredientsFor([row.local_id]);
    return rowToRecipe(row, ings.get(row.local_id) ?? []);
  }

  private async writeIngredients(localId: string, ingredients: LocalIngredient[]): Promise<void> {
    await this.db.runAsync('DELETE FROM ingredients WHERE recipe_local_id = ?', [localId]);
    for (const ing of ingredients) {
      await this.db.runAsync(
        `INSERT INTO ingredients (recipe_local_id, name, quantity, unit, category, display_order, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [localId, ing.name, ing.quantity, ing.unit, ing.category, ing.display_order, ing.notes],
      );
    }
  }

  async insert(recipe: LocalRecipe): Promise<void> {
    const placeholders = recipeParams(recipe).map(() => '?').join(', ');
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `INSERT INTO recipes (${RECIPE_COLUMNS}) VALUES (${placeholders})`,
        recipeParams(recipe),
      );
      await this.writeIngredients(recipe.localId, recipe.ingredients);
    });
  }

  async update(recipe: LocalRecipe): Promise<void> {
    await this.db.withTransactionAsync(async () => {
      await this.db.runAsync(
        `UPDATE recipes SET
           server_id = ?, name = ?, summary = ?, instructions = ?, prep_time_minutes = ?,
           cook_time_minutes = ?, servings = ?, cuisine = ?, course = ?, tags = ?,
           source_url = ?, difficulty = ?, is_favorite = ?, is_published = ?, created_at = ?,
           updated_at = ?, needs_sync = ?, last_synced_at = ?, locally_deleted = ?,
           pending_remote_delete = ?, deleted_at = ?, is_conflicted_copy = ?
         WHERE local_id = ?`,
        [
          recipe.serverId,
          recipe.name,
          recipe.summary,
          recipe.instructions,
          recipe.prep_time_minutes,
          recipe.cook_time_minutes,
          recipe.servings,
          recipe.cuisine,
          recipe.course,
          recipe.tags,
          recipe.source_url,
          recipe.difficulty,
          recipe.is_favorite ? 1 : 0,
          recipe.is_published ? 1 : 0,
          recipe.createdAt,
          recipe.updatedAt,
          recipe.needsSync ? 1 : 0,
          recipe.lastSyncedAt,
          recipe.locallyDeleted ? 1 : 0,
          recipe.pendingRemoteDelete ? 1 : 0,
          recipe.deletedAt,
          recipe.isConflictedCopy ? 1 : 0,
          recipe.localId,
        ],
      );
      await this.writeIngredients(recipe.localId, recipe.ingredients);
    });
  }

  async remove(localId: string): Promise<void> {
    // ingredients cascade via the FK (foreign_keys pragma is enabled on open).
    await this.db.runAsync('DELETE FROM recipes WHERE local_id = ?', [localId]);
  }
}
