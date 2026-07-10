/**
 * Strips preparation notes and size adjectives from ingredient names so
 * shopping lists show only what to buy, not how to prep it.
 *
 * 1:1 port of `SharedLogic/PrepNoteStripper.swift` (same word/phrase tables,
 * same three-pass algorithm and quirks). Used by the generate-from-recipes flow
 * to clean "Large Onion, Finely Chopped" → "Onion".
 */

/** Result of stripping prep notes from an ingredient name. */
export type StrippedIngredient = {
  name: string;
  prep: string;
  sizeAdjective: string;
};

/** Prep verbs/participles that are useless on a shopping list (lowercase). */
const prepWords: Set<string> = new Set([
  'chopped', 'diced', 'grated', 'sifted', 'melted', 'softened',
  'sliced', 'minced', 'peeled', 'toasted', 'roasted', 'blanched',
  'seeded', 'deveined', 'squeezed', 'trimmed', 'crushed', 'cubed',
  'julienned', 'shredded', 'halved', 'quartered', 'mashed',
  'crumbled', 'torn', 'beaten', 'whisked', 'thawed', 'drained',
  'rinsed', 'cored', 'pitted', 'zested', 'divided', 'packed',
  'sieved', 'ground', 'cracked', 'snipped', 'scored',
]);

/** Multi-word prep phrases stripped as a unit (order matters — matched in order). */
const prepPhrases: string[] = [
  'finely chopped', 'roughly chopped', 'coarsely chopped',
  'finely diced', 'finely grated', 'freshly grated',
  'finely sliced', 'thinly sliced', 'thickly sliced',
  'finely minced', 'freshly ground', 'freshly squeezed',
  'freshly cracked', 'lightly beaten', 'lightly toasted',
  'at room temperature', 'room temperature',
  'cut into chunks', 'cut into cubes', 'cut into pieces',
  'cut into strips', 'cut into wedges', 'cut into rings',
  'excess moisture squeezed out', 'moisture squeezed out',
  'patted dry', 'bones removed', 'skin removed',
  'stems removed', 'seeds removed', 'rind removed',
  'to taste', 'for garnish', 'for serving', 'for decoration',
  'plus extra', 'plus more',
];

/** Size adjectives stripped when they precede a food word (lowercase). */
const sizeAdjectives: Set<string> = new Set([
  'large', 'medium', 'small', 'big', 'tiny', 'extra-large', 'jumbo',
]);

const PREP_CONNECTIVES = new Set(['and', 'or', 'then', 'well']);

function escapeRegExp(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function trimCommaSpace(s: string): string {
  return s.replace(/^[,\s]+/, '').replace(/[,\s]+$/, '');
}

/**
 * Strip prep notes from an ingredient name.
 * @param name Raw ingredient name, e.g. "Large Onion, Finely Chopped".
 * @returns Cleaned name, extracted prep notes, and any stripped size adjective.
 */
export function stripPrepNotes(name: string): StrippedIngredient {
  let working = name.trim();
  if (working.length === 0) return { name: '', prep: '', sizeAdjective: '' };

  // Strip a leading parenthesized quantity prefix like "(1 Cup)" or "(2 tbsp)".
  working = working.replace(/^\s*\([^)]*\)\s*/, '').trim();

  const collectedPrep: string[] = [];

  // First pass: strip known multi-word prep phrases. `lower` is computed once
  // (matching the Swift quirk); the regex runs against the live `working`.
  const lower = working.toLowerCase();
  for (const phrase of prepPhrases) {
    if (!lower.includes(phrase)) continue;
    const re = new RegExp(`,?\\s*${escapeRegExp(phrase)}\\s*,?`, 'i');
    const m = re.exec(working);
    if (m) {
      collectedPrep.push(trimCommaSpace(m[0]).toLowerCase());
      working = (working.slice(0, m.index) + working.slice(m.index + m[0].length)).trim();
    }
  }

  // Second pass: split on commas; drop trailing segments that are entirely prep.
  const segments = working.split(',').map((s) => s.trim());
  const keptSegments: string[] = [];
  segments.forEach((segment, i) => {
    if (i === 0) {
      keptSegments.push(segment);
      return;
    }
    const words = segment.toLowerCase().split(/\s+/).filter((w) => w.length > 0);
    const isPrepSegment =
      words.length > 0 && words.every((w) => prepWords.has(w) || PREP_CONNECTIVES.has(w));
    if (isPrepSegment) collectedPrep.push(segment.toLowerCase());
    else keptSegments.push(segment);
  });
  working = trimCommaSpace(keptSegments.join(', '));

  // Third pass: strip a single leading size adjective (only if ≥2 words remain).
  let sizeAdj = '';
  const nameWords = working.split(/\s+/).filter((w) => w.length > 0);
  if (nameWords.length >= 2 && sizeAdjectives.has(nameWords[0].toLowerCase())) {
    sizeAdj = nameWords[0].toLowerCase();
    working = nameWords.slice(1).join(' ');
  }

  working = trimCommaSpace(working).trim();
  return { name: working, prep: collectedPrep.join(', '), sizeAdjective: sizeAdj };
}
