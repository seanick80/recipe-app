/**
 * Parses raw text lines (from OCR of a handwritten shopping list) into
 * structured grocery item candidates. Input is a multi-line string (one item
 * per line, possibly with quantities like "2 cans tomatoes" or "milk x3");
 * output is an array of {@link ParsedListItem} ready for user confirmation.
 * 1:1 port of `SharedLogic/ListLineParser.swift` (framework-free).
 */

export type ParsedListItem = { name: string; quantity: number; unit: string };

/** Known unit abbreviations and their canonical forms. */
const knownUnits: Record<string, string> = {
  g: 'g', gram: 'g', grams: 'g',
  kg: 'kg', kilogram: 'kg', kilograms: 'kg',
  mg: 'mg', milligram: 'mg', milligrams: 'mg',
  ml: 'ml', milliliter: 'ml', milliliters: 'ml', millilitre: 'ml', millilitres: 'ml',
  l: 'l', liter: 'l', liters: 'l', litre: 'l', litres: 'l',
  lb: 'lb', lbs: 'lb', pound: 'lb', pounds: 'lb',
  oz: 'oz', ounce: 'oz', ounces: 'oz',
  gal: 'gallon', gallon: 'gallon', gallons: 'gallon',
  qt: 'quart', quart: 'quart', quarts: 'quart',
  pt: 'pint', pint: 'pint', pints: 'pint',
  cup: 'cup', cups: 'cup',
  tbsp: 'tbsp', tablespoon: 'tbsp', tablespoons: 'tbsp',
  tsp: 'tsp', teaspoon: 'tsp', teaspoons: 'tsp',
  can: 'can', cans: 'can',
  bag: 'bag', bags: 'bag',
  box: 'box', boxes: 'box',
  bottle: 'bottle', bottles: 'bottle',
  bunch: 'bunch', bunches: 'bunch',
  dozen: 'dozen', doz: 'dozen',
  loaf: 'loaf', loaves: 'loaf',
  count: 'count', ct: 'count',
  pkg: 'package', package: 'package', packages: 'package',
  jar: 'jar', jars: 'jar',
  stick: 'stick', sticks: 'stick',
  head: 'head', heads: 'head',
  piece: 'piece', pieces: 'piece', pc: 'piece', pcs: 'piece',
  roll: 'roll', rolls: 'roll',
  pack: 'pack', packs: 'pack',
  slice: 'slice', slices: 'slice',
};

/**
 * Metric/imperial units that commonly appear fused to their quantity in
 * printed recipes (e.g. "150g", "60ml", "2oz"). Only the short-form mass/volume
 * units are recognized in fused form — word units like "cup" or "tbsp" are left
 * to the space-separated path so ambiguous tokens like "cups" aren't misparsed.
 */
const fusedUnitCanonicalForms: Record<string, string> = {
  g: 'g', kg: 'kg',
  mg: 'mg',
  ml: 'ml', l: 'l',
  oz: 'oz', lb: 'lb', lbs: 'lb',
};

/** Strict number parse mirroring Swift's `Double(String)` (rejects empty/garbage). */
function parseDouble(s: string): number | null {
  if (s.length === 0) return null;
  if (s.trim() === '') return null;
  const n = Number(s);
  if (Number.isNaN(n)) return null;
  return n;
}

/** Trims any of `chars` off both ends (mirrors Swift `trimmingCharacters(in:)`). */
function trimCharacters(s: string, chars: string): string {
  let start = 0;
  let end = s.length;
  while (start < end && chars.includes(s[start])) start += 1;
  while (end > start && chars.includes(s[end - 1])) end -= 1;
  return s.slice(start, end);
}

/**
 * Parses a multi-line OCR string into an array of {@link ParsedListItem}.
 * Blank lines and lines that look like headers/noise are skipped.
 */
export function parseShoppingListText(text: string): ParsedListItem[] {
  const lines = text.split(/\r\n|\n|\r/);
  const result: ParsedListItem[] = [];
  for (const line of lines) {
    const item = parseListLine(line);
    if (item !== null) result.push(item);
  }
  return result;
}

