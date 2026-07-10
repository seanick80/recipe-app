/**
 * Minimal, signature-free JWT claim decoder — a TypeScript port of the SwiftUI
 * `JWTDecoder`. Used only to read claims for *optimistic* session restore on
 * cold start (render the signed-in UI instantly, then validate against
 * `/auth/me` in the background). The server is the sole authority on validity;
 * we never trust these claims for anything but UI hydration.
 */
export type JwtClaims = {
  /** `sub` claim — the user's email. */
  email?: string;
  name?: string;
  role?: string;
  /** Expiry, seconds since epoch. */
  exp?: number;
};

/** Decode a base64url segment to a UTF-8 string (handles non-ASCII names). */
function base64UrlDecodeToString(segment: string): string {
  const b64 = segment.replace(/-/g, '+').replace(/_/g, '/');
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
  const binary = atob(padded);
  // `atob` yields a Latin1 string; re-interpret the bytes as UTF-8 so accented
  // characters in `name` survive the round-trip.
  const percentEncoded = Array.from(binary)
    .map((c) => '%' + c.charCodeAt(0).toString(16).padStart(2, '0'))
    .join('');
  return decodeURIComponent(percentEncoded);
}

export function decodeJwt(token: string): JwtClaims | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(base64UrlDecodeToString(parts[1])) as Record<string, unknown>;
    return {
      email: typeof payload.sub === 'string' ? payload.sub : undefined,
      name: typeof payload.name === 'string' ? payload.name : undefined,
      role: typeof payload.role === 'string' ? payload.role : undefined,
      exp: typeof payload.exp === 'number' ? payload.exp : undefined,
    };
  } catch {
    return null;
  }
}

/** True if the token is past its `exp`. Tokens with no `exp` are treated as non-expiring. */
export function isExpired(claims: JwtClaims, nowSeconds: number): boolean {
  if (claims.exp == null) return false;
  return claims.exp <= nowSeconds;
}
