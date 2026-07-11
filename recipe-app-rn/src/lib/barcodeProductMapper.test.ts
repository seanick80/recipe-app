/** Mirror of `TestFixtures/TestBarcode.swift`. */
import { formatProductDisplay, mapOFFCategory, parseOpenFoodFactsJSON } from './barcodeProductMapper';

describe('parseOpenFoodFactsJSON', () => {
  it('parses a valid response', () => {
    const json = {
      status: 1,
      code: '3017620422003',
      product: {
        product_name_en: 'Nutella',
        brands: 'Ferrero',
        categories_tags: ['en:breakfasts', 'en:spreads'],
      },
    };
    const result = parseOpenFoodFactsJSON(json)!;
    expect(result.name).toBe('Nutella');
    expect(result.brand).toBe('Ferrero');
  });

  it('returns null when not found (status 0)', () => {
    expect(parseOpenFoodFactsJSON({ status: 0, code: '0' })).toBeNull();
  });

  it('falls back to product_name when *_en is empty', () => {
    const json = {
      status: 1,
      code: '456',
      product: { product_name_en: '', product_name: 'Lait', brands: 'X' },
    };
    expect(parseOpenFoodFactsJSON(json)!.name).toBe('Lait');
  });
});

describe('mapOFFCategory', () => {
  it.each<[string[], string]>([
    [['en:dairies'], 'Dairy'],
    [['en:fruits'], 'Produce'],
    [['en:meats'], 'Meat'],
    [[], 'Other'],
  ])('maps %j → %s', (tags, expected) => {
    expect(mapOFFCategory(tags)).toBe(expected);
  });
});

describe('formatProductDisplay', () => {
  it('prepends the brand', () => {
    expect(formatProductDisplay('Milk', 'Horizon')).toBe('Horizon Milk');
  });
  it('omits an empty brand', () => {
    expect(formatProductDisplay('Eggs', '')).toBe('Eggs');
  });
  it('does not duplicate a brand already in the name', () => {
    expect(formatProductDisplay('Horizon Milk', 'Horizon')).toBe('Horizon Milk');
  });
});