/**
 * Parses a single line of text into a {@link ParsedListItem}, or null if the
 * line is blank/noise.
 *
 * Supported formats:
 *   "milk"                    → (milk, 1, "")
 *   "2 milk"                  → (milk, 2, "")
 *   "2x milk"                 → (milk, 2, "")
 *   "milk x3"                 → (milk, 3, "")
 *   "2 cans tomatoes"         → (tomatoes, 2, "can")
 *   "1 lb chicken breast"     → (chicken breast, 1, "lb")
 *   "- eggs"                  → (eggs, 1, "")     (bullet prefix stripped)
 *   "• bread"                 → (bread, 1, "")     (bullet prefix stripped)
 *   "3. bananas"              → (bananas, 3, "")   (numbered list)
 */
export function parseListLine(rawLine: string): ParsedListItem | null {
  let line = rawLine.trim();

  // Skip blank lines
  if (line.length === 0) return null;

  // Strip common list prefixes: "- ", "• ", "* ", "[] ", "[x] "
  if (line.startsWith('- ') || line.startsWith('• ') || line.startsWith('* ')) {
    line = line.slice(2);
  } else if (line.startsWith('[] ')) {
    line = line.slice(3);
  } else if (line.startsWith('[x] ') || line.startsWith('[X] ')) {
    line = line.slice(4);
  }

  line = line.trim();
  if (line.length === 0) return null;

  // Skip lines that look like headers (all caps, short, no lowercase)
  if (
    [...line].length <= 20 &&
    line === line.toUpperCase() &&
    !/\p{Ll}/u.test(line) &&
    /\p{L}/u.test(line)
  ) {
    // Could be a category header like "DAIRY" or "PRODUCE"
    return null;
  }

  let quantity = 1;
  let unit = '';

  const tokens = line.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return null;

  let startIndex = 0;

  // Try to parse leading quantity: "2", "2x", "0.5"
  const firstNum = parseQuantityToken(tokens[0]);
  const fused = firstNum === null ? parseFusedQuantityUnit(tokens[0]) : null;
  if (firstNum !== null) {
    quantity = firstNum;
    startIndex = 1;
    // Compound fraction: "1 1/2", "1 ½", "2 3/4"
    if (startIndex < tokens.length && Number.isInteger(firstNum)) {
      const frac = parseQuantityToken(tokens[startIndex]);
      if (frac !== null && frac > 0 && frac < 1) {
        quantity = firstNum + frac;
        startIndex += 1;
      }
    }
    // Also handle "1 and 1/2"
    if (startIndex < tokens.length && tokens[startIndex].toLowerCase() === 'and') {
      if (startIndex + 1 < tokens.length) {
        const frac = parseQuantityToken(tokens[startIndex + 1]);
        if (frac !== null && frac > 0 && frac < 1) {
          quantity = firstNum + frac;
          startIndex += 2;
        }
      }
    }
  } else if (fused !== null) {
    // Handles tokens like "150g", "60ml", "2oz" where OCR / recipe
    // formatting has glued the number and unit with no space.
    quantity = fused.quantity;
    unit = fused.unit;
    startIndex = 1;
  }

  // Check for "x3" or "×3" suffix at end of line
  if (startIndex === 0) {
    const lastToken = tokens[tokens.length - 1];
    const trailingQty = parseTrailingMultiplier(lastToken);
    if (trailingQty !== null) {
      quantity = trailingQty;
      // Parse remaining tokens (excluding last)
      const nameTokens = tokens.slice(0, tokens.length - 1);
      if (nameTokens.length === 0) return null;
      const name = nameTokens.join(' ');
      return { name: cleanItemName(name), quantity, unit };
    }
  }

  // Check for numbered list: "3. bananas" — the number is the quantity
  if (startIndex === 0 && tokens[0].endsWith('.')) {
    const numPart = tokens[0].slice(0, -1);
    const n = parseDouble(numPart);
    if (n !== null && n > 0 && n <= 100) {
      quantity = n;
      startIndex = 1;
    }
  }

  // Check if next token is a known unit. Strip trailing punctuation first so a
  // dotted abbreviation like "Tbsp." or "tsp." still matches `knownUnits`
  // instead of leaking into the item name.
  if (startIndex < tokens.length) {
    const candidate = trimCharacters(tokens[startIndex], ',.;:').toLowerCase();
    const canonical = knownUnits[candidate];
    if (canonical !== undefined) {
      unit = canonical;
      startIndex += 1;
    }
  }

  // Remaining tokens form the item name
  if (startIndex >= tokens.length) {
    // Only had a number and maybe a unit, no item name
    // Treat the unit as the name if we have one
    if (unit.length > 0) {
      return { name: unit, quantity, unit: '' };
    }
    return null;
  }

  const name = tokens.slice(startIndex).join(' ');
  return { name: cleanItemName(name), quantity, unit };
}

