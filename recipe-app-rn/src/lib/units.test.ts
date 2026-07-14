import { isCustomUnit, RECIPE_UNITS, SHOPPING_UNITS, unitsFor } from './units';

describe('units', () => {
  it('recipe list mirrors the Swift recipeUnits (leading none)', () => {
    expect(RECIPE_UNITS[0]).toBe('');
    expect(RECIPE_UNITS).toContain('tsp');
    expect(RECIPE_UNITS).toContain('clove');
    expect(RECIPE_UNITS).toContain('bottle');
  });

  it('shopping list mirrors the Swift shoppingUnits (leading none)', () => {
    expect(SHOPPING_UNITS[0]).toBe('');
    expect(SHOPPING_UNITS).toContain('dozen');
    expect(SHOPPING_UNITS).toContain('carton');
    expect(SHOPPING_UNITS).toContain('case');
  });

  it('has no duplicate entries', () => {
    expect(new Set(RECIPE_UNITS).size).toBe(RECIPE_UNITS.length);
    expect(new Set(SHOPPING_UNITS).size).toBe(SHOPPING_UNITS.length);
  });

  it('unitsFor selects the list by context', () => {
    expect(unitsFor('recipe')).toBe(RECIPE_UNITS);
    expect(unitsFor('shopping')).toBe(SHOPPING_UNITS);
  });

  describe('isCustomUnit', () => {
    it('is false for the empty (none) unit', () => {
      expect(isCustomUnit('', 'recipe')).toBe(false);
      expect(isCustomUnit('   ', 'recipe')).toBe(false);
    });

    it('is false for a preset unit', () => {
      expect(isCustomUnit('tsp', 'recipe')).toBe(false);
      expect(isCustomUnit('dozen', 'shopping')).toBe(false);
    });

    it('is true for a value outside the preset list', () => {
      expect(isCustomUnit('sackful', 'recipe')).toBe(true);
      // "clove" is a recipe unit but not a shopping unit → custom for shopping.
      expect(isCustomUnit('clove', 'shopping')).toBe(true);
    });
  });
});
