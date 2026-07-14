/** Mirror of `TestFixtures/TestRecipeSchemaParser.swift`. */
import {
  cleanIngredientText,
  collapseDoubleParens,
  collapseWhitespace,
  decodeHTMLEntities,
  ImportedRecipe,
  parseDuration,
  parseRecipeFromHTML,
  removeEmptyParens,
  stripDualUnits,
  stripHTMLTags,
  stripLeadingCommaInParens,
} from './recipeSchemaParser';

describe('testJSONLDParsingVariants', () => {
  // Standard JSON-LD with all fields
  const html = `
    <html><head>
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "Recipe",
      "name": "Classic Chocolate Chip Cookies",
      "recipeIngredient": [
        "2 1/4 cups all-purpose flour",
        "1 cup butter, softened",
        "3/4 cup sugar",
        "2 large eggs"
      ],
      "recipeInstructions": [
        {"@type": "HowToStep", "text": "Preheat oven to 375°F."},
        {"@type": "HowToStep", "text": "Mix flour, baking soda, and salt."},
        {"@type": "HowToStep", "text": "Bake for 9 to 11 minutes."}
      ],
      "recipeYield": "4 dozen",
      "prepTime": "PT15M",
      "cookTime": "PT11M",
      "totalTime": "PT26M",
      "recipeCuisine": "American",
      "recipeCategory": "Dessert",
      "image": "https://example.com/cookies.jpg"
    }
    </script>
    </head><body></body></html>
    `;
  const result = parseRecipeFromHTML(html, 'https://example.com/cookies');
  if (!result.success) throw new Error('JSON-LD parse should succeed');
  const recipe = result.recipe;

  it('title', () => expect(recipe.title).toBe('Classic Chocolate Chip Cookies'));
  it('ingredient count', () => expect(recipe.ingredients.length).toBe(4));
  it('instruction count', () => expect(recipe.instructions.length).toBe(3));
  it('servings', () => expect(recipe.servings).toBe(4));
  it('prep time', () => expect(recipe.prepTimeMinutes).toBe(15));
  it('cook time', () => expect(recipe.cookTimeMinutes).toBe(11));
  it('cuisine', () => expect(recipe.cuisine).toBe('American'));
  it('image URL', () => expect(recipe.imageURL).toBe('https://example.com/cookies.jpg'));
});

describe('testJSONLDStructuralVariants', () => {
  it('@graph: title', () => {
    const graphHTML = `
      <html><head>
      <script type="application/ld+json">
      {"@context":"https://schema.org","@graph":[
        {"@type":"WebPage","name":"Blog"},
        {"@type":"Recipe","name":"Garlic Bread",
         "recipeIngredient":["1 baguette","4 cloves garlic"],
         "recipeInstructions":"Slice bread. Spread butter. Bake."}
      ]}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(graphHTML);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.title).toBe('Garlic Bread');
  });

  it('Array JSON-LD: title', () => {
    const arrayHTML = `
      <html><head>
      <script type="application/ld+json">
      [{"@type":"WebSite","name":"Blog"},
       {"@type":"Recipe","name":"Salad","recipeIngredient":["lettuce","tomato"]}]
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(arrayHTML);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.title).toBe('Salad');
  });

  it('Multiple blocks: finds recipe in second', () => {
    const multiHTML = `
      <html><head>
      <script type="application/ld+json">{"@type":"WebSite","name":"Blog"}</script>
      <script type="application/ld+json">
      {"@type":"Recipe","name":"Found Second","recipeIngredient":["1 egg"]}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(multiHTML);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.title).toBe('Found Second');
  });

  it('Array @type: parsed', () => {
    const typeArrayHTML = `
      <html><head>
      <script type="application/ld+json">
      {"@type":["Recipe","HowTo"],"name":"Multi-Type","recipeIngredient":["1 cup rice"]}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(typeArrayHTML);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.title).toBe('Multi-Type');
  });
});

