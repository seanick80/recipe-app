import { useState } from "react";
import { Link } from "react-router-dom";
import { useRecipes } from "../hooks/useRecipes";
import { useAuth } from "../hooks/useAuth";
import { RecipeCard } from "../components/RecipeCard";
import styles from "./RecipeListPage.module.css";

export function RecipeListPage() {
  const { data: user, isLoading: authLoading } = useAuth();
  const { data: recipes, isLoading, error } = useRecipes();
  const [search, setSearch] = useState("");

  if (authLoading) return <div className="loading">Loading...</div>;

  if (!user) {
    return (
      <div className={styles.empty}>
        <p>Sign in to see your recipes.</p>
        <Link to="/login" className={styles.newBtn}>
          Sign in
        </Link>
      </div>
    );
  }

  if (isLoading) return <div className="loading">Loading recipes...</div>;
  if (error) return <div className="error">Failed to load recipes.</div>;

  const filtered = (recipes ?? []).filter((r) =>
    r.name.toLowerCase().includes(search.toLowerCase()),
  );

  return (
    <div>
      <div className={styles.toolbar}>
        <input
          type="text"
          className={styles.search}
          placeholder="Search recipes..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {user && (
          <Link to="/recipes/new" className={styles.newBtn}>
            New Recipe
          </Link>
        )}
      </div>
      {filtered.length === 0 ? (
        <p className={styles.empty}>No recipes found.</p>
      ) : (
        <div className={styles.grid}>
          {filtered.map((recipe) => (
            <RecipeCard key={recipe.id} recipe={recipe} />
          ))}
        </div>
      )}
    </div>
  );
}
