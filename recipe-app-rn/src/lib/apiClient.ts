import { API_BASE_URL, USER_AGENT } from '../config';

export type ApiErrorKind =
  | 'unauthorized'
  | 'forbidden'
  | 'notFound'
  | 'server'
  | 'network'
  | 'decode';

/** Typed error mirroring the SwiftUI `APIError` cases. */
export class ApiError extends Error {
  readonly kind: ApiErrorKind;
  readonly status: number;

  constructor(kind: ApiErrorKind, status: number, message: string) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
  }
}

/** 429 and 5xx are retried with backoff; 401/403/404 are terminal (matches SwiftUI). */
export function isRetryableStatus(status: number): boolean {
  return status === 429 || (status >= 500 && status < 600);
}

const defaultSleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

export type RequestOptions = {
  method?: string;
  /** JSON-serialized as the request body when present. */
  body?: unknown;
  /** Bearer token; attached as `Authorization: Bearer <token>` when truthy. */
  token?: string | null;
  /** Max attempts including the first (default 3), mirroring the SwiftUI retry loop. */
  maxAttempts?: number;
  /** Injectable for tests; defaults to real exponential backoff. */
  sleep?: (ms: number) => Promise<void>;
  signal?: AbortSignal;
};

/**
 * Core HTTP layer — a port of the SwiftUI `APIClient.performRequest`.
 * Attaches `User-Agent` + `Authorization`, JSON-encodes the body, retries
 * 429/5xx up to `maxAttempts` with `2^attempt` second backoff, and maps
 * failures onto {@link ApiError}. The token is passed in explicitly (read fresh
 * from secure storage by the caller) rather than cached here.
 */
export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const { method = 'GET', body, token, maxAttempts = 3, sleep = defaultSleep, signal } = options;

  const url = path.startsWith('http')
    ? path
    : `${API_BASE_URL}/${path.replace(/^\/+/, '')}`;

  const headers: Record<string, string> = {
    'User-Agent': USER_AGENT,
    Accept: 'application/json',
  };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;

  let lastError: ApiError = new ApiError('network', 0, 'Request failed');

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    let response: Response;
    try {
      response = await fetch(url, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
        signal,
      });
    } catch (e) {
      lastError = new ApiError('network', 0, `Network request failed: ${String(e)}`);
      if (attempt < maxAttempts - 1) {
        await sleep(2 ** attempt * 1000);
        continue;
      }
      throw lastError;
    }

    if (response.ok) {
      if (response.status === 204) return undefined as T;
      try {
        return (await response.json()) as T;
      } catch (e) {
        throw new ApiError('decode', response.status, `Failed to decode response: ${String(e)}`);
      }
    }

    if (response.status === 401) throw new ApiError('unauthorized', 401, 'Unauthorized');
    if (response.status === 403) throw new ApiError('forbidden', 403, 'Forbidden');
    if (response.status === 404) throw new ApiError('notFound', 404, 'Not found');

    if (isRetryableStatus(response.status)) {
      lastError = new ApiError('server', response.status, `Server error ${response.status}`);
      if (attempt < maxAttempts - 1) {
        await sleep(2 ** attempt * 1000);
        continue;
      }
      throw lastError;
    }

    throw new ApiError('server', response.status, `Request failed (${response.status})`);
  }

  throw lastError;
}
