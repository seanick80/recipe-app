import { apiFetch } from "./client";

export interface User {
  email: string;
  name: string;
  role: string;
}

export function fetchCurrentUser(): Promise<User> {
  return apiFetch<User>("/auth/me");
}

export function getLoginUrl(): string {
  return "/api/v1/auth/login";
}

export function logout(): Promise<void> {
  return apiFetch<void>("/auth/logout", { method: "POST" });
}
