/**
 * Extracts a structured recipe from a web page's HTML by parsing JSON-LD
 * Schema.org Recipe markup, falling back to basic HTML/microdata heuristics.
 * Also cleans imported ingredient strings (dual units, stray parens, etc.).
 * 1:1 port of `SharedLogic/RecipeSchemaParser.swift` (framework-free).
 */

/** A normalization applied to an ingredient string during import cleaning. */
export type IngredientNormalization = {
  type: string; // e.g. "dual_units", "leading_comma_parens", "double_parens"
  original: string; // text before this normalization
  cleaned: string; // text after this normalization
};

/** Result of parsing a recipe from a web page's HTML. */
export type ImportedRecipe = {
  title: string;
  ingredients: string[];
  instructions: string[];
  servings: number | null;
  prepTimeMinutes: number | null;
  cookTimeMinutes: number | null;
  totalTimeMinutes: number | null;
  cuisine: string;
  course: string;
  sourceURL: string;
  imageURL: string;
  /**
   * Normalizations applied to ingredient strings during import cleaning.
   * Empty if all ingredients were already clean.
   */
  ingredientNormalizations: IngredientNormalization[];
};

/** Errors that can occur during recipe import. */
export type RecipeImportError = 'noRecipeFound' | 'noHTML' | 'missingTitle' | 'missingIngredients';

/** Result of `parseRecipeFromHTML` (mirrors Swift `Result<ImportedRecipe, RecipeImportError>`). */
export type ParseResult =
  | { success: true; recipe: ImportedRecipe }
  | { success: false; error: RecipeImportError };

/** Result of cleaning an ingredient string: the final text plus any normalizations applied. */
export type CleanedIngredient = {
  text: string;
  normalizations: IngredientNormalization[];
};

// MARK: - Foundation helpers

/** Trims Swift `.whitespaces` (space/tab) off both ends. */
function trimWhitespace(s: string): string {
  return s.replace(/^[ \t]+/, '').replace(/[ \t]+$/, '');
}

/** Case-insensitive `indexOf` (positions align because lowercasing preserves length). */
function indexOfCI(haystack: string, needle: string, from: number): number {
  return haystack.toLowerCase().indexOf(needle.toLowerCase(), from);
}

function isString(v: unknown): v is string {
  return typeof v === 'string';
}

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

function isStringArray(v: unknown): v is string[] {
  return Array.isArray(v) && v.every(isString);
}

function isDictArray(v: unknown): v is Record<string, unknown>[] {
  return Array.isArray(v) && v.every(isPlainObject);
}

// MARK: - Public entry point

/**
 * Extracts a structured recipe from HTML by parsing JSON-LD Schema.org Recipe markup.
 * Falls back to basic HTML heuristics if no structured data is present.
 */
export function parseRecipeFromHTML(html: string, sourceURL = ''): ParseResult {
  if (html.trim().length === 0) {
    return { success: false, error: 'noHTML' };
  }

  // Try JSON-LD first (covers ~80% of recipe sites)
  const jsonLD = extractJSONLDRecipe(html, sourceURL);
  if (jsonLD !== null) {
    return validate(jsonLD);
  }

  // Fallback: look for microdata or basic HTML structure
  const heuristic = extractFromHTMLHeuristic(html, sourceURL);
  if (heuristic !== null) {
    return validate(heuristic);
  }

  return { success: false, error: 'noRecipeFound' };
}

/** Validates that an imported recipe has the minimum required fields. */
function validate(recipe: ImportedRecipe): ParseResult {
  if (recipe.title.trim().length === 0) {
    return { success: false, error: 'missingTitle' };
  }
  if (recipe.ingredients.length === 0) {
    return { success: false, error: 'missingIngredients' };
  }
  return { success: true, recipe };
}

// MARK: - JSON-LD Extraction

/** Finds and parses `<script type="application/ld+json">` blocks containing Recipe schema. */
function extractJSONLDRecipe(html: string, sourceURL: string): ImportedRecipe | null {
  const blocks = extractJSONLDBlocks(html);
  for (const block of blocks) {
    const recipe = parseRecipeJSON(block, sourceURL);
    if (recipe !== null) {
      return recipe;
    }
  }
  return null;
}