describe('testErrorCases', () => {
  it.each([
    ['', 'noHTML', 'Empty HTML'],
    ['   \n\t  ', 'noHTML', 'Whitespace HTML'],
    ['<html><body><h1>About</h1></body></html>', 'noRecipeFound', 'No recipe'],
  ])('%s -> %s (%s)', (html, expected) => {
    const r = parseRecipeFromHTML(html);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe(expected);
  });

  it('Article JSON-LD', () => {
    const articleHTML = `
      <html><head><script type="application/ld+json">
      {"@type":"Article","name":"NYC Restaurants"}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(articleHTML);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe('noRecipeFound');
  });

  it('Empty title', () => {
    const noTitleHTML = `
      <html><head><script type="application/ld+json">
      {"@type":"Recipe","name":"","recipeIngredient":["1 cup flour"]}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(noTitleHTML);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe('missingTitle');
  });

  it('No ingredients', () => {
    const noIngHTML = `
      <html><head><script type="application/ld+json">
      {"@type":"Recipe","name":"Mystery","recipeIngredient":[]}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(noIngHTML);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe('missingIngredients');
  });

  it('Malformed JSON', () => {
    const badJSON = `
      <html><head><script type="application/ld+json">
      { this is not valid json!!! }
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(badJSON);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe('noRecipeFound');
  });
});

describe('testHTMLHeuristicAndEntities', () => {
  it('Heuristic: title + ingredients', () => {
    const heuristicHTML = `
      <html><body><h1>Quick Pasta</h1>
      <ul><li>1 lb spaghetti</li><li>2 cups sauce</li></ul>
      </body></html>
      `;
    const r = parseRecipeFromHTML(heuristicHTML);
    expect(r.success).toBe(true);
    if (r.success) {
      expect(r.recipe.title).toBe('Quick Pasta');
      expect(r.recipe.ingredients.length).toBe(2);
    }
  });

  it('Non-recipe heuristic rejected', () => {
    const contactHTML = `
      <html><body><h1>Contact</h1>
      <ul><li>Email: a@b.com</li><li>Phone: 555</li></ul>
      </body></html>
      `;
    const r = parseRecipeFromHTML(contactHTML);
    expect(r.success).toBe(false);
    if (!r.success) expect(r.error).toBe('noRecipeFound');
  });

  it('Decode &amp;', () => expect(decodeHTMLEntities('Mac &amp; Cheese')).toBe('Mac & Cheese'));
  it('Decode &#39;', () => expect(decodeHTMLEntities('Bob&#39;s')).toBe("Bob's"));
  it('Strip HTML tags', () => expect(stripHTMLTags('<b>Bold</b> text')).toBe('Bold text'));
});

describe('testDualUnitStripping', () => {
  it.each([
    ['50 g / 3 1/2 tbsp butter', '3 1/2 tbsp butter', 'g -> tbsp'],
    ['500 ml / 2 cups water', '2 cups water', 'ml -> cups'],
    ['2.5 kg / 5 lb chicken', '5 lb chicken', 'decimal kg -> lb'],
    ['50 G / 3 tbsp butter', '3 tbsp butter', 'uppercase G'],
    ['2 cups flour', '2 cups flour', 'non-dual unchanged'],
    ['Salt and pepper', 'Salt and pepper', 'no quantity unchanged'],
  ])('Dual: %s -> %s', (input, expected) => {
    expect(stripDualUnits(input)).toBe(expected);
  });
});

