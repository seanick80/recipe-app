import { Link, Outlet } from "react-router-dom";
import { useAuth } from "../hooks/useAuth";
import { logout } from "../api/auth";
import { useQueryClient } from "@tanstack/react-query";
import styles from "./Layout.module.css";

export function Layout() {
  const { data: user } = useAuth();
  const queryClient = useQueryClient();

  async function handleLogout() {
    await logout();
    queryClient.invalidateQueries({ queryKey: ["auth"] });
  }

  return (
    <div className={styles.wrapper}>
      <header className={styles.header}>
        <Link to="/" className={styles.brand}>
          Our Recipes
        </Link>
        <nav className={styles.nav}>
          <Link to="/">Recipes</Link>
          {user ? (
            <span className={styles.authInfo}>
              <span className={styles.userName}>{user.name}</span>
              <button onClick={handleLogout} className={styles.logoutBtn}>
                Log out
              </button>
            </span>
          ) : (
            <Link to="/login">Sign in</Link>
          )}
        </nav>
      </header>
      <main className={styles.main}>
        <Outlet />
      </main>
    </div>
  );
}
