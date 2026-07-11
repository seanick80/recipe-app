/** Mirror of `TestFixtures/TestContentDetector.swift`. */
import { detectContentType } from './contentDetector';

describe('detectContentType', () => {
  it('detects a recipe with headers', () => {
    const recipe = ['Chocolate Cake', 'Ingredients', '2 cups flour', 'Instructions', 'Preheat oven to 350'].join('\n');
    expect(detectContentType(recipe)).toBe('recipe');
  });

  it('detects a shopping list', () => {
    expect(detectContentType('Shopping List\nMilk\nEggs\nBread')).toBe('shoppingList');
  });

  it('treats empty text as unknown', () => {
    expect(detectContentType('')).toBe('unknown');
  });

  it('lets a shopping marker override a weak recipe signal', () => {
    const ambiguous = 'Grocery List\nMilk\nEggs\nServes as breakfast staple';
    expect(detectContentType(ambiguous)).not.toBe('recipe');
  });
});