describe('testIngredientTextCleaning', () => {
  it('Double parens collapsed', () => expect(collapseDoubleParens('milk ((full fat))')).toBe('milk (full fat)'));
  it('Leading comma stripped', () =>
    expect(stripLeadingCommaInParens('macaroni (, uncooked)')).toBe('macaroni (uncooked)'));
  it('Empty parens removed', () => expect(removeEmptyParens('flour () here')).toBe('flour here'));
  it('Whitespace collapsed', () => expect(collapseWhitespace('  flour   sifted  ')).toBe('flour sifted'));

  it('Full pipeline: dual + comma', () => {
    const r1 = cleanIngredientText('250 g / 2 1/2 cups elbow macaroni (, uncooked)');
    expect(r1.text).toBe('2 1/2 cups elbow macaroni (uncooked)');
  });
  it('Full pipeline: multiple normalizations', () => {
    const r1 = cleanIngredientText('250 g / 2 1/2 cups elbow macaroni (, uncooked)');
    expect(r1.normalizations.length).toBeGreaterThanOrEqual(2);
  });

  it('Already clean: no normalizations', () => {
    const r2 = cleanIngredientText('2 cups flour');
    expect(r2.normalizations.length).toBe(0);
  });

  it('Tracked: dual_units present', () => {
    const r3 = cleanIngredientText('50 g / 3 1/2 tbsp butter (, softened)');
    const types = r3.normalizations.map((n) => n.type);
    expect(types).toContain('dual_units');
  });
  it('Tracked: leading_comma present', () => {
    const r3 = cleanIngredientText('50 g / 3 1/2 tbsp butter (, softened)');
    const types = r3.normalizations.map((n) => n.type);
    expect(types).toContain('leading_comma_parens');
  });
});

describe('testDualUnitsInJSONLDImport', () => {
  const html = `
    <html><head><script type="application/ld+json">
    {"@type":"Recipe","name":"Mac",
     "recipeIngredient":["50 g / 3 tbsp butter (, softened)","2 cups flour"]}
    </script></head><body></body></html>
    `;
  const result = parseRecipeFromHTML(html);
  if (!result.success) throw new Error('JSON-LD dual unit should parse');
  const recipe = result.recipe;

  it('JSON-LD: cleaned', () => expect(recipe.ingredients[0]).toBe('3 tbsp butter (softened)'));
  it('JSON-LD: clean unchanged', () => expect(recipe.ingredients[1]).toBe('2 cups flour'));
  it('JSON-LD: normalizations populated', () => expect(recipe.ingredientNormalizations.length).toBeGreaterThan(0));
});

describe('testDurationParsing', () => {
  it.each([
    ['PT30M', 30, '30 minutes'],
    ['PT1H30M', 90, '1h30m'],
  ])('%s -> %s', (input, expected) => {
    expect(parseDuration(input as string)).toBe(expected);
  });

  it('0 minutes -> nil', () => expect(parseDuration('PT0M')).toBeNull());
  it('nil input', () => expect(parseDuration(null)).toBeNull());
});

describe('testServingsAndImageFormats', () => {
  it.each([
    ['"recipeYield": 6', 6],
    ['"recipeYield": "4 servings"', 4],
    ['"recipeYield": ["8"]', 8],
  ])('servings from %s', (fragment, expected) => {
    const html = `
      <html><head><script type="application/ld+json">
      {"@type":"Recipe","name":"T","recipeIngredient":["1 egg"],${fragment}}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(html);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.servings).toBe(expected);
  });

  it('Image object URL', () => {
    const imgHTML = `
      <html><head><script type="application/ld+json">
      {"@type":"Recipe","name":"T","recipeIngredient":["1 egg"],
       "image":{"@type":"ImageObject","url":"https://x.com/photo.jpg"}}
      </script></head><body></body></html>
      `;
    const r = parseRecipeFromHTML(imgHTML);
    expect(r.success).toBe(true);
    if (r.success) expect(r.recipe.imageURL).toBe('https://x.com/photo.jpg');
  });
});

describe('testImportedRecipeCodable', () => {
  // Swift checkCodableRoundTrip -> JSON.parse(JSON.stringify(...)) deep-equal.
  it('ImportedRecipe Codable round-trip', () => {
    const recipe: ImportedRecipe = {
      title: 'Test',
      ingredients: ['1 cup flour'],
      instructions: ['Mix well'],
      servings: 4,
      prepTimeMinutes: 10,
      cookTimeMinutes: 20,
      totalTimeMinutes: 30,
      cuisine: 'Italian',
      course: 'Dinner',
      sourceURL: 'https://example.com',
      imageURL: 'https://example.com/img.jpg',
      ingredientNormalizations: [],
    };
    expect(JSON.parse(JSON.stringify(recipe))).toEqual(recipe);
  });
});
