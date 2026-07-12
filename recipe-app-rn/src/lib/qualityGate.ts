/**
 * Image quality assessment and handwriting detection for OCR scans. On iOS,
 * VNRecognizedTextObservation provides per-line confidence and bounding boxes;
 * this module works with simplified versions so the logic is testable without
 * the Vision framework. 1:1 port of `SharedLogic/QualityGate.swift`
 * (framework-free).
 */

/** Normalized bounding box (0..1 coordinates, origin at bottom-left to match Vision). */
export type NormalizedBox = {
  x: number;
  y: number;
  width: number;
  height: number;
};

/** A single line of OCR output with position and confidence metadata. */
export type OCRLine = {
  text: string;
  confidence: number; // 0.0–1.0
  boundingBox: NormalizedBox; // normalized 0..1 coordinates
};

/** Result of assessing overall image quality for OCR. */
export type ImageQualityAssessment = {
  medianConfidence: number;
  lowConfidenceRatio: number; // fraction of lines below 0.5
  isAcceptable: boolean;
  reason: string;
  shouldRetake: boolean;
};

/** Zero box (origin, no size) — matches Swift `NormalizedBox.zero`. */
export const zeroBox: NormalizedBox = { x: 0, y: 0, width: 0, height: 0 };

/** Center x coordinate. */
export function boxMidX(b: NormalizedBox): number {
  return b.x + b.width / 2;
}

/** Center y coordinate. */
export function boxMidY(b: NormalizedBox): number {
  return b.y + b.height / 2;
}

/** Right edge. */
export function boxMaxX(b: NormalizedBox): number {
  return b.x + b.width;
}

/** Top edge. */
export function boxMaxY(b: NormalizedBox): number {
  return b.y + b.height;
}

/**
 * Constructs an `OCRLine`, defaulting the bounding box to `zeroBox` (mirrors the
 * Swift initializer's `boundingBox: NormalizedBox = .zero` default).
 */
export function makeOCRLine(text: string, confidence: number, boundingBox: NormalizedBox = zeroBox): OCRLine {
  return { text, confidence, boundingBox };
}

// MARK: - Quality Assessment

/** Minimum median confidence to accept an image. */
const minMedianConfidence = 0.35;

/** Maximum ratio of low-confidence lines before rejecting. */
const maxLowConfidenceRatio = 0.6;

/** Confidence threshold below which a line is "low confidence". */
const lowConfidenceThreshold = 0.5;

/**
 * Assesses overall image quality from OCR line results.
 *
 * Checks:
 *   - Median OCR confidence (below 0.35 = blurry/bad lighting)
 *   - Ratio of low-confidence lines (>60% = widespread problems)
 */
export function assessImageQuality(lines: OCRLine[]): ImageQualityAssessment {
  if (lines.length === 0) {
    return {
      medianConfidence: 0.0,
      lowConfidenceRatio: 1.0,
      isAcceptable: false,
      reason: 'No text detected — page may be blank or image too dark',
      shouldRetake: true,
    };
  }

  const confidences = lines.map((l) => l.confidence).sort((a, b) => a - b);
  const medianConf = median(confidences);
  const lowCount = confidences.filter((c) => c < lowConfidenceThreshold).length;
  const lowRatio = lowCount / confidences.length;

  const reasons: string[] = [];

  if (medianConf < minMedianConfidence) {
    const pct = Math.trunc(medianConf * 100);
    reasons.push(`Very low OCR confidence (${pct}%) — image may be blurry or poorly lit`);
  }

  if (lowRatio > maxLowConfidenceRatio) {
    const pct = Math.trunc(lowRatio * 100);
    reasons.push(`${pct}% of text lines have low confidence — widespread readability issues`);
  }

  const isAcceptable = reasons.length === 0;
  return {
    medianConfidence: medianConf,
    lowConfidenceRatio: lowRatio,
    isAcceptable,
    reason: reasons.join('; '),
    shouldRetake: !isAcceptable,
  };
}

// MARK: - Handwriting Detection

/** Minimum absolute confidence for printed text. */
const handwritingConfidenceThreshold = 0.35;

/** Page edge margin (5% from each edge). */
const edgeMarginRatio = 0.05;

/**
 * Detects whether an OCR line is likely handwritten based on multiple signals.
 *
 * Requires 3+ signals to flag, preventing false positives on normal printed
 * text that happens to have low OCR confidence:
 *   - Very low absolute confidence (< 0.35)
 *   - Confidence well below page median (< 60% of median)
 *   - Position in page margins (outer 5%)
 *   - Line height very different from median (>80% bigger or <50% smaller)
 */
