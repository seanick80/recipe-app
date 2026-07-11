/**
 * Fuzzy matching for post-OCR correction of handwritten list misreads. Uses
 * Levenshtein edit distance to suggest corrections from a known vocabulary. 1:1
 * port of `SharedLogic/FuzzyMatcher.swift` (framework-free).
 */

/**
 * Suggest a correction for a possibly-garbled OCR token: the best vocabulary
 * word within edit distance ≤2, ties broken toward shorter words. Returns null
 * for an exact (case-insensitive) match or when nothing is close enough.
 */
export function suggestCorrection(input: string, vocabulary: string[]): string | null {
  const lower = input.toLowerCase();

  for (const word of vocabulary) {
    if (lower === word.toLowerCase()) return null;
  }

  let bestMatch: string | null = null;
  let bestDistance = Number.MAX_SAFE_INTEGER;

  for (const word of vocabulary) {
    const dist = editDistance(lower, word.toLowerCase());
    if (dist > 0 && dist <= 2 && dist < bestDistance) {
      bestDistance = dist;
      bestMatch = word;
    } else if (dist === bestDistance && dist <= 2) {
      // Tie-break: prefer shorter words (more common grocery items).
      if (bestMatch !== null && word.length < bestMatch.length) bestMatch = word;
    }
  }

  return bestMatch;
}

/** Levenshtein edit distance (single-row DP), matching the Swift implementation. */
export function editDistance(a: string, b: string): number {
  const aChars = [...a];
  const bChars = [...b];
  const m = aChars.length;
  const n = bChars.length;
  if (m === 0) return n;
  if (n === 0) return m;

  let prev = Array.from({ length: n + 1 }, (_, i) => i);
  let curr = new Array<number>(n + 1).fill(0);

  for (let i = 1; i <= m; i++) {
    curr[0] = i;
    for (let j = 1; j <= n; j++) {
      if (aChars[i - 1] === bChars[j - 1]) {
        curr[j] = prev[j - 1];
      } else {
        curr[j] = 1 + Math.min(prev[j], curr[j - 1], prev[j - 1]);
      }
    }
    [prev, curr] = [curr, prev];
  }
  return prev[n];
}

/** Common grocery items for fuzzy matching (mirrors the Swift vocabulary list). */
export function groceryVocabulary(): string[] {
  return [
    // Produce
    'apple', 'apricot', 'artichoke', 'arugula', 'asparagus',
    'avocado', 'banana', 'basil', 'beet', 'blueberry', 'blackberry',
    'raspberry', 'strawberry', 'cranberry', 'broccoli', 'cabbage',
    'cantaloupe', 'carrot', 'cauliflower', 'celery', 'cherry',
    'cilantro', 'clementine', 'coconut', 'corn', 'cucumber',
    'dill', 'eggplant', 'fennel', 'fig', 'garlic', 'ginger',
    'grape', 'grapefruit', 'kale', 'kiwi', 'leek', 'lemon',
    'lettuce', 'lime', 'mango', 'melon', 'mint', 'mushroom',
    'nectarine', 'okra', 'onion', 'orange', 'parsley', 'parsnip',
    'peach', 'pear', 'pea', 'pepper', 'pineapple', 'plum',
    'pomegranate', 'potato', 'pumpkin', 'radish', 'rosemary',
    'sage', 'scallion', 'shallot', 'spinach', 'squash',
    'thyme', 'tomato', 'turnip', 'watermelon', 'yam', 'zucchini',
    // Dairy
    'milk', 'cheese', 'yogurt', 'butter', 'cream', 'eggs', 'egg',
    'buttermilk', 'ghee', 'mozzarella', 'parmesan', 'ricotta',
    'cheddar', 'feta', 'margarine',
    // Meat
    'chicken', 'beef', 'pork', 'fish', 'salmon', 'shrimp',
    'bacon', 'sausage', 'turkey', 'lamb', 'ham', 'steak',
    'tuna', 'cod', 'tilapia', 'crab', 'lobster',
    // Bakery
    'bread', 'bagel', 'muffin', 'roll', 'croissant', 'tortilla',
    'bun', 'pita', 'naan', 'cake', 'pie',
    // Dry & Canned
    'rice', 'pasta', 'noodle', 'spaghetti', 'flour', 'sugar',
    'salt', 'oil', 'cereal', 'oatmeal', 'granola', 'beans',
    'lentils', 'chickpea', 'honey', 'syrup', 'vinegar',
    'vanilla', 'yeast',
    // Snacks
    'chips', 'cookies', 'crackers', 'candy', 'chocolate',
    'nuts', 'almonds', 'popcorn',
    // Beverages
    'water', 'juice', 'soda', 'coffee', 'tea', 'beer', 'wine',
    // Condiments & Sauces
    'gravy', 'ketchup', 'mustard', 'mayo', 'relish', 'sriracha',
    'hummus', 'pesto', 'salsa',
    // Spices
    'cumin', 'paprika', 'turmeric', 'cinnamon', 'nutmeg',
    'cardamom', 'cayenne', 'curry', 'oregano', 'saffron',
    // Household
    'soap', 'detergent', 'napkins', 'towels', 'tissues',
  ];
}
