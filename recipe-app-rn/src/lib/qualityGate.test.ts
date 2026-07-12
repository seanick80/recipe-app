// Ported 1:1 from TestFixtures/TestQualityGate.swift
import {
  assessImageQuality,
  groupLinesIntoBlocks,
  isLikelyHandwritten,
  isLikelyMetadataJunk,
  looksLikeIngredientStart,
  looksLikeNumberedInstruction,
  makeOCRLine,
  sectionFromHeader,
  separateHandwritten,
  type OCRLine,
} from './qualityGate';

describe('assessImageQuality', () => {
  it('accepts a high-confidence image', () => {
    const good = assessImageQuality([
      makeOCRLine('2 cups flour', 0.92),
      makeOCRLine('1 tsp vanilla', 0.88),
      makeOCRLine('3 eggs', 0.95),
    ]);
    expect(good.isAcceptable).toBe(true);
    expect(good.shouldRetake).toBe(false);
  });

  it('rejects a blurry (low-confidence) image', () => {
    const blurry = assessImageQuality([
      makeOCRLine('flour', 0.2),
      makeOCRLine('eggs', 0.15),
      makeOCRLine('sugar', 0.3),
    ]);
    expect(blurry.isAcceptable).toBe(false);
  });

  it('rejects an image with no text', () => {
    const empty = assessImageQuality([]);
    expect(empty.isAcceptable).toBe(false);
    expect(empty.reason).toContain('No text');
  });
});

describe('isLikelyHandwritten', () => {
  const medianConf = 0.85;
  const medianH = 0.03;

  it('flags low conf + margin + small as handwritten', () => {
    const hw = makeOCRLine('x2', 0.2, { x: 0.01, y: 0.5, width: 0.05, height: 0.02 });
    expect(isLikelyHandwritten(hw, medianConf, medianH)).toBe(true);
  });

  it('does not flag good-confidence printed text', () => {
    const printed = makeOCRLine('2 cups flour', 0.9, { x: 0.1, y: 0.3, width: 0.3, height: 0.03 });
    expect(isLikelyHandwritten(printed, medianConf, medianH)).toBe(false);
  });

  it('does not flag low confidence alone', () => {
    const lowOnly = makeOCRLine('sugar', 0.25, { x: 0.2, y: 0.5, width: 0.2, height: 0.03 });
    expect(isLikelyHandwritten(lowOnly, medianConf, medianH)).toBe(false);
  });
});

describe('separateHandwritten', () => {
  it('separates printed from handwritten lines', () => {
    const lines: OCRLine[] = [
      makeOCRLine('flour', 0.9, { x: 0.1, y: 0.3, width: 0.3, height: 0.03 }),
      makeOCRLine('salt', 0.88, { x: 0.1, y: 0.35, width: 0.25, height: 0.03 }),
      makeOCRLine('x1.5', 0.15, { x: 0.01, y: 0.32, width: 0.06, height: 0.01 }),
    ];
    const { printed, handwritten } = separateHandwritten(lines);
    expect(printed.length).toBe(2);
    expect(handwritten.length).toBe(1);
  });
});

describe('groupLinesIntoBlocks', () => {
  it('produces no blocks for empty input', () => {
    expect(groupLinesIntoBlocks([]).length).toBe(0);
  });

  it('merges adjacent lines into one block', () => {
    const adjacent: OCRLine[] = [
      makeOCRLine('a', 0.9, { x: 0.1, y: 0.3, width: 0.2, height: 0.03 }),
      makeOCRLine('b', 0.9, { x: 0.1, y: 0.34, width: 0.2, height: 0.03 }),
    ];
    expect(groupLinesIntoBlocks(adjacent).length).toBe(1);
  });

  it('splits a large gap into two blocks', () => {
    const separated: OCRLine[] = [
      makeOCRLine('top', 0.9, { x: 0.1, y: 0.1, width: 0.3, height: 0.03 }),
      makeOCRLine('bottom', 0.9, { x: 0.1, y: 0.8, width: 0.3, height: 0.03 }),
    ];
    expect(groupLinesIntoBlocks(separated).length).toBe(2);
  });
});

describe('sectionFromHeader', () => {
  it('routes explicit section headers', () => {
    expect(sectionFromHeader('Ingredients')).toBe('ingredients');
    expect(sectionFromHeader('Method')).toBe('instructions');
  });

  it('does not treat an ingredient line or empty string as a header', () => {
    expect(sectionFromHeader('5 Free Range Eggs')).toBeNull();
    expect(sectionFromHeader('')).toBeNull();
  });
});

describe('isLikelyMetadataJunk', () => {
  it('flags a number + bullet as junk', () => {
    expect(isLikelyMetadataJunk('270•')).toBe(true);
  });

  it('does not flag a real ingredient line', () => {
    expect(isLikelyMetadataJunk('5 Free Range Eggs')).toBe(false);
  });
});

describe('ingredient and instruction detection', () => {
  it('recognizes numbered instructions', () => {
    expect(looksLikeNumberedInstruction('1 Combine flours; whisk in eggs')).toBe(true);
    expect(looksLikeNumberedInstruction('2 eggs')).toBe(false);
  });

  it('recognizes ingredient starts and rejects instructions', () => {
    expect(looksLikeIngredientStart('2 tablespoons vegetable oil')).toBe(true);
    expect(looksLikeIngredientStart('Preheat oven to 180°C')).toBe(false);
  });
});

describe('data type round-trip (Codable substitute)', () => {
  // Swift's testDataTypeCodable used JSONEncoder/JSONDecoder to verify OCRLine
  // survives a round-trip. TS has no Codable, so we assert a
  // JSON.parse(JSON.stringify(...)) deep-equal round-trip instead.
  it('OCRLine survives a JSON round-trip', () => {
    const line = makeOCRLine('test', 0.85, { x: 0.1, y: 0.2, width: 0.3, height: 0.04 });
    const roundTripped = JSON.parse(JSON.stringify(line));
    expect(roundTripped).toEqual(line);
  });
});
