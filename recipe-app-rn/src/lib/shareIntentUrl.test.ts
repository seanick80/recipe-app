import { extractSharedUrl } from './shareIntentUrl';

describe('extractSharedUrl', () => {
  it('prefers the pre-parsed webUrl', () => {
    expect(extractSharedUrl('https://example.com/recipe', 'ignored text')).toBe('https://example.com/recipe');
  });

  it('returns a bare URL from text when webUrl is absent', () => {
    expect(extractSharedUrl(null, 'https://example.com/soup')).toBe('https://example.com/soup');
  });

  it('extracts an embedded URL from prose', () => {
    expect(extractSharedUrl(null, 'Check this out https://example.com/x it is great')).toBe(
      'https://example.com/x',
    );
  });

  it('trims trailing sentence punctuation', () => {
    expect(extractSharedUrl(null, 'Try https://example.com/recipe.')).toBe('https://example.com/recipe');
    expect(extractSharedUrl(null, 'Link (https://example.com/a)')).toBe('https://example.com/a');
  });

  it('handles http as well as https', () => {
    expect(extractSharedUrl(null, 'http://example.com/y')).toBe('http://example.com/y');
  });

  it('falls back to text when webUrl has no URL', () => {
    expect(extractSharedUrl('not a url', 'see https://example.com/z')).toBe('https://example.com/z');
  });

  it('returns null when there is no URL', () => {
    expect(extractSharedUrl(null, 'just some words')).toBeNull();
    expect(extractSharedUrl(null, null)).toBeNull();
    expect(extractSharedUrl(undefined, undefined)).toBeNull();
    expect(extractSharedUrl('', '')).toBeNull();
  });

  it('keeps query strings and fragments intact', () => {
    expect(extractSharedUrl(null, 'https://example.com/r?id=5&x=1#steps')).toBe(
      'https://example.com/r?id=5&x=1#steps',
    );
  });
});
