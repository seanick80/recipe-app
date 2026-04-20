import { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useRecipe, useCreateRecipe, useUpdateRecipe } from "../hooks/useRecipes";
import { IngredientRow } from "../components/IngredientRow";
import type { RecipeCreate } from "../api/recipes";
import styles from "./RecipeEditorPage.module.css";

interface IngredientForm {
  name: string;
  quantity: number;
  unit: string;
  category: string;
  display_order: number;
  notes: string;
}

const EMPTY_INGREDIENT: IngredientForm = {
  name: "",
  quantity: 0,
  unit: "",
  category: "",
  display_order: 0,
  notes: "",
};

function emptyForm(): RecipeCreate {
  return {
    name: "",
    summary: "",
    instructions: "",
    prep_time_minutes: 0,
    cook_time_minutes: 0,
    servings: 0,
    cuisine: "",
    course: "",
    tags: "",
    source_url: "",
    difficulty: "",
    is_favorite: false,
    is_published: false,
    ingredients: [],
  };
}

export function RecipeEditorPage() {
  const { id } = useParams<{ id: string }>();
  const isEditing = Boolean(id);
  const navigate = useNavigate();

  const { data: existing, isLoading } = useRecipe(id ?? "");
  const createMutation = useCreateRecipe();
  const updateMutation = useUpdateRecipe();

  const [form, setForm] = useState<RecipeCreate>(emptyForm);
  const [ingredients, setIngredients] = useState<IngredientForm[]>([]);
  const [initialized, setInitialized] = useState(false);

  useEffect(() => {
    if (isEditing && existing && !initialized) {
      setForm({
        name: existing.name,
        summary: existing.summary,
        instructions: existing.instructions,
        prep_time_minutes: existing.prep_time_minutes,
        cook_time_minutes: existing.cook_time_minutes,
        servings: existing.servings,
        cuisine: existing.cuisine,
        course: existing.course,
        tags: existing.tags,
        source_url: existing.source_url,
        difficulty: existing.difficulty,
        is_favorite: existing.is_favorite,
        is_published: existing.is_published,
        ingredients: [],
      });
      setIngredients(
        existing.ingredients.map((ing) => ({
          name: ing.name,
          quantity: ing.quantity,
          unit: ing.unit,
          category: ing.category,
          display_order: ing.display_order,
          notes: ing.notes,
        })),
      );
      setInitialized(true);
    }
  }, [isEditing, existing, initialized]);

  if (isEditing && isLoading) {
    return <div className="loading">Loading recipe...</div>;
  }

  function updateField(field: keyof RecipeCreate, value: string | number | boolean) {
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  function handleIngredientChange(
    index: number,
    field: keyof IngredientForm,
    value: string | number,
  ) {
    setIngredients((prev) => {
      const next = [...prev];
      next[index] = { ...next[index], [field]: value };
      return next;
    });
  }

  function addIngredient() {
    setIngredients((prev) => [
      ...prev,
      { ...EMPTY_INGREDIENT, display_order: prev.length },
    ]);
  }

  function removeIngredient(index: number) {
    setIngredients((prev) => prev.filter((_, i) => i !== index));
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const payload: RecipeCreate = {
      ...form,
      ingredients: ingredients.map((ing, i) => ({
        ...ing,
        display_order: i,
      })),
    };

    if (isEditing && id) {
      updateMutation.mutate(
        { id, data: payload },
        { onSuccess: (recipe) => navigate(`/recipes/${recipe.id}`) },
      );
    } else {
      createMutation.mutate(payload, {
        onSuccess: (recipe) => navigate(`/recipes/${recipe.id}`),
      });
    }
  }

  const isPending = createMutation.isPending || updateMutation.isPending;

  return (
    <form onSubmit={handleSubmit} className={styles.form}>
      <h1 className={styles.title}>
        {isEditing ? "Edit Recipe" : "New Recipe"}
      </h1>

      <label className={styles.label}>
        Name
        <input
          type="text"
          required
          value={form.name}
          onChange={(e) => updateField("name", e.target.value)}
        />
      </label>

      <label className={styles.label}>
        Summary
        <textarea
          rows={2}
          value={form.summary}
          onChange={(e) => updateField("summary", e.target.value)}
        />
      </label>

      <div className={styles.row}>
        <label className={styles.label}>
          Prep Time (min)
          <input
            type="number"
            min={0}
            value={form.prep_time_minutes || ""}
            onChange={(e) =>
              updateField("prep_time_minutes", parseInt(e.target.value) || 0)
            }
          />
        </label>
        <label className={styles.label}>
          Cook Time (min)
          <input
            type="number"
            min={0}
            value={form.cook_time_minutes || ""}
            onChange={(e) =>
              updateField("cook_time_minutes", parseInt(e.target.value) || 0)
            }
          />
        </label>
        <label className={styles.label}>
          Servings
          <input
            type="number"
            min={0}
            value={form.servings || ""}
            onChange={(e) =>
              updateField("servings", parseInt(e.target.value) || 0)
            }
          />
        </label>
      </div>

      <div className={styles.row}>
        <label className={styles.label}>
          Cuisine
          <input
            type="text"
            value={form.cuisine}
            onChange={(e) => updateField("cuisine", e.target.value)}
          />
        </label>
        <label className={styles.label}>
          Course
          <input
            type="text"
            value={form.course}
            onChange={(e) => updateField("course", e.target.value)}
          />
        </label>
        <label className={styles.label}>
          Difficulty
          <input
            type="text"
            value={form.difficulty}
            onChange={(e) => updateField("difficulty", e.target.value)}
          />
        </label>
      </div>

      <label className={styles.label}>
        Tags
        <input
          type="text"
          placeholder="comma-separated"
          value={form.tags}
          onChange={(e) => updateField("tags", e.target.value)}
        />
      </label>

      <label className={styles.label}>
        Source URL
        <input
          type="url"
          value={form.source_url}
          onChange={(e) => updateField("source_url", e.target.value)}
        />
      </label>

      <fieldset className={styles.fieldset}>
        <legend>Ingredients</legend>
        {ingredients.map((ing, i) => (
          <IngredientRow
            key={i}
            ingredient={ing}
            index={i}
            onChange={handleIngredientChange}
            onRemove={removeIngredient}
          />
        ))}
        <button
          type="button"
          className={styles.addBtn}
          onClick={addIngredient}
        >
          + Add Ingredient
        </button>
      </fieldset>

      <label className={styles.label}>
        Instructions
        <textarea
          rows={8}
          placeholder="One step per line"
          value={form.instructions}
          onChange={(e) => updateField("instructions", e.target.value)}
        />
      </label>

      <div className={styles.checkboxes}>
        <label>
          <input
            type="checkbox"
            checked={form.is_favorite}
            onChange={(e) => updateField("is_favorite", e.target.checked)}
          />{" "}
          Favorite
        </label>
        <label>
          <input
            type="checkbox"
            checked={form.is_published}
            onChange={(e) => updateField("is_published", e.target.checked)}
          />{" "}
          Published
        </label>
      </div>

      <div className={styles.formActions}>
        <button type="submit" className={styles.saveBtn} disabled={isPending}>
          {isPending ? "Saving..." : "Save Recipe"}
        </button>
        <button
          type="button"
          className={styles.cancelBtn}
          onClick={() => navigate(-1)}
        >
          Cancel
        </button>
      </div>
    </form>
  );
}
