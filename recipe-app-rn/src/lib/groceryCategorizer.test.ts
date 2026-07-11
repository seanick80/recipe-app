import { categorizeGroceryItem } from './groceryCategorizer';

// Ported 1:1 from TestFixtures/TestGroceryCategorizer.swift (31 assertions).

describe('categorizeGroceryItem', () => {
  describe('one representative per category', () => {
    it.each([
      ['apple', 'Produce'],
      ['milk', 'Dairy'],
      ['chicken', 'Meat'],
      ['bread', 'Bakery'],
      ['rice', 'Dry & Canned'],
      ['coffee', 'Beverages'],
      ['chips', 'Snacks'],
      ['ketchup', 'Condiments'],
      ['cumin', 'Spices'],
      ['soap', 'Household'],
      ['ice cream', 'Frozen'],
    ])('%s -> %s', (item, expected) => {
      expect(categorizeGroceryItem(item)).toBe(expected);
    });
  });

  describe('compound overrides', () => {
    it.each([
      ['chicken broth', 'Dry & Canned'],
      ['onion soup mix', 'Dry & Canned'],
      ['cake mix', 'Dry & Canned'],
    ])('%s -> %s', (item, expected) => {
      expect(categorizeGroceryItem(item)).toBe(expected);
    });
  });

  describe('multi-word and spices', () => {
    it.each([
      ['bell pepper', 'Produce'],
      ['cream cheese', 'Dairy'],
      ['ground beef', 'Meat'],
      ['peanut butter', 'Dry & Canned'],
      ['garam masala', 'Spices'],
      ['chili powder', 'Spices'],
      ['vanilla extract', 'Spices'],
    ])('%s -> %s', (item, expected) => {
      expect(categorizeGroceryItem(item)).toBe(expected);
    });
  });

  describe('category priority', () => {
    it('garlic outranks clove', () => {
      expect(categorizeGroceryItem('cloves garlic minced')).toBe('Produce');
    });
    it('chicken multi-word match', () => {
      expect(categorizeGroceryItem('chicken thighs')).toBe('Meat');
    });
  });

  describe('baking and dry & canned', () => {
    it.each([
      ['baking powder', 'Dry & Canned'],
      ['flour', 'Dry & Canned'],
      ['cornstarch', 'Dry & Canned'],
      ['Granulated Sugar Or Honey', 'Dry & Canned'],
    ])('%s -> %s', (item, expected) => {
      expect(categorizeGroceryItem(item)).toBe(expected);
    });
  });

  describe('edge cases', () => {
    it('trims whitespace', () => {
      expect(categorizeGroceryItem('  Milk  ')).toBe('Dairy');
    });
    it('handles all caps', () => {
      expect(categorizeGroceryItem('CHICKEN')).toBe('Meat');
    });
    it('empty -> Other', () => {
      expect(categorizeGroceryItem('')).toBe('Other');
    });
    it('build67 regression (embedded size/weight)', () => {
      expect(categorizeGroceryItem('16-Oz (450G) Tomato Sauce')).toBe('Dry & Canned');
    });
  });
});
