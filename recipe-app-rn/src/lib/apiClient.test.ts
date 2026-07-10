import { apiRequest, ApiError, isRetryableStatus } from './apiClient';

const noSleep = () => Promise.resolve();

function jsonResponse(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as unknown as Response;
}

describe('isRetryableStatus', () => {
  it.each([
    [429, true],
    [500, true],
    [503, true],
    [400, false],
    [401, false],
    [404, false],
    [200, false],
  ])('status %i → %s', (status, expected) => {
    expect(isRetryableStatus(status)).toBe(expected);
  });
});

describe('apiRequest', () => {
  const fetchMock = jest.fn();

  beforeEach(() => {
    fetchMock.mockReset();
    globalThis.fetch = fetchMock as unknown as typeof fetch;
  });

  it('builds the URL under the API base and returns parsed JSON', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, { hello: 'world' }));
    const result = await apiRequest<{ hello: string }>('recipes/');
    expect(result).toEqual({ hello: 'world' });
    const [url] = fetchMock.mock.calls[0];
    expect(url).toMatch(/\/api\/v1\/recipes\/$/);
  });

  it('attaches Authorization + User-Agent headers when a token is given', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, []));
    await apiRequest('recipes/', { token: 'abc123' });
    const [, init] = fetchMock.mock.calls[0];
    expect(init.headers.Authorization).toBe('Bearer abc123');
    expect(init.headers['User-Agent']).toBe('RecipeApp-RN/0.1.0');
  });

  it('omits Authorization when no token is given', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, []));
    await apiRequest('recipes/');
    const [, init] = fetchMock.mock.calls[0];
    expect(init.headers.Authorization).toBeUndefined();
  });

  it('JSON-encodes the body and sets Content-Type on POST', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(200, { token: 't' }));
    await apiRequest('auth/mobile/google', { method: 'POST', body: { id_token: 'g' } });
    const [, init] = fetchMock.mock.calls[0];
    expect(init.method).toBe('POST');
    expect(init.body).toBe('{"id_token":"g"}');
    expect(init.headers['Content-Type']).toBe('application/json');
  });

  it('returns undefined for 204 No Content', async () => {
    fetchMock.mockResolvedValueOnce({ ok: true, status: 204 } as Response);
    await expect(apiRequest('recipes/x', { method: 'DELETE' })).resolves.toBeUndefined();
  });

  it('throws unauthorized (no retry) on 401', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(401, {}));
    await expect(apiRequest('auth/me', { token: 't', sleep: noSleep })).rejects.toMatchObject({
      kind: 'unauthorized',
      status: 401,
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('throws forbidden on 403 and notFound on 404 without retrying', async () => {
    fetchMock.mockResolvedValueOnce(jsonResponse(403, {}));
    await expect(apiRequest('x', { sleep: noSleep })).rejects.toMatchObject({ kind: 'forbidden' });

    fetchMock.mockResolvedValueOnce(jsonResponse(404, {}));
    await expect(apiRequest('x', { sleep: noSleep })).rejects.toMatchObject({ kind: 'notFound' });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('retries 5xx up to maxAttempts then throws server error', async () => {
    fetchMock.mockResolvedValue(jsonResponse(503, {}));
    await expect(apiRequest('recipes/', { sleep: noSleep })).rejects.toMatchObject({
      kind: 'server',
      status: 503,
    });
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it('recovers when a retryable error is followed by success', async () => {
    fetchMock
      .mockResolvedValueOnce(jsonResponse(500, {}))
      .mockResolvedValueOnce(jsonResponse(200, { ok: true }));
    await expect(apiRequest('recipes/', { sleep: noSleep })).resolves.toEqual({ ok: true });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('retries network failures then throws a network ApiError', async () => {
    fetchMock.mockRejectedValue(new TypeError('offline'));
    const err = (await apiRequest('recipes/', { sleep: noSleep }).catch((e) => e)) as ApiError;
    expect(err).toBeInstanceOf(ApiError);
    expect(err.kind).toBe('network');
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });
});