/**
 * Attempts to parse a token as a quantity number.
 * Handles: "2", "2x", "0.5", "½", "1/2"
 */
export function parseQuantityToken(token: string): number | null {
  let t = token;

  // Strip trailing "x" or "×" multiplier marker
  if (t.endsWith('x') || t.endsWith('×')) {
    t = t.slice(0, -1);
  }

  // Direct number
  const direct = parseDouble(t);
  if (direct !== null && direct > 0) return direct;

  // Fused whole number + unicode fraction: "1½", "2¼", "1¾"
  const unicodeFractions: Record<string, number> = {
    '½': 0.5, '⅓': 1.0 / 3, '⅔': 2.0 / 3,
    '¼': 0.25, '¾': 0.75,
  };
  const chars = [...t];
  if (chars.length >= 2) {
    const lastChar = chars[chars.length - 1];
    const fracValue = unicodeFractions[lastChar];
    if (fracValue !== undefined) {
      const wholePart = chars.slice(0, -1).join('');
      const whole = parseDouble(wholePart);
      if (whole !== null && whole > 0) {
        return whole + fracValue;
      }
    }
  }

  // Unicode fractions
  const fractions: Record<string, number> = {
    '½': 0.5, '⅓': 1.0 / 3, '⅔': 2.0 / 3,
    '¼': 0.25, '¾': 0.75,
  };
  const f = fractions[t];
  if (f !== undefined) return f;

  // Slash fraction: "1/2", "3/4"
  const parts = t.split('/');
  if (parts.length === 2) {
    const num = parseDouble(parts[0]);
    const den = parseDouble(parts[1]);
    if (num !== null && den !== null && den > 0) {
      return num / den;
    }
  }

  return null;
}

/**
 * Attempts to split a single fused token like "150g" or "60ml" into a quantity
 * and unit. Returns null if the token doesn't match `<number><short-unit>`
 * exactly (trailing punctuation like a comma is ignored so "375g," still parses).
 */
export function parseFusedQuantityUnit(token: string): { quantity: number; unit: string } | null {
  // Strip trailing punctuation the ingredient line may have attached.
  const trimmed = trimCharacters(token, ',.;:');
  if (trimmed.length === 0) return null;

  // Find the boundary between the numeric prefix and the alpha suffix.
  const chars = [...trimmed];
  let splitIndex = 0;
  for (const ch of chars) {
    if ((ch >= '0' && ch <= '9') || ch === '.') {
      splitIndex += 1;
    } else {
      break;
    }
  }
  if (!(splitIndex > 0 && splitIndex < chars.length)) {
    return null;
  }

  const numPart = chars.slice(0, splitIndex).join('');
  const unitPart = chars.slice(splitIndex).join('').toLowerCase();

  const qty = parseDouble(numPart);
  if (qty === null || !(qty > 0)) return null;
  const canonical = fusedUnitCanonicalForms[unitPart];
  if (canonical === undefined) return null;
  return { quantity: qty, unit: canonical };
}

/** Parses trailing multiplier like "x3", "×2". */
export function parseTrailingMultiplier(token: string): number | null {
  const t = token;
  if ((t.startsWith('x') || t.startsWith('×')) && [...t].length > 1) {
    const numPart = t.slice(1);
    const n = parseDouble(numPart);
    if (n !== null && n > 0) return n;
  }
  return null;
}

/** Cleans up an item name: trims whitespace, removes trailing punctuation. */
export function cleanItemName(name: string): string {
  let cleaned = name.trim();
  // Remove trailing punctuation that OCR might add
  while (cleaned.endsWith(',') || cleaned.endsWith('.') || cleaned.endsWith(';')) {
    cleaned = cleaned.slice(0, -1).trim();
  }
  return cleaned;
}
