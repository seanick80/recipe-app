/** Mirror of `TestFixtures/TestFuzzyMatcher.swift`. */
import { editDistance, groceryVocabulary, suggestCorrection } from './fuzzyMatcher';

describe('suggestCorrection', () => {
  const vocab = ['Milk', 'Bread', 'Eggs'];

  it('returns null for an exact match (case-insensitive)', () => {
    expect(suggestCorrection('Eggs', vocab)).toBeNull();
    expect(suggestCorrection('eggs', vocab)).toBeNull();
  });

  it('corrects single-character edits', () => {
    expect(suggestCorrection('Milz', vocab)).toBe('Milk'); // substitution
    expect(suggestCorrection('Egs', ['Eggs'])).toBe('Eggs'); // deletion
  });

  it('returns null when nothing is close enough', () => {
    expect(suggestCorrection('ABCDE', vocab)).toBeNull();
  });

  it('returns null for an empty vocabulary', () => {
    expect(suggestCorrection('Milk', [])).toBeNull();
  });
});

describe('editDistance', () => {
  it.each<[string, string, number]>([
    ['kitten', 'sitting', 3],
    ['', 'abc', 3],
    ['abc', 'abc', 0],
  ])('d(%s, %s) = %i', (a, b, d) => {
    expect(editDistance(a, b)).toBe(d);
  });
});

describe('groceryVocabulary', () => {
  it('has a substantial set and corrects against it', () => {
    const vocab = groceryVocabulary();
    expect(vocab.length).toBeGreaterThan(50);
    expect(suggestCorrection('Millk', vocab)).toBe('milk');
  });
});