/** Extracts all JSON-LD script block contents from HTML. */
export function extractJSONLDBlocks(html: string): string[] {
  const blocks: string[] = [];
  const tag = 'application/ld+json';
  let from = 0;

  for (;;) {
    const tagIdx = indexOfCI(html, tag, from);
    if (tagIdx < 0) break;
    // Find the closing > of the <script> tag
    const openEnd = html.indexOf('>', tagIdx + tag.length);
    if (openEnd < 0) break;
    // Find the closing </script>
    const closeIdx = indexOfCI(html, '</script>', openEnd + 1);
    if (closeIdx < 0) break;
    const jsonContent = html.slice(openEnd + 1, closeIdx).trim();
    if (jsonContent.length > 0) {
      blocks.push(jsonContent);
    }
    from = closeIdx + '</script>'.length;
  }
  return blocks;
}

/** Parses a JSON string as a Schema.org Recipe, handling both single objects and @graph arrays. */
export function parseRecipeJSON(json: string, sourceURL: string): ImportedRecipe | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(json);
  } catch {
    return null;
  }

  // Could be a single object or an array
  if (isPlainObject(parsed)) {
    return recipeFromDict(parsed, sourceURL);
  }
  if (isDictArray(parsed)) {
    for (const item of parsed) {
      const recipe = recipeFromDict(item, sourceURL);
      if (recipe !== null) {
        return recipe;
      }
    }
  }
  return null;
}

/** Converts a JSON dictionary to an ImportedRecipe if it represents a Schema.org Recipe. */
function recipeFromDict(dict: Record<string, unknown>, sourceURL: string): ImportedRecipe | null {
  // Check @graph pattern (common on WordPress sites)
  const graph = dict['@graph'];
  if (isDictArray(graph)) {
    for (const item of graph) {
      const recipe = recipeFromDict(item, sourceURL);
      if (recipe !== null) {
        return recipe;
      }
    }
    return null;
  }

  // Must be a Recipe type
  const typeValue = dict['@type'];
  let isRecipe: boolean;
  if (isString(typeValue)) {
    isRecipe = typeValue.toLowerCase() === 'recipe';
  } else if (isStringArray(typeValue)) {
    isRecipe = typeValue.some((t) => t.toLowerCase() === 'recipe');
  } else {
    isRecipe = false;
  }
  if (!isRecipe) return null;

  const title = isString(dict['name']) ? dict['name'] : '';
  const ingredients = extractStringArray(dict['recipeIngredient']);
  const instructions = extractInstructions(dict['recipeInstructions']);
  const servings = extractServings(dict['recipeYield']);
  const prepTime = parseDuration(asString(dict['prepTime']));
  const cookTime = parseDuration(asString(dict['cookTime']));
  const totalTime = parseDuration(asString(dict['totalTime']));
  const cuisine = extractFirstString(dict['recipeCuisine']);
  const course = extractFirstString(dict['recipeCategory']);
  const imageURL = extractImageURL(dict['image']);

  const allNormalizations: IngredientNormalization[] = [];
  const cleanedIngredients = ingredients.map((raw) => {
    const decoded = decodeHTMLEntities(raw);
    const result = cleanIngredientText(decoded);
    allNormalizations.push(...result.normalizations);
    return result.text;
  });

  return {
    title: decodeHTMLEntities(title),
    ingredients: cleanedIngredients,
    instructions: instructions.map((i) => decodeHTMLEntities(i)),
    servings,
    prepTimeMinutes: prepTime,
    cookTimeMinutes: cookTime,
    totalTimeMinutes: totalTime,
    cuisine,
    course,
    sourceURL,
    imageURL,
    ingredientNormalizations: allNormalizations,
  };
}

// MARK: - HTML Heuristic Fallback

