import { useNavigate, useParams, Link } from "react-router-dom";
import { useRecipe, useDeleteRecipe } from "../hooks/useRecipes";
import { useAuth } from "../hooks/useAuth";
import styles from "./RecipeDetailPage.module.css";

export function RecipeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { data: recipe, isLoading, error } = useRecipe(id!);
  const { data: user } = useAuth();
  const deleteMutation = useDeleteRecipe();

  if (isLoading) return <div className="loading">Loading recipe...</div>;
  if (error || !recipe) return <div className="error">Recipe not found.</div>;

  const totalTime = recipe.prep_time_minutes + recipe.cook_time_minutes;
  const isAdmin = user?.role === "admin";

  const recipeId = recipe.id;

  function handleDelete() {
    if (!confirm("Are you sure you want to delete this recipe?")) return;
    deleteMutation.mutate(recipeId, {
      onSuccess: () => navigate("/"),
    });
  }

  const instructions = recipe.instructions
    .split("\n")
    .filter((line) => line.trim() !== "");

  return (
    <article className={styles.article}>
      <h1 className={styles.title}>{recipe.name}</h1>

      {recipe.summary && <p className={styles.summary}>{recipe.summary}</p>}

      <div className={styles.metaBar}>
        {recipe.prep_time_minutes > 0 && (
          <span>Prep: {recipe.prep_time_minutes} min</span>
        )}
        {recipe.cook_time_minutes > 0 && (
          <span>Cook: {recipe.cook_time_minutes} min</span>
        )}
        {totalTime > 0 && <span>Total: {totalTime} min</span>}
        {recipe.servings > 0 && <span>Servings: {recipe.servings}</span>}
        {recipe.difficulty && <span>{recipe.difficulty}</span>}
        {recipe.cuisine && <span>{recipe.cuisine}</span>}
      </div>

      {recipe.ingredients.length > 0 && (
        <section className={styles.section}>
          <h2>Ingredients</h2>
          <table className={styles.ingredientTable}>
            <thead>
              <tr>
                <th>Qty</th>
                <th>Unit</th>
                <th>Ingredient</th>
              </tr>
            </thead>
            <tbody>
              {recipe.ingredients.map((ing) => (
                <tr key={ing.id}>
                  <td>{ing.quantity}</td>
                  <td>{ing.unit}</td>
                  <td>{ing.name}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      {instructions.length > 0 && (
        <section className={styles.section}>
          <h2>Instructions</h2>
          <ol className={styles.instructions}>
            {instructions.map((step, i) => (
              <li key={i}>{step}</li>
            ))}
          </ol>
        </section>
      )}

      {user && (
        <div className={styles.actions}>
          <Link to={`/recipes/${recipe.id}/edit`} className={styles.editBtn}>
            Edit
          </Link>
          {isAdmin && (
            <button
              onClick={handleDelete}
              className={styles.deleteBtn}
              disabled={deleteMutation.isPending}
            >
              {deleteMutation.isPending ? "Deleting..." : "Delete"}
            </button>
          )}
        </div>
      )}
    </article>
  );
}
