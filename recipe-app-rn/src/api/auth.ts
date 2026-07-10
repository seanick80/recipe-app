import { apiRequest } from '../lib/apiClient';
import type { AuthUser, TokenResponse } from '../types/auth';

/**
 * Auth endpoints, mirroring the SwiftUI `AuthService` network calls.
 * - `exchangeGoogleToken`: the load-bearing native sign-in exchange.
 * - `fetchMe`: background session validation.
 * - `refreshToken`: 401 recovery before flagging re-auth.
 */

export function exchangeGoogleToken(idToken: string): Promise<TokenResponse> {
  return apiRequest<TokenResponse>('auth/mobile/google', {
    method: 'POST',
    body: { id_token: idToken },
  });
}

export function fetchMe(token: string): Promise<AuthUser> {
  return apiRequest<AuthUser>('auth/me', { token });
}

export function refreshToken(token: string): Promise<TokenResponse> {
  return apiRequest<TokenResponse>('auth/refresh', { method: 'POST', token });
}
