/**
 * Auth wire-format types, mirroring the SwiftUI `AuthService` DTOs and the
 * server's auth responses.
 */

/** Response from `POST /auth/mobile/google` and `POST /auth/refresh`. */
export type TokenResponse = {
  token: string;
  email: string;
  name: string;
  role: string;
};

/** Response from `GET /auth/me`, and the shape held in auth state. */
export type AuthUser = {
  email: string;
  name: string;
  role: string;
};