/** Basic heuristic extraction when no JSON-LD is present. */
function extractFromHTMLHeuristic(html: string, sourceURL: string): ImportedRecipe | null {
  const title = extractHTMLTitle(html);
  if (title.length === 0) return null;

  // Look for ingredient-like list items
  const listItems = extractListItems(html);
  const ingredients = listItems.filter((item) => looksLikeIngredient(item));
  if (ingredients.length === 0) return null;

  const allNormalizations: IngredientNormalization[] = [];
  const cleanedIngredients = ingredients.map((raw) => {
    const result = cleanIngredientText(raw);
    allNormalizations.push(...result.normalizations);
    return result.text;
  });

  return {
    title,
    ingredients: cleanedIngredients,
    instructions: [],
    servings: null,
    prepTimeMinutes: null,
    cookTimeMinutes: null,
    totalTimeMinutes: null,
    cuisine: '',
    course: '',
    sourceURL,
    imageURL: '',
    ingredientNormalizations: allNormalizations,
  };
}

/** Extracts the page title from <title> or <h1>. */
function extractHTMLTitle(html: string): string {
  // Try <h1> first (more likely to be the recipe name)
  const h1 = extractTagContent(html, 'h1');
  if (h1 !== null) {
    return decodeHTMLEntities(stripHTMLTags(h1));
  }
  const title = extractTagContent(html, 'title');
  if (title !== null) {
    return decodeHTMLEntities(stripHTMLTags(title));
  }
  return '';
}

/** Extracts content between an opening and closing tag. */
function extractTagContent(html: string, tag: string): string | null {
  const openRe = new RegExp(`<${tag}[^>]*>`, 'i');
  const m = openRe.exec(html);
  if (m === null) return null;
  const openEnd = m.index + m[0].length;
  const closeIdx = indexOfCI(html, `</${tag}>`, openEnd);
  if (closeIdx < 0) return null;
  return html.slice(openEnd, closeIdx).trim();
}

/** Extracts text content from <li> elements. */
function extractListItems(html: string): string[] {
  const items: string[] = [];
  let search = 0;
  for (;;) {
    const openIdx = indexOfCI(html, '<li', search);
    if (openIdx < 0) break;
    const tagEnd = html.indexOf('>', openIdx + '<li'.length);
    if (tagEnd < 0) break;
    const closeIdx = indexOfCI(html, '</li>', tagEnd + 1);
    if (closeIdx < 0) break;
    const content = stripHTMLTags(html.slice(tagEnd + 1, closeIdx)).trim();
    if (content.length > 0) {
      items.push(content);
    }
    search = closeIdx + '</li>'.length;
  }
  return items;
}

/** Heuristic: does this string look like a recipe ingredient? */
function looksLikeIngredient(text: string): boolean {
  const lower = text.toLowerCase();
  // Must be short-ish (ingredients are typically < 100 chars)
  if (text.length > 120) return false;
  // Starts with a number or fraction
  const first = text[0];
  if (first !== undefined && ((first >= '0' && first <= '9') || first === '½' || first === '¼' || first === '¾')) {
    return true;
  }
  // Contains common measurement words
  const measurements = [
    'cup',
    'tablespoon',
    'teaspoon',
    'tbsp',
    'tsp',
    'oz',
    'ounce',
    'pound',
    'lb',
    'gram',
    'kg',
    'ml',
  ];
  for (const m of measurements) {
    if (lower.includes(m)) return true;
  }
  return false;
}

// MARK: - JSON Helper Extractors

/** Coerces to string or `undefined` (mirrors Swift `as? String`). */
function asString(value: unknown): string | undefined {
  return isString(value) ? value : undefined;
}

/** Extracts a string array from various JSON representations. */
function extractStringArray(value: unknown): string[] {
  if (isStringArray(value)) {
    return value.filter((s) => s.trim().length !== 0);
  }
  if (isString(value)) {
    return [value];
  }
  return [];
}

