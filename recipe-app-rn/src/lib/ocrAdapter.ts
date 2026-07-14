/**
 * Adapts Google ML Kit's on-device text-recognition output
 * (`@react-native-ml-kit/text-recognition`) into the framework-free
 * {@link OCRLine} shape the ported quality gate / parser pipeline expects.
 *
 * Two coordinate systems have to be reconciled here:
 *
 *   - ML Kit reports bounding boxes as `{ left, top, width, height }` in **pixel**
 *     coordinates with the origin at the **top-left** and y growing **downward**.
 *   - {@link OCRLine.boundingBox} follows Apple's Vision convention: **normalized**
 *     0..1 coordinates with the origin at the **bottom-left** and y growing
 *     **upward** (this is what `qualityGate.ts` assumes for margin/height math).
 *
 * So every box is normalized by the image dimensions AND has its y-axis flipped.
 * See {@link normalizeFrame} for the exact transform.
 *
 * ML Kit's text recognizer does **not** expose a per-line confidence score, so
 * every adapted line is given {@link DEFAULT_OCR_CONFIDENCE} (1.0). This means
 * the quality gate's confidence-based checks are effectively no-ops for ML Kit
 * input — quality is instead judged downstream by whether any text was found and
 * how it parses. Kept as a constant so it's easy to revisit if a future ML Kit
 * version surfaces confidence.
 *
 * Pure / framework-free: only `import type` is pulled from the native package, so
 * this module is unit-testable without the native module present.
 */

import type { OCRLine, NormalizedBox } from './qualityGate';
import { zeroBox } from './qualityGate';

/** A ML Kit bounding box: pixel coords, top-left origin, y grows downward. */
export type MLKitFrame = {
  left: number;
  top: number;
  width: number;
  height: number;
};

/** Minimal shape of a ML Kit recognized line (subset of the library's `TextLine`). */
export type MLKitLine = {
  text: string;
  frame?: MLKitFrame;
};

/** Minimal shape of a ML Kit recognized block (subset of the library's `TextBlock`). */
export type MLKitBlock = {
  text: string;
  lines: MLKitLine[];
};

/** Minimal shape of a ML Kit recognition result (subset of `TextRecognitionResult`). */
export type MLKitResult = {
  text: string;
  blocks: MLKitBlock[];
};

/**
 * Confidence assigned to every ML Kit line. ML Kit text recognition does not
 * report per-line confidence, so we use a neutral-high default; the quality gate
 * still catches the "no text at all" case, which is the failure mode that
 * matters most for a photo scan.
 */
export const DEFAULT_OCR_CONFIDENCE = 1.0;

/** Clamps a value into the [0, 1] range. */
function clamp01(n: number): number {
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

/**
 * Converts a ML Kit pixel frame (top-left origin) into a normalized
 * {@link NormalizedBox} (bottom-left origin), flipping the y-axis.
 *
 *   x_norm      = left / imgW
 *   width_norm  = width / imgW
 *   height_norm = height / imgH
 *   y_norm      = 1 - (top + height) / imgH   ← bottom edge, measured from bottom
 *
 * Returns {@link zeroBox} when the frame is missing or image dimensions are
 * non-positive (avoids division by zero / NaN boxes).
 */
export function normalizeFrame(frame: MLKitFrame | undefined, imageWidth: number, imageHeight: number): NormalizedBox {
  if (!frame || imageWidth <= 0 || imageHeight <= 0) return zeroBox;

  const width = clamp01(frame.width / imageWidth);
  const height = clamp01(frame.height / imageHeight);
  const x = clamp01(frame.left / imageWidth);
  // Flip Y: ML Kit `top` is distance from the top edge; Vision wants the box
  // origin at its bottom edge measured up from the image bottom.
  const y = clamp01(1 - (frame.top + frame.height) / imageHeight);

  return { x, y, width, height };
}

/**
 * Flattens a ML Kit recognition result into {@link OCRLine}[], one entry per
 * recognized line (in block-then-line order, i.e. ML Kit's reading order),
 * normalizing + y-flipping each bounding box and assigning
 * {@link DEFAULT_OCR_CONFIDENCE}.
 *
 * Lines with empty/whitespace-only text are dropped. `imageWidth`/`imageHeight`
 * are the pixel dimensions of the captured photo (from
 * expo-camera's `takePictureAsync` result).
 */
export function mlKitToOCRLines(result: MLKitResult, imageWidth: number, imageHeight: number): OCRLine[] {
  const lines: OCRLine[] = [];
  for (const block of result.blocks) {
    for (const line of block.lines) {
      if (line.text.trim().length === 0) continue;
      lines.push({
        text: line.text,
        confidence: DEFAULT_OCR_CONFIDENCE,
        boundingBox: normalizeFrame(line.frame, imageWidth, imageHeight),
      });
    }
  }
  return lines;
}
