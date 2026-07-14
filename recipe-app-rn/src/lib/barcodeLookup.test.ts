import { lookupBarcode, offProductUrl } from './barcodeLookup';

/** Minimal `Response` stand-in for the injected fetch. */
function fakeResponse(body: unknown, ok = true): Response {
  return {
    ok,
    status: ok ? 200 : 404,
    json: async () => body,
  } as unknown as Response;
}

describe('offProductUrl', () => {
  it('builds the OFF v2 product URL', () => {
    expect(offProductUrl('3017620422003')).toBe(
      'https://world.openfoodfacts.org/api/v2/product/3017620422003.json',
    );
  });

  it('encodes the barcode', () => {
    expect(offProductUrl('a b')).toContain('a%20b');
  });
});

describe('lookupBarcode', () => {
  it('returns the parsed product when found', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(
      fakeResponse({
        status: 1,
        code: '3017620422003',
        product: { product_name_en: 'Nutella', brands: 'Ferrero', categories_tags: ['en:dairies'] },
      }),
    );
    const result = await lookupBarcode('3017620422003', fetchImpl as unknown as typeof fetch);
    expect(fetchImpl).toHaveBeenCalledWith(offProductUrl('3017620422003'));
    expect(result).not.toBeNull();
    expect(result!.name).toBe('Nutella');
    expect(result!.brand).toBe('Ferrero');
    expect(result!.category).toBe('Dairy');
  });

  it('returns null when the product is not found (status 0)', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({ status: 0, code: '0000000000000' }));
    expect(await lookupBarcode('0000000000000', fetchImpl as unknown as typeof fetch)).toBeNull();
  });

  it('returns null on a non-ok HTTP status', async () => {
    const fetchImpl = jest.fn().mockResolvedValue(fakeResponse({}, false));
    expect(await lookupBarcode('123', fetchImpl as unknown as typeof fetch)).toBeNull();
  });

  it('returns null on a network error (never rejects)', async () => {
    const fetchImpl = jest.fn().mockRejectedValue(new Error('offline'));
    await expect(lookupBarcode('123', fetchImpl as unknown as typeof fetch)).resolves.toBeNull();
  });

  it('returns null on malformed JSON', async () => {
    const fetchImpl = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => {
        throw new Error('invalid json');
      },
    });
    expect(await lookupBarcode('123', fetchImpl as unknown as typeof fetch)).toBeNull();
  });

  it('returns null for a blank barcode without fetching', async () => {
    const fetchImpl = jest.fn();
    expect(await lookupBarcode('  ', fetchImpl as unknown as typeof fetch)).toBeNull();
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});