/** Extracts instructions from various Schema.org formats. */
function extractInstructions(value: unknown): string[] {
  if (isStringArray(value)) {
    return value.filter((s) => s.trim().length !== 0);
  }
  if (isString(value)) {
    // Could be HTML or plain text
    const cleaned = stripHTMLTags(value);
    return cleaned
      .split('\n')
      .map((s) => s.trim())
      .filter((s) => s.length !== 0);
  }
  if (isDictArray(value)) {
    // HowToStep or HowToSection objects
    const mapped: string[] = [];
    for (const step of value) {
      if (isString(step['text'])) {
        mapped.push(stripHTMLTags(step['text']).trim());
        continue;
      }
      if (isString(step['name'])) {
        mapped.push(stripHTMLTags(step['name']).trim());
        continue;
      }
      // HowToSection with itemListElement
      const items = step['itemListElement'];
      if (isDictArray(items)) {
        const joined = items
          .map((it) => it['text'])
          .filter(isString)
          .map((t) => stripHTMLTags(t).trim())
          .join('\n');
        mapped.push(joined);
        continue;
      }
      // nil in Swift compactMap -> skipped
    }
    return mapped.filter((s) => s.length !== 0);
  }
  return [];
}

/** Extracts servings count from recipeYield. */
function extractServings(value: unknown): number | null {
  if (typeof value === 'number' && Number.isInteger(value)) {
    return value;
  }
  if (isString(value)) {
    // "4 servings" or just "4"
    const digits = value.replace(/[^0-9]/g, '');
    if (digits.length === 0) return null;
    const n = parseInt(digits, 10);
    return Number.isNaN(n) ? null : n;
  }
  if (Array.isArray(value) && value.length > 0) {
    return extractServings(value[0]);
  }
  return null;
}

/** Extracts first string from a string or array. */
function extractFirstString(value: unknown): string {
  if (isString(value)) return value;
  if (isStringArray(value) && value.length > 0) return value[0];
  return '';
}

/** Extracts image URL from various formats. */
function extractImageURL(value: unknown): string {
  if (isString(value)) return value;
  if (isPlainObject(value) && isString(value['url'])) return value['url'];
  if (Array.isArray(value) && value.length > 0) {
    return extractImageURL(value[0]);
  }
  return '';
}

// MARK: - ISO 8601 Duration Parser

/** Parses ISO 8601 duration (e.g. "PT30M", "PT1H15M") to minutes. */
export function parseDuration(iso: string | null | undefined): number | null {
  if (iso == null || !iso.toUpperCase().startsWith('PT')) return null;
  const upper = iso.toUpperCase();
  let hours = 0;
  let minutes = 0;

  // Extract hours
  const hMatch = /(\d+)H/.exec(upper);
  if (hMatch !== null) {
    hours = parseInt(hMatch[1], 10) || 0;
  }
  // Extract minutes
  const mMatch = /(\d+)M/.exec(upper);
  if (mMatch !== null) {
    minutes = parseInt(mMatch[1], 10) || 0;
  }

  const total = hours * 60 + minutes;
  return total > 0 ? total : null;
}

// MARK: - Ingredient Cleaning

/**
 * Applies all ingredient normalizations in sequence. Returns the cleaned text
 * and a log of every transformation applied (empty if the input was already clean).
 */
export function cleanIngredientText(raw: string): CleanedIngredient {
  let text = raw;
  const normalizations: IngredientNormalization[] = [];

  const steps: [string, (s: string) => string | null][] = [
    [
      'dual_units',
      (s) => {
        const r = stripDualUnits(s);
        return r === s ? null : r;
      },
    ],
    [
      'double_parens',
      (s) => {
        const r = collapseDoubleParens(s);
        return r === s ? null : r;
      },
    ],
    [
      'leading_comma_parens',
      (s) => {
        const r = stripLeadingCommaInParens(s);
        return r === s ? null : r;
      },
    ],
    [
      'empty_parens',
      (s) => {
        const r = removeEmptyParens(s);
        return r === s ? null : r;
      },
    ],
    [
      'excess_whitespace',
      (s) => {
        const r = collapseWhitespace(s);
        return r === s ? null : r;
      },
    ],
  ];

  for (const [type, transform] of steps) {
    const cleaned = transform(text);
    if (cleaned !== null) {
      normalizations.push({ type, original: text, cleaned });
      text = cleaned;
    }
  }

  return { text, normalizations };
}