export function isLikelyHandwritten(line: OCRLine, medianConfidence: number, medianHeight: number): boolean {
  let signals = 0;

  // Very low absolute confidence.
  if (line.confidence < handwritingConfidenceThreshold) {
    signals += 1;
  }

  // Confidence well below page median.
  if (medianConfidence > 0 && line.confidence < medianConfidence * 0.6) {
    signals += 1;
  }

  // In page margins (left or right edge).
  const box = line.boundingBox;
  if (box.x < edgeMarginRatio || boxMaxX(box) > 1.0 - edgeMarginRatio) {
    signals += 1;
  }

  // Line height very different from median.
  if (medianHeight > 0 && box.height > 0) {
    const ratio = box.height / medianHeight;
    if (ratio > 1.8 || ratio < 0.5) {
      signals += 1;
    }
  }

  return signals >= 3;
}

/** Splits OCR lines into printed and handwritten groups. */
export function separateHandwritten(lines: OCRLine[]): { printed: OCRLine[]; handwritten: OCRLine[] } {
  if (lines.length === 0) return { printed: [], handwritten: [] };

  const confidences = lines.map((l) => l.confidence).sort((a, b) => a - b);
  const medConf = median(confidences);
  const heights = lines.map((l) => l.boundingBox.height).sort((a, b) => a - b);
  const medHeight = median(heights);

  const printed: OCRLine[] = [];
  const handwritten: OCRLine[] = [];

  for (const line of lines) {
    if (isLikelyHandwritten(line, medConf, medHeight)) {
      handwritten.push(line);
    } else {
      printed.push(line);
    }
  }

  return { printed, handwritten };
}

// MARK: - Block Grouping

/**
 * Groups OCR lines into vertically-adjacent blocks.
 *
 * A new block starts when the vertical gap between a line and its predecessor
 * exceeds `gapFactor * medianHeight`. Used after `separateHandwritten` to feed
 * multi-line text into `classifyZone` (which expects coherent blocks, not
 * individual lines).
 */
export function groupLinesIntoBlocks(lines: OCRLine[], gapFactor = 1.5): OCRLine[][] {
  if (lines.length === 0) return [];
  const sorted = [...lines].sort((a, b) => a.boundingBox.y - b.boundingBox.y);
  const heights = sorted.map((l) => l.boundingBox.height).sort((a, b) => a - b);
  const medianHeight = median(heights);
  const gapThreshold = Math.max(medianHeight * gapFactor, 0.005);

  const blocks: OCRLine[][] = [[sorted[0]]];
  for (const line of sorted.slice(1)) {
    const currentBlock = blocks[blocks.length - 1];
    const previous = currentBlock[currentBlock.length - 1];
    if (previous === undefined) continue;
    const prevBottom = boxMaxY(previous.boundingBox);
    const gap = line.boundingBox.y - prevBottom;
    if (gap > gapThreshold) {
      blocks.push([line]);
    } else {
      currentBlock.push(line);
    }
  }
  return blocks;
}

// MARK: - Section Header Routing
//
// Recipe OCR produces lines in reading order. Rather than trust geometric block
// grouping (fragile on multi-column pages and dense web layouts), we walk the
// lines in order and use explicit section headers like "Ingredients", "Method",
// "Step 1" to route each subsequent line to the correct bucket.

/** Semantic section of a recipe, identified from explicit headers in the OCR. */
export type RecipeSection = 'intro' | 'ingredients' | 'instructions';

/**
 * If the line is a standalone section header, returns the section it
 * introduces. Otherwise null.
 *
 * Matches whole-line headers only — phrases embedded in paragraphs don't count,
 * to avoid misreading body sentences that happen to contain the word
 * "ingredients".
 */
export function sectionFromHeader(line: string): RecipeSection | null {
  const trimmed = line
    .trim()
    .replace(/^[:.·•*]+|[:.·•*]+$/g, '')
    .trim()
    .toLowerCase();

  // Only short, header-like strings (< 30 chars keeps out paragraphs that
  // happen to mention "ingredients" in prose).
  const len = [...trimmed].length;
  if (len < 4 || len >= 30) return null;

  switch (trimmed) {
    case 'ingredients':
    case 'ingredient list':
    case 'what you need':
    case "what you'll need":
      return 'ingredients';
    case 'method':
    case 'directions':
    case 'direction':
    case 'instructions':
    case 'instruction':
    case 'preparation':
    case 'procedure':
    case 'steps':
    case 'how to make':
    case 'how to make it':
      return 'instructions';
    default:
      // "Step 1", "Step 2", "step 3" — anywhere a step header appears, we're in
      // the instruction section.
      if (trimmed.startsWith('step ') || trimmed.startsWith('step\t')) {
        return 'instructions';
      }
      return null;
  }
}

/**
 * True if the line is metadata noise with no real content — e.g. orphan digits
 * from nutrition widgets ("270•", "615°", "108."), bare unit tokens ("160g."),
 * or decorative symbols. These appear around recipe headers on web pages and
 * should be dropped before parsing.
 */
