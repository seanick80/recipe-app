import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

import { exchangeGoogleToken, fetchMe, refreshToken } from '../api/auth';
import { ApiError } from '../lib/apiClient';
import { signInWithGoogle, signOutGoogle } from '../lib/googleSignIn';
import { decodeJwt } from '../lib/jwt';
import { deleteToken, getToken, setToken } from '../lib/secureStore';
import type { AuthUser } from '../types/auth';

type AuthStatus = 'loading' | 'authenticated' | 'unauthenticated';

type AuthContextValue = {
  status: AuthStatus;
  user: AuthUser | null;
  /** Current JWT, or null when signed out / browsing as a guest. */
  token: string | null;
  /**
   * Background validation/refresh failed — the app stays usable (local view)
   * but should nudge the user to sign in again. Distinct from "signed out".
   */
  needsReauth: boolean;
  /** True when the user chose "continue without signing in" (local-only, no token). */
  isGuest: boolean;
  /** Native Google sign-in → token exchange. Returns after state is updated. */
  signIn: () => Promise<void>;
  signOut: () => Promise<void>;
  continueAsGuest: () => void;
};

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [status, setStatus] = useState<AuthStatus>('loading');
  const [user, setUser] = useState<AuthUser | null>(null);
  const [token, setTokenState] = useState<string | null>(null);
  const [needsReauth, setNeedsReauth] = useState(false);
  const [isGuest, setIsGuest] = useState(false);

  /**
   * Background session validation against `/auth/me`. On 401 it tries a token
   * refresh before flipping `needsReauth`; it never forces a sign-out. Network
   * errors are swallowed so the app stays optimistically signed in (retried on
   * the next launch), matching the SwiftUI `validateSession`.
   */
  const validateSession = useCallback(async (currentToken: string) => {
    try {
      const me = await fetchMe(currentToken);
      setUser(me);
      setNeedsReauth(false);
    } catch (e) {
      if (e instanceof ApiError && e.kind === 'unauthorized') {
        try {
          const refreshed = await refreshToken(currentToken);
          await setToken(refreshed.token);
          setTokenState(refreshed.token);
          setUser({ email: refreshed.email, name: refreshed.name, role: refreshed.role });
          setNeedsReauth(false);
        } catch {
          setNeedsReauth(true);
        }
      }
      // Non-auth (network/transport) errors: stay signed in, retry next launch.
    }
  }, []);

  // Optimistic session restore on cold start: decode the stored token's claims
  // to render the signed-in UI immediately, then validate in the background.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      const stored = await getToken();
      if (cancelled) return;
      if (!stored) {
        setStatus('unauthenticated');
        return;
      }
      const claims = decodeJwt(stored);
      setTokenState(stored);
      if (claims?.email) {
        setUser({ email: claims.email, name: claims.name ?? '', role: claims.role ?? '' });
      }
      setStatus('authenticated');
      void validateSession(stored);
    })();
    return () => {
      cancelled = true;
    };
  }, [validateSession]);

  const signIn = useCallback(async () => {
    const idToken = await signInWithGoogle();
    if (!idToken) return; // cancelled — leave state untouched
    const resp = await exchangeGoogleToken(idToken);
    await setToken(resp.token);
    setTokenState(resp.token);
    setUser({ email: resp.email, name: resp.name, role: resp.role });
    setNeedsReauth(false);
    setIsGuest(false);
    setStatus('authenticated');
  }, []);

  const signOut = useCallback(async () => {
    await signOutGoogle();
    await deleteToken();
    setTokenState(null);
    setUser(null);
    setNeedsReauth(false);
    setIsGuest(false);
    setStatus('unauthenticated');
  }, []);

  const continueAsGuest = useCallback(() => {
    setIsGuest(true);
    setStatus('authenticated');
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({ status, user, token, needsReauth, isGuest, signIn, signOut, continueAsGuest }),
    [status, user, token, needsReauth, isGuest, signIn, signOut, continueAsGuest],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within an AuthProvider');
  return ctx;
}
