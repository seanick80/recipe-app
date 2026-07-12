/**
 * Parses raw OCR text from a recipe photo into structured recipe fields using
 * heuristic line-by-line analysis (title, ingredients, instructions, servings,
 * prep/cook time). Reuses the shopping-list line parser for ingredient lines.
 * 1:1 port of `SharedLogic/OCRParser.swift` (framework-free).
 */

import { parseListLine, ParsedListItem } from './listLineParser';

export type ParsedIngredient = { name: string; quantity: number; unit: string };

export type ParsedRecipe = {
  title: string;
  ingredients: ParsedIngredient[];
  instructions: string[];
  servings: number | null;
  prepTimeMinutes: number | null;
  cookTimeMinutes: number | null;
};

/** Section markers that indicate the start of an ingredients list. */
const ingredientHeaders = [
  'ingredients', 'ingredient list', 'what you need',
  'you will need', "you'll need", 'shopping list',
];

/** Section markers that indicate the start of instructions. */
const instructionHeaders = [
  'instructions', 'directions', 'method', 'steps',
  'preparation', 'how to make', 'procedure',
];

/** True if `ch` is an ASCII digit (mirrors Swift `Character.isNumber` for our inputs). */
function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

/** Leading run of digits (mirrors Swift `prefix(while: { $0.isNumber })`). */
function leadingDigits(s: string): string {
  let i = 0;
  while (i < s.length && isDigit(s[i])) i += 1;
  return s.slice(0, i);
}

/** Drops the leading run of digits (mirrors Swift `drop(while: { $0.isNumber })`). */
function dropLeadingDigits(s: string): string {
  let i = 0;
  while (i < s.length && isDigit(s[i])) i += 1;
  return s.slice(i);
}

/** Trims whitespace off both ends (mirrors Swift `trimmingCharacters(in: .whitespaces)`). */
function trimWhitespace(s: string): string {
  return s.replace(/^[ \t]+/, '').replace(/[ \t]+$/, '');
}

/** Trims any of `chars` off both ends (mirrors Swift `trimmingCharacters(in:)`). */
function trimCharacters(s: string, chars: string): string {
  let start = 0;
  let end = s.length;
  while (start < end && chars.includes(s[start])) start += 1;
  while (end > start && chars.includes(s[end - 1])) end -= 1;
  return s.slice(start, end);
}

/** Strict integer parse mirroring Swift's `Int(String)` (rejects empty/garbage). */
function parseInt10(s: string): number | null {
  if (s.length === 0) return null;
  if (!/^[+-]?\d+$/.test(s)) return null;
  const n = Number(s);
  if (Number.isNaN(n)) return null;
  return n;
}

/** Parses raw OCR text into a `ParsedRecipe`. */
export function parseRecipeText(text: string): ParsedRecipe {
  const lines = text.split(/\r\n|\n|\r/).map((l) => trimWhitespace(l));

  let title = '';
  const ingredients: ParsedIngredient[] = [];
  const instructions: string[] = [];
  let servings: number | null = null;
  let prepTime: number | null = null;
  let cookTime: number | null = null;

  type Section = 'header' | 'ingredients' | 'instructions' | 'unknown';
  let currentSection: Section = 'header';

  for (const line of lines) {
    const lower = line.toLowerCase();

    // Skip blank lines
    if (line.length === 0) continue;

    // Detect section headers
    if (ingredientHeaders.some((h) => lower.startsWith(h))) {
      currentSection = 'ingredients';
      continue;
    }
    if (instructionHeaders.some((h) => lower.startsWith(h))) {
      currentSection = 'instructions';
      continue;
    }

    // Extract metadata from any section
    const s = parseServings(lower);
    if (s !== null) {
      servings = s;
      continue;
    }
    const prep = parseTimeField(lower, ['prep time', 'prep']);
    if (prep !== null) {
      prepTime = prep;
      continue;
    }
    const cook = parseTimeField(lower, ['cook time', 'cooking time', 'cook']);
    if (cook !== null) {
      cookTime = cook;
      continue;
    }
    const total = parseTimeField(lower, ['total time', 'total']);
    if (total !== null) {
      // If we have prep but not cook, derive cook from total
      if (prepTime !== null && cookTime === null) {
        cookTime = Math.max(0, total - (prepTime ?? 0));
      } else if (prepTime === null && cookTime === null) {
        // Just store as cook time
        cookTime = total;
      }
      continue;
    }

    switch (currentSection) {
      case 'header':
        // First non-metadata, non-blank line is the title
        if (title.length === 0) {
          title = cleanRecipeTitle(line);
        }
        break;
      case 'ingredients': {
        const ingredient = parseIngredientLine(line);
        if (ingredient !== null) {
          ingredients.push(ingredient);
        }
        break;
      }
      case 'instructions': {
        const cleaned = cleanInstructionLine(line);
        if (cleaned.length > 0) {
          instructions.push(cleaned);
        }
        break;
      }
      default: // 'unknown'
        break;
    }
  }

  // Fallback: if no section headers were found, try parsing all non-title
  // lines as ingredients. Real-world recipe photos often lack headers.
  if (ingredients.length === 0 && instructions.length === 0) {
    for (const line of lines) {
      if (line.length === 0) continue;
      const lower = line.toLowerCase();
      // Skip the title line
      if (line === title || (line === cleanRecipeTitle(line) && line === title)) continue;
      // Skip metadata lines
      if (parseServings(lower) !== null) continue;
      if (parseTimeField(lower, ['prep time', 'prep']) !== null) continue;
      if (parseTimeField(lower, ['cook time', 'cooking time', 'cook']) !== null) continue;
      if (parseTimeField(lower, ['total time', 'total']) !== null) continue;
      // Try as ingredient
      const ingredient = parseIngredientLine(line);
      if (ingredient !== null) {
        ingredients.push(ingredient);
      }
    }
  }

  return {
    title,
    ingredients,
    instructions,
    servings,
    prepTimeMinutes: prepTime,
    cookTimeMinutes: cookTime,
  };
}