export function isLikelyMetadataJunk(line: string): boolean {
  const trimmed = line.trim();
  if (trimmed.length === 0) return true;

  // A line is junk if, after stripping digits / punctuation / common unit
  // suffixes, there's no alphabetic content left (or only a lone unit letter).
  const unitRegex = /\b\d+(\.\d+)?\s*(g|kg|ml|l|oz|lb)\b/gi;
  const stripCharacters = /[0-9.,°•·*:;×xX/\\\-+()[\] \t]/g;
  const stripped = trimmed.replace(unitRegex, '').trim().replace(stripCharacters, '');

  // After stripping digits/units/punctuation, very short residue (<= 1 letter)
  // means the line was essentially numeric.
  return [...stripped].length <= 1;
}

// MARK: - Headerless Recipe Heuristics

const cookingVerbs = new Set<string>([
  'heat', 'combine', 'cook', 'add', 'stir', 'mix', 'pour', 'place',
  'bake', 'serve', 'preheat', 'bring', 'reduce', 'cover', 'remove',
  'transfer', 'whisk', 'fold', 'season', 'drain', 'cut', 'slice',
  'chop', 'melt', 'grease', 'brush', 'roll', 'spread', 'arrange',
  'return', 'meanwhile', 'fill', 'sprinkle', 'set', 'let', 'cool',
  'line', 'soak', 'blend', 'process', 'knead', 'shape', 'divide',
  'toss', 'drizzle', 'garnish', 'top', 'stand', 'rest', 'simmer',
  'boil', 'fry', 'roast', 'grill', 'broil', 'sauté', 'sear',
  'marinate', 'refrigerate', 'freeze', 'thaw', 'wrap', 'discard',
  'squeeze', 'strain', 'rinse', 'wash', 'peel', 'trim', 'score',
  'thread', 'skewer', 'invert', 'unmould', 'unmold', 'flip',
  'using', 'in', 'on', 'working', 'make', 'prepare', 'finish',
]);

/**
 * True if the line looks like a numbered instruction step — e.g. "1 Combine
 * flours in large bowl" or "3 Serve fritters topped with...". These start with
 * a digit (1–9) immediately followed by a space and a capital letter or verb,
 * distinguishing them from ingredient lines like "2 eggs" or "1 tablespoon
 * olive oil".
 */
export function looksLikeNumberedInstruction(line: string): boolean {
  const trimmed = line.trim();
  const chars = [...trimmed];
  if (chars.length <= 10) return false;

  // Must start with a single digit followed by a space.
  const first = chars[0];
  if (!isNumberChar(first) || chars.length <= 2 || chars[1] !== ' ') return false;

  // The word after the number: if it's a cooking verb → instruction.
  const afterNumber = chars.slice(2).join('').trim();
  const firstWord = prefixWhileLetter(afterNumber).toLowerCase();

  return cookingVerbs.has(firstWord);
}

/**
 * True if the line starts with a quantity pattern typical of an ingredient line
 * — e.g. "½ cup", "2 tablespoons", "420g", "¼ cup (60ml)". Used as a fallback
 * when no section headers were found.
 */
export function looksLikeIngredientStart(line: string): boolean {
  const trimmed = line.trim();
  if (trimmed.length === 0) return false;

  // Must start with a digit, fraction character, or Unicode fraction.
  const first = [...trimmed][0];
  const codePoint = first.codePointAt(0) ?? 0;
  const isASCIIScalar = codePoint < 128;
  const startsWithQuantity = isASCIIScalar ? isNumberChar(first) : '½¼¾⅓⅔⅛⅜⅝⅞'.includes(first);

  if (!startsWithQuantity) return false;

  // If it looks like a numbered instruction, it's not an ingredient.
  if (looksLikeNumberedInstruction(trimmed)) return false;

  // Short lines starting with a number are likely ingredients ("2 eggs"). Long
  // lines (>100 chars) starting with a number are likely instructions.
  if ([...trimmed].length > 100) return false;

  return true;
}

// MARK: - Helpers

/** Median of a sorted array. */
function median(sorted: number[]): number {
  if (sorted.length === 0) return 0;
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return sorted[mid];
}

/** True if the character is an ASCII decimal digit (mirrors Swift `Character.isNumber` here). */
function isNumberChar(ch: string): boolean {
  return /[0-9]/.test(ch);
}

/** Leading run of letters from a string (mirrors Swift `prefix(while: { $0.isLetter })`). */
function prefixWhileLetter(s: string): string {
  let out = '';
  for (const ch of s) {
    if (/\p{L}/u.test(ch)) {
      out += ch;
    } else {
      break;
    }
  }
  return out;
}
