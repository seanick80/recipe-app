import { decodeJwt, isExpired } from './jwt';

/** base64url-encode a UTF-8 JSON value (test helper — inverse of the decoder). */
function b64url(value: unknown): string {
  const json = JSON.stringify(value);
  const utf8 = encodeURIComponent(json).replace(/%([0-9A-Fa-f]{2})/g, (_, h: string) =>
    String.fromCharCode(parseInt(h, 16)),
  );
  return btoa(utf8).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function makeJwt(payload: Record<string, unknown>): string {
  return `${b64url({ alg: 'HS256', typ: 'JWT' })}.${b64url(payload)}.signature`;
}

describe('decodeJwt', () => {
  it('maps sub → email and reads name/role/exp', () => {
    const token = makeJwt({ sub: 'nicha@aq1systems.com', name: 'Nick', role: 'admin', exp: 123 });
    expect(decodeJwt(token)).toEqual({
      email: 'nicha@aq1systems.com',
      name: 'Nick',
      role: 'admin',
      exp: 123,
    });
  });

  it('decodes UTF-8 names correctly', () => {
    const token = makeJwt({ sub: 'a@b.com', name: 'José Ölmütz' });
    expect(decodeJwt(token)?.name).toBe('José Ölmütz');
  });

  it('leaves missing/wrong-typed claims undefined', () => {
    const token = makeJwt({ sub: 'a@b.com', exp: 'not-a-number' });
    const claims = decodeJwt(token);
    expect(claims).toEqual({ email: 'a@b.com', name: undefined, role: undefined, exp: undefined });
  });

  it('returns null for a malformed token (wrong segment count)', () => {
    expect(decodeJwt('abc.def')).toBeNull();
    expect(decodeJwt('not-a-jwt')).toBeNull();
  });

  it('returns null when the payload is not valid JSON', () => {
    const token = `${b64url({ alg: 'HS256' })}.${btoa('{not json')}.sig`;
    expect(decodeJwt(token)).toBeNull();
  });
});

describe('isExpired', () => {
  it('is true when exp is at or before now', () => {
    expect(isExpired({ exp: 100 }, 100)).toBe(true);
    expect(isExpired({ exp: 100 }, 101)).toBe(true);
  });

  it('is false when exp is in the future', () => {
    expect(isExpired({ exp: 100 }, 99)).toBe(false);
  });

  it('treats a token without exp as non-expiring', () => {
    expect(isExpired({}, 9_999_999_999)).toBe(false);
  });
});
