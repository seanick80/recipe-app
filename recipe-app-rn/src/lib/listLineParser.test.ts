/** Mirror of `TestFixtures/TestListParser.swift`. */
import { parseListLine, parseQuantityToken, parseShoppingListText } from './listLineParser';

// testParseBasicVariants — (input, expectedQty, expectedUnit, expectedName)
describe('parseListLine — basic variants', () => {
  it.each<[string, number, string, string]>([
    ['milk', 1, '', 'milk'],
    ['2 bananas', 2, '', 'bananas'],
    ['2 cans tomatoes', 2, 'can', 'tomatoes'],
    ['1 lb chicken breast', 1, 'lb', 'chicken breast'],
    ['1/2 lb ground beef', 0.5, 'lb', 'ground beef'],
    ['2 pounds chicken', 2, 'lb', 'chicken'],
    ['500 g chicken breast', 500, 'g', 'chicken breast'],
    ['250 ml milk', 250, 'ml', 'milk'],
  ])('%s → qty=%f unit=%s name=%s', (input, qty, unit, name) => {
    const r = parseListLine(input)!;
    expect(r.quantity).toBe(qty);
    expect(r.unit).toBe(unit);
    expect(r.name).toBe(name);
  });
});

// testParseSpecialPrefixes
describe('parseListLine — special prefixes', () => {
  it('parses a multiplier suffix', () => {
    expect(parseListLine('milk x3')!.quantity).toBe(3);
  });
  it('parses an x prefix', () => {
    expect(parseListLine('2x eggs')!.quantity).toBe(2);
  });
  it('strips a bullet dash', () => {
    expect(parseListLine('- eggs')!.name).toBe('eggs');
  });
  it('strips a bullet dot', () => {
    expect(parseListLine('\u{2022} bread')!.name).toBe('bread');
  });
  it('strips an unchecked checkbox', () => {
    expect(parseListLine('[] bread')!.name).toBe('bread');
  });
  it('strips a checked checkbox', () => {
    expect(parseListLine('[x] milk')!.name).toBe('milk');
  });
  it('parses a numbered list', () => {
    expect(parseListLine('3. bananas')!.name).toBe('bananas');
  });
});

// testParseNilCases
describe('parseListLine — nil cases', () => {
  it('returns null for a blank line', () => {
    expect(parseListLine('')).toBeNull();
  });
  it('returns null for whitespace', () => {
    expect(parseListLine('   ')).toBeNull();
  });
  it('returns null for a category header', () => {
    expect(parseListLine('DAIRY')).toBeNull();
  });
});

// testParseMultiLineText
describe('parseShoppingListText', () => {
  it('parses a multi-line list, skipping blanks and headers', () => {
    const text = 'milk\n2 cans tomatoes\n- eggs\n3 lb chicken breast\n\nDAIRY\ncheese';
    const items = parseShoppingListText(text);
    expect(items.length).toBe(5);
    expect(items[1].unit).toBe('can');
  });
});

// testParseFusedUnits
describe('parseListLine — fused units', () => {
  it.each<[string, number, string]>([
    ['150g flour', 150, 'g'],
    ['60ml vegetable oil', 60, 'ml'],
    ['8oz cream cheese', 8, 'oz'],
    ['150g (1 cup) White Self Raising Flour, sifted', 150, 'g'],
    ['375g, zucchini, grated', 375, 'g'],
  ])('%s → qty=%f unit=%s', (input, qty, unit) => {
    const r = parseListLine(input)!;
    expect(r.quantity).toBe(qty);
    expect(r.unit).toBe(unit);
  });

  it('treats space-separated g as a unit', () => {
    expect(parseListLine('2 g sugar')!.unit).toBe('g');
  });
  it.each<[string, number, string, string]>([
    ['2 Tbsp. butter', 2, 'tbsp', 'butter'],
    ['1 tsp. salt', 1, 'tsp', 'salt'],
    ['2 tbsp. unsalted butter', 2, 'tbsp', 'unsalted butter'],
    ['1 TSP. salt', 1, 'tsp', 'salt'],
  ])('strips trailing punctuation off a dotted unit: %s', (input, qty, unit, name) => {
    const r = parseListLine(input)!;
    expect(r.quantity).toBe(qty);
    expect(r.unit).toBe(unit);
    expect(r.name).toBe(name);
  });
  it('canonicalizes the word "grams" to g', () => {
    expect(parseListLine('grams of truth')!.unit).toBe('g');
  });
});

// testCompoundFractions
describe('parseListLine — compound fractions', () => {
  it.each<[string, number, string]>([
    ['1 1/2 cups flour', 1.5, 'cup'],
    ['1 and 1/2 cups flour', 1.5, 'cup'],
    ['1\u{00BD} tbsp sugar', 1.5, 'tbsp'],
    ['2\u{00BC} cups all-purpose flour', 2.25, 'cup'],
  ])('%s → qty=%f unit=%s', (input, qty, unit) => {
    const r = parseListLine(input)!;
    expect(r.quantity).toBe(qty);
    expect(r.unit).toBe(unit);
  });
});

// testTrailingPunctuation
describe('parseListLine — trailing punctuation', () => {
  it('strips a trailing comma', () => {
    expect(parseListLine('bread,')!.name).toBe('bread');
  });
  it('strips a trailing period', () => {
    expect(parseListLine('eggs.')!.name).toBe('eggs');
  });
});

// testUnicodeFraction
describe('parseQuantityToken', () => {
  it('parses a bare unicode 1/2', () => {
    expect(parseQuantityToken('\u{00BD}')).toBe(0.5);
  });
});
