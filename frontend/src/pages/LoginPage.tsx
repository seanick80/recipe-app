import { Navigate } from "react-router-dom";
import { useAuth } from "../hooks/useAuth";
import { getLoginUrl } from "../api/auth";
import styles from "./LoginPage.module.css";

export function LoginPage() {
  const { data: user, isLoading } = useAuth();

  if (isLoading) return <div className="loading">Loading...</div>;
  if (user) return <Navigate to="/" />;

  return (
    <div className={styles.container}>
      <h1 className={styles.title}>Sign In</h1>
      <p className={styles.subtitle}>
        Sign in to create and manage your recipes.
      </p>
      <a href={getLoginUrl()} className={styles.googleBtn}>
        Sign in with Google
      </a>
    </div>
  );
}