/** Strips dual-unit patterns: "50 g / 3 1/2 tbsp butter" → "3 1/2 tbsp butter". */
export function stripDualUnits(ingredient: string): string {
  const trimmed = trimWhitespace(ingredient);
  const pattern = /^\d+(?:\.\d+)?\s+(?:g|kg|mg|ml|l)\s*\/\s*(.+)$/i;
  const m = pattern.exec(trimmed);
  if (m === null) {
    return ingredient;
  }
  const afterSlash = trimWhitespace(m[1]);
  return afterSlash.length === 0 ? ingredient : afterSlash;
}

/** Collapses double parentheses: "((full fat preferred))" → "(full fat preferred)". */
export function collapseDoubleParens(text: string): string {
  let result = text;
  // Repeatedly collapse (( ... )) → ( ... ) until stable
  for (;;) {
    const open = result.indexOf('((');
    if (open < 0) break;
    // Find matching ))
    const close = result.indexOf('))', open + 2);
    if (close < 0) break;
    result = result.slice(0, close) + ')' + result.slice(close + 2);
    result = result.slice(0, open) + '(' + result.slice(open + 2);
  }
  return result;
}

/** Strips leading comma inside parentheses: "(, shredded)" → "(shredded)". */
export function stripLeadingCommaInParens(text: string): string {
  let result = text;
  const re = /\(\s*,\s*/;
  // Pattern: "(" followed by optional spaces, comma, optional spaces → "("
  for (;;) {
    const m = re.exec(result);
    if (m === null) break;
    result = result.slice(0, m.index) + '(' + result.slice(m.index + m[0].length);
  }
  return result;
}

/** Removes empty parentheses (with optional whitespace inside): "flour () here" → "flour here". */
export function removeEmptyParens(text: string): string {
  let result = text;
  const re = /\s*\(\s*\)/;
  for (;;) {
    const m = re.exec(result);
    if (m === null) break;
    result = result.slice(0, m.index) + result.slice(m.index + m[0].length);
  }
  return trimWhitespace(result);
}

/** Collapses multiple spaces into one. */
export function collapseWhitespace(text: string): string {
  let result = text;
  while (result.indexOf('  ') >= 0) {
    result = result.replace('  ', ' ');
  }
  return trimWhitespace(result);
}

// MARK: - HTML Utilities

/** Strips HTML tags from a string. */
export function stripHTMLTags(html: string): string {
  let result = html;
  // Remove tags
  for (;;) {
    const open = result.indexOf('<');
    if (open < 0) break;
    const close = result.indexOf('>', open + 1);
    if (close < 0) break;
    result = result.slice(0, open) + result.slice(close + 1);
  }
  return result.trim();
}

/** Decodes common HTML entities. */
export function decodeHTMLEntities(text: string): string {
  let result = text;
  const entities: [string, string][] = [
    ['&amp;', '&'],
    ['&lt;', '<'],
    ['&gt;', '>'],
    ['&quot;', '"'],
    ['&#39;', "'"],
    ['&apos;', "'"],
    ['&#x27;', "'"],
    ['&nbsp;', ' '],
    ['&#8217;', '’'],
    ['&#8211;', '–'],
    ['&#8212;', '—'],
  ];
  for (const [entity, replacement] of entities) {
    result = result.split(entity).join(replacement);
  }
  // Numeric entities: &#NNN;
  for (;;) {
    const start = result.indexOf('&#');
    if (start < 0) break;
    const end = result.indexOf(';', start + 2);
    if (end < 0) break;
    const numStr = result.slice(start + 2, end);
    const num = /^\d+$/.test(numStr) ? parseInt(numStr, 10) : NaN;
    // Unicode.Scalar(num) is nil for surrogates and values above U+10FFFF.
    if (!Number.isNaN(num) && num <= 0x10ffff && !(num >= 0xd800 && num <= 0xdfff)) {
      result = result.slice(0, start) + String.fromCodePoint(num) + result.slice(end + 1);
    } else {
      break;
    }
  }
  return result;
}
