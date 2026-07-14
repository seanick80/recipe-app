import { formatIngredient, parsedRecipeToImported, runOCRPipeline } from './ocrPipeline';
import { makeOCRLine, type NormalizedBox, type OCRLine } from './qualityGate';

/** Builds a good-confidence OCR line with a plausible mid-page box. */
function line(text: string, y = 0.5, confidence = 0.9): OCRLine {
  const box: NormalizedBox = { x: 0.2, y, width: 0.5, height: 0.03 };
  return makeOCRLine(text, confidence, box);
}

describe('formatIngredient', () => {
  it('renders quantity + unit + name', () => {
    expect(formatIngredient({ name: 'flour', quantity: 2, unit: 'cups' })).toBe('2 cups flour');
  });

  it('renders quantity + name when there is no unit', () => {
    expect(formatIngredient({ name: 'eggs', quantity: 3, unit: '' })).toBe('3 eggs');
  });

  it('drops a redundant leading 1 when there is no unit', () => {
    expect(formatIngredient({ name: 'salt', quantity: 1, unit: '' })).toBe('salt');
  });

  it('keeps a quantity of 1 when there is a unit', () => {
    expect(formatIngredient({ name: 'milk', quantity: 1, unit: 'cup' })).toBe('1 cup milk');
  });
});

describe('parsedRecipeToImported', () => {
  it('maps fields and stringifies ingredients', () => {
    const imported = parsedRecipeToImported({
      title: 'Pancakes',
      ingredients: [
        { name: 'flour', quantity: 2, unit: 'cups' },
        { name: 'eggs', quantity: 3, unit: '' },
      ],
      instructions: ['Mix everything', 'Cook on a griddle'],
      servings: 4,
      prepTimeMinutes: 10,
      cookTimeMinutes: 15,
    });
    expect(imported.title).toBe('Pancakes');
    expect(imported.ingredients).toEqual(['2 cups flour', '3 eggs']);
    expect(imported.instructions).toEqual(['Mix everything', 'Cook on a griddle']);
    expect(imported.servings).toBe(4);
    expect(imported.prepTimeMinutes).toBe(10);
    expect(imported.cookTimeMinutes).toBe(15);
    // Photo scans carry no web-source metadata.
    expect(imported.sourceURL).toBe('');
    expect(imported.imageURL).toBe('');
    expect(imported.ingredientNormalizations).toEqual([]);
  });
});

describe('runOCRPipeline', () => {
  it('routes a recipe (section headers present) to the recipe path', () => {
    const lines = [
      line('Banana Pancakes', 0.95),
      line('Serves 4', 0.9),
      line('Ingredients', 0.9),
      line('2 cups flour', 0.9),
      line('3 eggs', 0.9),
      line('Instructions', 0.9),
      line('Mash the bananas', 0.9),
      line('Cook on a hot griddle', 0.9),
    ];
    const result = runOCRPipeline(lines);
    expect(result.detected).toBe('recipe');
    expect(result.kind).toBe('recipe');
    if (result.kind !== 'recipe') throw new Error('expected recipe');
    expect(result.recipe.title).toBe('Banana Pancakes');
    expect(result.recipe.servings).toBe(4);
    expect(result.recipe.ingredients.length).toBeGreaterThanOrEqual(2);
    expect(result.recipe.instructions.length).toBeGreaterThanOrEqual(1);
    expect(result.quality.isAcceptable).toBe(true);
  });

  it('routes a shopping list (shopping marker present) to the shopping path', () => {
    const lines = [
      line('Shopping List', 0.95),
      line('2 apples', 0.9),
      line('1 loaf bread', 0.9),
      line('milk', 0.9),
    ];
    const result = runOCRPipeline(lines);
    expect(result.detected).toBe('shoppingList');
    expect(result.kind).toBe('shoppingList');
    if (result.kind !== 'shoppingList') throw new Error('expected shoppingList');
    expect(result.items.length).toBeGreaterThanOrEqual(3);
    expect(result.items.map((i) => i.name)).toEqual(expect.arrayContaining(['milk']));
  });

  it('defaults unknown content to the recipe path', () => {
    const lines = [line('Some random note', 0.9), line('nothing structured here', 0.9)];
    const result = runOCRPipeline(lines);
    expect(result.detected).toBe('unknown');
    expect(result.kind).toBe('recipe');
  });

  it('flags an empty capture as poor quality / retake', () => {
    const result = runOCRPipeline([]);
    expect(result.quality.shouldRetake).toBe(true);
    expect(result.quality.isAcceptable).toBe(false);
  });

  it('flags a low-confidence capture as retake but still returns a result', () => {
    const lines = [
      line('blurry title', 0.9, 0.2),
      line('ingredients', 0.8, 0.2),
      line('mush', 0.7, 0.1),
      line('method', 0.6, 0.2),
    ];
    const result = runOCRPipeline(lines);
    expect(result.quality.shouldRetake).toBe(true);
    // Still routed (the UI decides whether to honor the retake hint).
    expect(result.kind).toBeDefined();
  });
});
