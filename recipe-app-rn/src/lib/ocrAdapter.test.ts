import { DEFAULT_OCR_CONFIDENCE, mlKitToOCRLines, normalizeFrame, type MLKitResult } from './ocrAdapter';
import { zeroBox } from './qualityGate';

describe('normalizeFrame', () => {
  it('normalizes pixel coords by image dimensions', () => {
    // 1000x2000 image; a box at left=100, width=200 → x=0.1, width=0.2.
    const box = normalizeFrame({ left: 100, top: 500, width: 200, height: 100 }, 1000, 2000);
    expect(box.x).toBeCloseTo(0.1, 6);
    expect(box.width).toBeCloseTo(0.2, 6);
    expect(box.height).toBeCloseTo(0.05, 6); // 100 / 2000
  });

  it('flips the Y axis to bottom-left origin', () => {
    // A line near the TOP of the image (top=0) should map to a HIGH y
    // (near the top edge in bottom-left coords, i.e. y ≈ 1 - height).
    const top = normalizeFrame({ left: 0, top: 0, width: 100, height: 100 }, 1000, 1000);
    expect(top.y).toBeCloseTo(0.9, 6); // 1 - (0 + 100)/1000

    // A line near the BOTTOM (top=900, height=100 → bottom edge at 1000) should
    // map to y ≈ 0.
    const bottom = normalizeFrame({ left: 0, top: 900, width: 100, height: 100 }, 1000, 1000);
    expect(bottom.y).toBeCloseTo(0.0, 6); // 1 - (900 + 100)/1000
  });

  it('preserves vertical ordering after the flip (higher on page ⇒ larger y)', () => {
    const upper = normalizeFrame({ left: 0, top: 100, width: 50, height: 40 }, 500, 1000);
    const lower = normalizeFrame({ left: 0, top: 800, width: 50, height: 40 }, 500, 1000);
    expect(upper.y).toBeGreaterThan(lower.y);
  });

  it('returns zeroBox when the frame is missing', () => {
    expect(normalizeFrame(undefined, 1000, 1000)).toBe(zeroBox);
  });

  it('returns zeroBox for non-positive image dimensions (no divide-by-zero)', () => {
    expect(normalizeFrame({ left: 0, top: 0, width: 10, height: 10 }, 0, 1000)).toBe(zeroBox);
    expect(normalizeFrame({ left: 0, top: 0, width: 10, height: 10 }, 1000, 0)).toBe(zeroBox);
  });

  it('clamps out-of-bounds coordinates into [0,1]', () => {
    const box = normalizeFrame({ left: -50, top: -50, width: 2000, height: 2000 }, 1000, 1000);
    expect(box.x).toBe(0);
    expect(box.width).toBe(1);
    expect(box.height).toBe(1);
    expect(box.y).toBeGreaterThanOrEqual(0);
    expect(box.y).toBeLessThanOrEqual(1);
  });
});

describe('mlKitToOCRLines', () => {
  const result: MLKitResult = {
    text: 'Pancakes\n2 cups flour',
    blocks: [
      {
        text: 'Pancakes',
        lines: [{ text: 'Pancakes', frame: { left: 100, top: 50, width: 300, height: 60 } }],
      },
      {
        text: '2 cups flour',
        lines: [
          { text: '2 cups flour', frame: { left: 100, top: 200, width: 400, height: 50 } },
          { text: '   ', frame: { left: 0, top: 0, width: 10, height: 10 } }, // whitespace-only → dropped
        ],
      },
    ],
  };

  it('flattens blocks→lines in reading order, dropping blank lines', () => {
    const lines = mlKitToOCRLines(result, 1000, 1000);
    expect(lines.map((l) => l.text)).toEqual(['Pancakes', '2 cups flour']);
  });

  it('assigns the default confidence to every line', () => {
    const lines = mlKitToOCRLines(result, 1000, 1000);
    expect(lines.every((l) => l.confidence === DEFAULT_OCR_CONFIDENCE)).toBe(true);
  });

  it('normalizes and flips each box', () => {
    const lines = mlKitToOCRLines(result, 1000, 1000);
    // "Pancakes" is higher on the page than "2 cups flour" ⇒ larger flipped y.
    expect(lines[0].boundingBox.y).toBeGreaterThan(lines[1].boundingBox.y);
    expect(lines[0].boundingBox.x).toBeCloseTo(0.1, 6);
  });

  it('returns an empty array for a result with no blocks', () => {
    expect(mlKitToOCRLines({ text: '', blocks: [] }, 1000, 1000)).toEqual([]);
  });
});
