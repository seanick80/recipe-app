/**
 * Open Food Facts barcode lookup. Thin fetch wrapper around
 * {@link parseOpenFoodFactsJSON} — builds the OFF API v2 URL, fetches the
 * product JSON, parses it, and folds every failure (network error, non-2xx
 * status, malformed body, product-not-found) down to `null` so callers only
 * have to handle "found" vs "not found".
 *
 * `fetchImpl` is injected so tests can drive it without touching the network;
 * it defaults to the global `fetch`.
 */
import { parseOpenFoodFactsJSON, type ProductLookupResult } from './barcodeProductMapper';

/** Builds the Open Food Facts API v2 product URL for a barcode. */
export function offProductUrl(barcode: string): string {
  return `https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(barcode)}.json`;
}

/**
 * Looks up a barcode on Open Food Facts. Resolves to the parsed product, or
 * `null` when the product is unknown or anything goes wrong (never rejects).
 */
export async function lookupBarcode(
  barcode: string,
  fetchImpl: typeof fetch = fetch,
): Promise<ProductLookupResult | null> {
  const code = barcode.trim();
  if (code.length === 0) return null;
  try {
    const response = await fetchImpl(offProductUrl(code));
    if (!response.ok) return null;
    const json = (await response.json()) as unknown;
    return parseOpenFoodFactsJSON(json);
  } catch {
    return null;
  }
}
