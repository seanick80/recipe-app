/** Mirror of `TestFixtures/TestOCR.swift`. */
import {
  cleanInstructionLine,
  parseIngredientLine,
  parseRecipeText,
  parseServings,
  parseTimeString,
  ParsedRecipe,
} from './ocrParser';

describe('parseRecipeText — full recipe', () => {
  it('extracts title, servings, prep time, ingredients, and instructions', () => {
    const text = [
      'Spaghetti Bolognese',
      'Serves 4',
      'Prep time: 15 min',
      'Cook time: 45 min',
      '',
      'Ingredients',
      '- 1 lb ground beef',
      '- 2 cans tomatoes',
      '- 1 box pasta',
      '- 3 cloves garlic',
      '',
      'Instructions',
      '1. Brown the ground beef in a large pan',
      '2. Add garlic and cook for 1 minute',
      '3. Add tomatoes and simmer for 30 minutes',
      '4. Cook pasta according to package directions',
    ].join('\n');
    const recipe = parseRecipeText(text);
    expect(recipe.title).toBe('Spaghetti Bolognese');
    expect(recipe.servings).toBe(4);
    expect(recipe.prepTimeMinutes).toBe(15);
    expect(recipe.ingredients.length).toBe(4);
    expect(recipe.ingredients[0].unit).toBe('lb');
    expect(recipe.instructions.length).toBe(4);
  });
});

describe('parseRecipeText — variants', () => {
  it('parses servings', () => {
    expect(parseServings('serves 4')).toBe(4);
    expect(parseServings('yield: 8')).toBe(8);
    expect(parseServings('something else')).toBeNull();
  });

  it('parses time strings', () => {
    expect(parseTimeString('20 min')).toBe(20);
    expect(parseTimeString('1h 30m')).toBe(90);
  });

  it('parses an ingredient line', () => {
    const ing = parseIngredientLine('2 cups flour')!;
    expect(ing.name).toBe('flour');
    expect(ing.unit).toBe('cup');
  });

  it('cleans instruction lines', () => {
    expect(cleanInstructionLine('1. Preheat oven')).toBe('Preheat oven');
    expect(cleanInstructionLine('Step 2: Mix')).toBe('Mix');
  });
});

describe('parseRecipeText — edge cases', () => {
  it('handles empty input', () => {
    const empty = parseRecipeText('');
    expect(empty.ingredients.length).toBe(0);
  });

  it('handles alternate headers', () => {
    const text = 'Quick Salad\nWhat you need\n- lettuce\n- tomato\nMethod\nChop vegetables';
    const recipe = parseRecipeText(text);
    expect(recipe.title).toBe('Quick Salad');
    expect(recipe.ingredients.length).toBe(2);
    expect(recipe.instructions.length).toBe(1);
  });
});

describe('ParsedRecipe round-trip', () => {
  // Swift's `checkCodableRoundTrip` uses JSONEncoder/JSONDecoder; the TS
  // equivalent is a JSON.parse(JSON.stringify(...)) deep-equal round-trip.
  it('survives a JSON round-trip', () => {
    const recipe: ParsedRecipe = {
      title: 'Test',
      ingredients: [{ name: 'flour', quantity: 2, unit: 'cup' }],
      instructions: ['Mix well'],
      servings: 4,
      prepTimeMinutes: 10,
      cookTimeMinutes: 20,
    };
    const roundTripped: ParsedRecipe = JSON.parse(JSON.stringify(recipe));
    expect(roundTripped).toEqual(recipe);
  });
});
