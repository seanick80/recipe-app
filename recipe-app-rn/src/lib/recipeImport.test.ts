import { fetchAndParseRecipe, importedRecipeToDraft } from './recipeImport';
import type { ImportedRecipe } from './recipeSchemaParser';

/** A minimal `Response`-like stub carrying HTML text. */
function htmlResponse(status: number, html: string): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    text: async () => html,
  } as unknown as Response;
}

const recipeHTML = `
  <html><head>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Recipe",
    "name": "Weeknight Bolognese",
    "recipeIngredient": [
      "1 lb ground beef",
      "2 cups tomato sauce",
      "3 cloves garlic",
      "500g spaghetti"
    ],
    "recipeInstructions": [
      {"@type": "HowToStep", "text": "Brown the beef."},
      {"@type": "HowToStep", "text": "Add the sauce and simmer."},
      {"@type": "HowToStep", "text": "Toss with the pasta."}
    ],
    "recipeYield": "4 servings",
    "prepTime": "PT10M",
    "cookTime": "PT30M",
    "recipeCuisine": "Italian",
    "recipeCategory": "Dinner"
  }
  </script>
  </head><body></body></html>
`;

describe('fetchAndParseRecipe', () => {
  it('fetches and parses a recipe from valid HTML', async () => {
    const fetchMock = jest.fn().mockResolvedValueOnce(htmlResponse(200, recipeHTML));
    const result = await fetchAndParseRecipe('https://example.com/bolognese', fetchMock as unknown as typeof fetch);

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe('https://example.com/bolognese');
    expect(result.success).toBe(true);
    if (result.success) {
      expect(result.recipe.title).toBe('Weeknight Bolognese');
      expect(result.recipe.ingredients).toHaveLength(4);
      expect(result.recipe.sourceURL).toBe('https://example.com/bolognese');
    }
  });

  it('rejects a URL that is empty or not http(s)', async () => {
    const fetchMock = jest.fn();
    const result = await fetchAndParseRecipe('   ', fetchMock as unknown as typeof fetch);
    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.kind).toBe('invalidURL');
      expect(result.message.length).toBeGreaterThan(0);
    }
  });

  it('folds a network failure into a failure result (never throws)', async () => {
    const fetchMock = jest.fn().mockRejectedValueOnce(new Error('offline'));
    const result = await fetchAndParseRecipe('https://example.com/x', fetchMock as unknown as typeof fetch);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.kind).toBe('network');
      expect(result.message).toMatch(/reach/i);
    }
  });

  it('folds a non-2xx HTTP status into a failure result', async () => {
    const fetchMock = jest.fn().mockResolvedValueOnce(htmlResponse(404, ''));
    const result = await fetchAndParseRecipe('https://example.com/missing', fetchMock as unknown as typeof fetch);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error).toEqual({ kind: 'http', status: 404 });
      expect(result.message).toMatch(/404/);
    }
  });

  it('reports a parse failure when the page has no recipe', async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce(htmlResponse(200, '<html><body><p>Just an article.</p></body></html>'));
    const result = await fetchAndParseRecipe('https://example.com/article', fetchMock as unknown as typeof fetch);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.kind).toBe('parse');
      if (result.error.kind === 'parse') {
        expect(result.error.error).toBe('noRecipeFound');
      }
    }
  });
});

describe('importedRecipeToDraft', () => {
  const imported: ImportedRecipe = {
    title: 'Weeknight Bolognese',
    ingredients: ['1 lb ground beef', '2 cups tomato sauce', '3 cloves garlic', '500g spaghetti'],
    instructions: ['Brown the beef.', 'Add the sauce and simmer.', 'Toss with the pasta.'],
    servings: 4,
    prepTimeMinutes: 10,
    cookTimeMinutes: 30,
    totalTimeMinutes: 40,
    cuisine: 'Italian',
    course: 'Dinner',
    sourceURL: 'https://example.com/bolognese',
    imageURL: '',
    ingredientNormalizations: [],
  };

  it('maps scalar fields onto the create payload', () => {
    const draft = importedRecipeToDraft(imported);
    expect(draft.name).toBe('Weeknight Bolognese');
    expect(draft.servings).toBe(4);
    expect(draft.prep_time_minutes).toBe(10);
    expect(draft.cook_time_minutes).toBe(30);
    expect(draft.cuisine).toBe('Italian');
    expect(draft.course).toBe('Dinner');
    expect(draft.source_url).toBe('https://example.com/bolognese');
  });

  it('joins instructions into one numbered block', () => {
    const draft = importedRecipeToDraft(imported);
    expect(draft.instructions).toBe(
      '1. Brown the beef.\n\n2. Add the sauce and simmer.\n\n3. Toss with the pasta.',
    );
  });

  it('parses each ingredient string into structured qty/unit/name + category, preserving order', () => {
    const draft = importedRecipeToDraft(imported);
    expect(draft.ingredients.map((i) => i.name)).toEqual([
      'ground beef',
      'tomato sauce',
      'cloves garlic',
      'spaghetti',
    ]);
    // "1 lb ground beef" → qty 1, unit lb, Meat
    expect(draft.ingredients[0]).toMatchObject({
      name: 'ground beef',
      quantity: 1,
      unit: 'lb',
      category: 'Meat',
      display_order: 0,
    });
    // "2 cups tomato sauce" → qty 2, unit cup, Dry & Canned
    expect(draft.ingredients[1]).toMatchObject({ quantity: 2, unit: 'cup', display_order: 1 });
    // "3 cloves garlic" → qty 3, no known unit; garlic outranks clove → Produce
    expect(draft.ingredients[2]).toMatchObject({
      name: 'cloves garlic',
      quantity: 3,
      unit: '',
      category: 'Produce',
      display_order: 2,
    });
    // "500g spaghetti" → fused qty/unit → 500 g, Dry & Canned
    expect(draft.ingredients[3]).toMatchObject({
      name: 'spaghetti',
      quantity: 500,
      unit: 'g',
      category: 'Dry & Canned',
      display_order: 3,
    });
  });

  it('applies Swift-style defaults when optional fields are null', () => {
    const sparse: ImportedRecipe = {
      ...imported,
      servings: null,
      prepTimeMinutes: null,
      cookTimeMinutes: null,
      instructions: [],
      ingredients: ['salt'],
    };
    const draft = importedRecipeToDraft(sparse);
    expect(draft.servings).toBe(1);
    expect(draft.prep_time_minutes).toBe(0);
    expect(draft.cook_time_minutes).toBe(0);
    expect(draft.instructions).toBe('');
    // Unparseable/plain ingredient falls back to the raw name, quantity 1.
    expect(draft.ingredients[0]).toMatchObject({ name: 'salt', quantity: 1, unit: '' });
  });
});