/** Parses an ingredient line like "2 cups flour" or "1/2 lb chicken breast". */
export function parseIngredientLine(line: string): ParsedIngredient | null {
  let cleaned = trimWhitespace(line);
  if (cleaned.length === 0) return null;

  // Strip list markers
  if (cleaned.startsWith('- ') || cleaned.startsWith('• ') || cleaned.startsWith('* ')) {
    cleaned = cleaned.slice(2);
  }
  cleaned = trimWhitespace(cleaned);
  if (cleaned.length === 0) return null;

  // Reuse the list line parser logic
  const parsed: ParsedListItem | null = parseListLine(cleaned);
  if (parsed !== null) {
    return { name: parsed.name, quantity: parsed.quantity, unit: parsed.unit };
  }
  return { name: cleaned, quantity: 1, unit: '' };
}

/** Extracts servings from a line like "Serves 4" or "Servings: 6". */
export function parseServings(lower: string): number | null {
  const patterns = ['serves', 'servings:', 'servings', 'yield:', 'yield', 'makes'];
  for (const prefix of patterns) {
    if (lower.startsWith(prefix)) {
      let rest = trimWhitespace(lower.slice(prefix.length));
      rest = trimCharacters(rest, ':');
      rest = trimWhitespace(rest);
      // Extract first number
      const digits = leadingDigits(rest);
      const n = parseInt10(digits);
      if (n !== null && n > 0) return n;
    }
  }
  return null;
}

/** Extracts time in minutes from a line like "Prep time: 20 min". */
export function parseTimeField(lower: string, prefixes: string[]): number | null {
  for (const prefix of prefixes) {
    if (lower.startsWith(prefix)) {
      let rest = trimWhitespace(lower.slice(prefix.length));
      rest = trimCharacters(rest, ':');
      rest = trimWhitespace(rest);
      return parseTimeString(rest);
    }
  }
  return null;
}

/** Parses time strings like "20 min", "1 hour", "1h 30m", "90 minutes". */
export function parseTimeString(text: string): number | null {
  const lower = text.toLowerCase();
  let totalMinutes = 0;
  let foundAny = false;

  // Match hours: "1 hour", "2 hours", "1hr", "1h"
  const hourMatch = /(\d+)\s*(?:hours?|hrs?|h)(?:[^a-z]|$)/.exec(lower);
  if (hourMatch !== null) {
    const match = hourMatch[0];
    const digits = leadingDigits(match);
    const h = parseInt10(digits);
    if (h !== null) {
      totalMinutes += h * 60;
      foundAny = true;
    }
  }

  // Match minutes: "30 minutes", "20 min", "30m"
  const minMatch = /(\d+)\s*(?:minutes?|mins?|m)(?:[^a-z]|$)/.exec(lower);
  if (minMatch !== null) {
    const match = minMatch[0];
    const digits = leadingDigits(match);
    const m = parseInt10(digits);
    if (m !== null) {
      totalMinutes += m;
      foundAny = true;
    }
  }

  // Bare number — assume minutes
  if (!foundAny) {
    const digits = leadingDigits(lower);
    const m = parseInt10(digits);
    if (m !== null && m > 0) {
      return m;
    }
  }

  return foundAny ? totalMinutes : null;
}

/** Cleans a recipe title (removes trailing colons, excess whitespace). */
export function cleanRecipeTitle(title: string): string {
  let cleaned = trimWhitespace(title);
  if (cleaned.endsWith(':')) {
    cleaned = trimWhitespace(cleaned.slice(0, -1));
  }
  return cleaned;
}

/** Cleans an instruction line (removes numbered prefixes like "1. ", "Step 2: "). */
export function cleanInstructionLine(line: string): string {
  let cleaned = trimWhitespace(line);

  // Remove "Step N:" or "Step N." prefix
  if (cleaned.toLowerCase().startsWith('step')) {
    const rest = trimWhitespace(cleaned.slice(4));
    // Drop the number and separator
    const afterNum = trimWhitespace(dropLeadingDigits(rest));
    if (afterNum.startsWith(':') || afterNum.startsWith('.') || afterNum.startsWith(')')) {
      cleaned = trimWhitespace(afterNum.slice(1));
    }
  } else if (cleaned.length > 0 && isDigit(cleaned[0])) {
    // Remove "N. " or "N) " prefix
    const afterNum = trimWhitespace(dropLeadingDigits(cleaned));
    if (afterNum.startsWith('.') || afterNum.startsWith(')')) {
      cleaned = trimWhitespace(afterNum.slice(1));
    }
  }

  return cleaned;
}
