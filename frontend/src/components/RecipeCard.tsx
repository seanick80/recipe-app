import { Link } from "react-router-dom";
import type { Recipe } from "../api/recipes";
import styles from "./RecipeCard.module.css";

interface RecipeCardProps {
  recipe: Recipe;
}

export function RecipeCard({ recipe }: RecipeCardProps) {
  const totalTime = recipe.prep_time_minutes + recipe.cook_time_minutes;

  return (
    <Link to={`/recipes/${recipe.id}`} className={styles.card}>
      <h3 className={styles.name}>{recipe.name}</h3>
      {recipe.summary && <p className={styles.summary}>{recipe.summary}</p>}
      <div className={styles.meta}>
        {recipe.cuisine && <span>{recipe.cuisine}</span>}
        {totalTime > 0 && <span>{totalTime} min</span>}
        {recipe.servings > 0 && (
          <span>
            {recipe.servings} serving{recipe.servings !== 1 ? "s" : ""}
          </span>
        )}
      </div>
    </Link>
  );
}
