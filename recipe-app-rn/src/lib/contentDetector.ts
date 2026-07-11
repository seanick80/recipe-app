/**
 * Detects whether OCR text is a shopping list or a recipe, so the scan pipeline
 * can warn users who photograph a recipe from the shopping-list scanner. 1:1
 * port of `SharedLogic/ContentDetector.swift` (framework-free).
 */

export type ContentType = 'shoppingList' | 'recipe' | 'unknown';

/** Recipe marker keywords — ≥2 distinct hits ⇒ probably a recipe. */
const recipeMarkers: string[] = [
  'ingredients', 'ingredient list', 'what you need', "what you'll need",
  'method', 'directions', 'instructions', 'preparation', 'procedure',
  'steps', 'how to make',
  'preheat', 'preheat oven', 'bake at', 'cook for', 'simmer',
  'prep time', 'cook time', 'total time', 'servings', 'serves',
  'yield', 'makes', 'minutes', 'degrees',
];

/** Shopping-list markers. */
const shoppingMarkers: string[] = ['grocery', 'shopping list', 'to buy', 'need to get'];

/**
 * Detect the content type of OCR text. Scores recipe markers (section headers,
 * cooking verbs, time references) + a "step N" pattern; a strong shopping signal
 * biases toward a shopping list unless recipe markers are overwhelming (≥3).
 */
export function detectContentType(text: string): ContentType {
  const lower = text.toLowerCase();

  let recipeHits = 0;
  const matched = new Set<string>();
  for (const marker of recipeMarkers) {
    if (lower.includes(marker) && !matched.has(marker)) {
      matched.add(marker);
      recipeHits += 1;
    }
  }
  if (/step\s+\d/.test(lower)) recipeHits += 1;

  let shoppingHits = 0;
  for (const marker of shoppingMarkers) {
    if (lower.includes(marker)) shoppingHits += 1;
  }

  if (shoppingHits > 0 && recipeHits < 3) return 'shoppingList';
  if (recipeHits >= 2) return 'recipe';
  return 'unknown';
}
