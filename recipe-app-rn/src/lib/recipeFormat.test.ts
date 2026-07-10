import {
  formatIngredient,
  formatQuantity,
  isHttpUrl,
  parseTags,
  sortedIngredients,
  totalTimeMinutes,
} from './recipeFormat';
import type { Ingredient } from '../types/recipe';

function ingredient(overrides: Partial<Ingredient> = {}): Ingredient {
  return {
    id: 'i1',
    name: 'flour',
    quantity: 2,
    unit: 'cup',
    category: 'baking',
    display_order: 0,
    notes: '',
    ...overrides,
  };
}

describe('totalTimeMinutes', () => {
  it('sums prep and cook time', () => {
    expect(totalTimeMinutes({ prep_time_minutes: 10, cook_time_minutes: 25 })).toBe(35);
  });
});

describe('sortedIngredients', () => {
  it('orders by display_order ascending', () => {
    const list = [
      ingredient({ id: 'c', display_order: 2 }),
      ingredient({ id: 'a', display_order: 0 }),
      ingredient({ id: 'b', display_order: 1 }),
    ];
    expect(sortedIngredients(list).map((i) => i.id)).toEqual(['a', 'b', 'c']);
  });

  it('is stable for equal display_order and does not mutate the input', () => {
    const list = [
      ingredient({ id: 'x', display_order: 0 }),
      ingredient({ id: 'y', display_order: 0 }),
    ];
    expect(sortedIngredients(list).map((i) => i.id)).toEqual(['x', 'y']);
    expect(list.map((i) => i.id)).toEqual(['x', 'y']);
  });
});

describe('formatQuantity', () => {
  it.each([
    [2, '2'],
    [1.5, '1.5'],
    [0.25, '0.25'],
    [2.0, '2'],
    [1.333, '1.33'],
  ])('%s → %s', (input, expected) => {
    expect(formatQuantity(input)).toBe(expected);
  });
});

describe('formatIngredient', () => {
  it('formats quantity, unit, name', () => {
    expect(formatIngredient(ingredient({ quantity: 2, unit: 'cup', name: 'flour' }))).toBe(
      '2 cup flour',
    );
  });

  it('appends notes in parentheses', () => {
    expect(formatIngredient(ingredient({ name: 'onion', notes: 'diced' }))).toBe(
      '2 cup onion (diced)',
    );
  });

  it('omits quantity when zero and unit when empty', () => {
    expect(formatIngredient(ingredient({ quantity: 0, unit: '', name: 'salt' }))).toBe('salt');
    expect(formatIngredient(ingredient({ quantity: 3, unit: '', name: 'eggs' }))).toBe('3 eggs');
  });
});

describe('parseTags', () => {
  it('splits, trims, and drops empties', () => {
    expect(parseTags('vegan, quick ,, weeknight')).toEqual(['vegan', 'quick', 'weeknight']);
  });

  it('returns [] for an empty string', () => {
    expect(parseTags('')).toEqual([]);
  });
});

describe('isHttpUrl', () => {
  it.each([
    ['https://example.com', true],
    ['http://example.com', true],
    ['  https://example.com  ', true],
    ['ftp://example.com', false],
    ['just text', false],
    ['', false],
  ])('%s → %s', (input, expected) => {
    expect(isHttpUrl(input)).toBe(expected);
  });
});
