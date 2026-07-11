/**
 * Maps Open Food Facts API responses to product info. 1:1 port of
 * `SharedLogic/BarcodeProductMapper.swift` (framework-free). The barcode-scan
 * flow (Phase 5) hits `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
 * and feeds the JSON here to get a structured product for a grocery/pantry item.
 *
 * In Swift the input was `Data`/`[String: Any]`; in TS it's the already-parsed
 * JSON object (from `response.json()`), so the `Data` variant is dropped.
 */

export type ProductLookupResult = {
  barcode: string;
  name: string;
  brand: string;
  category: string;
  quantity: string;
  imageURL: string;
};

type Json = Record<string, unknown>;

function asString(v: unknown): string {
  return typeof v === 'string' ? v : '';
}

/** Picks the best available product name (product_name_en → product_name → generic_name). */
export function bestProductName(product: Json): string {
  const candidates = [
    asString(product.product_name_en),
    asString(product.product_name),
    asString(product.generic_name),
  ];
  for (const candidate of candidates) {
    const trimmed = candidate.trim();
    if (trimmed.length > 0) return trimmed;
  }
  return '';
}

/** Open Food Facts category tags → our store-aisle categories (order = priority). */
const offCategoryMapping: { keywords: string[]; category: string }[] = [
  { keywords: ['fruits', 'vegetables', 'legumes', 'salads'], category: 'Produce' },
  { keywords: ['dairies', 'milks', 'cheeses', 'yogurts', 'eggs', 'butters', 'creams'], category: 'Dairy' },
  { keywords: ['meats', 'poultry', 'beef', 'pork', 'fish', 'seafood', 'lamb'], category: 'Meat' },
  { keywords: ['cereals', 'pasta', 'rice', 'canned', 'sauces', 'oils', 'flour', 'sugar', 'spices'], category: 'Dry & Canned' },
  { keywords: ['frozen', 'ice-cream'], category: 'Frozen' },
  { keywords: ['breads', 'bakery', 'pastries'], category: 'Bakery' },
  { keywords: ['snacks', 'chips', 'crackers', 'cookies', 'candy', 'chocolate'], category: 'Snacks' },
  { keywords: ['beverages', 'drinks', 'juices', 'sodas', 'waters', 'coffee', 'tea'], category: 'Beverages' },
  { keywords: ['condiments', 'dressings', 'ketchup', 'mustard', 'mayonnaise'], category: 'Condiments' },
  { keywords: ['cleaning', 'household', 'paper'], category: 'Household' },
];

/** Maps OFF category tags (like "en:dairies", "en:whole-milks") to a store-aisle category. */
export function mapOFFCategory(tags: string[]): string {
  const normalized = tags.map((tag) => {
    const parts = tag.split(':');
    return (parts.length > 1 ? parts[1] : tag).toLowerCase();
  });
  for (const { keywords, category } of offCategoryMapping) {
    for (const tag of normalized) {
      for (const keyword of keywords) {
        if (tag.includes(keyword)) return category;
      }
    }
  }
  return 'Other';
}

/**
 * Parses an Open Food Facts API v2 JSON object into a {@link ProductLookupResult}.
 * Returns null if the product was not found (status != 1) or has no name.
 */
export function parseOpenFoodFactsJSON(json: unknown): ProductLookupResult | null {
  if (typeof json !== 'object' || json === null) return null;
  const root = json as Json;
  const status = typeof root.status === 'number' ? root.status : 0;
  if (status !== 1) return null;

  const product = (typeof root.product === 'object' && root.product !== null ? root.product : {}) as Json;
  const barcode = asString(root.code);
  const name = bestProductName(product);
  if (name.length === 0) return null;

  const categoriesTags = Array.isArray(product.categories_tags)
    ? (product.categories_tags.filter((t): t is string => typeof t === 'string'))
    : [];

  return {
    barcode,
    name,
    brand: asString(product.brands),
    category: mapOFFCategory(categoriesTags),
    quantity: asString(product.quantity),
    imageURL: asString(product.image_front_small_url),
  };
}

/** "Brand Name Product", or just "Product" if brand is empty / already in the name. */
export function formatProductDisplay(name: string, brand: string): string {
  const trimmedBrand = brand.trim();
  if (trimmedBrand.length === 0) return name;
  if (name.toLowerCase().includes(trimmedBrand.toLowerCase())) return name;
  return `${trimmedBrand} ${name}`;
}
