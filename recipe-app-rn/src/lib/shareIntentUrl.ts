/**
 * Pull the recipe URL out of an Android/iOS share-sheet payload.
 *
 * A `text/plain` share can arrive as a bare URL ("https://…"), as prose with a
 * link embedded ("Check this out https://example.com/x — so good"), or already
 * split into a dedicated `webUrl` field by `expo-share-intent`. We prefer the
 * pre-extracted `webUrl`, then fall back to scanning the raw text for the first
 * http(s) URL. Returns `null` when there is no usable URL — the caller then
 * simply ignores the share rather than kicking off a doomed fetch.
 *
 * Framework-free and pure so it can be unit-tested without the native module.
 */

// First http(s) token in a blob of text. Stops at whitespace; trailing
// sentence punctuation is trimmed afterwards so "…/recipe." → "…/recipe".
const URL_RE = /https?:\/\/[^\s<>"']+/i;

/** Trailing characters that are almost always punctuation, not part of a URL. */
const TRAILING_JUNK = /[.,;:!?)\]}'"]+$/;

/**
 * Extract the first http(s) URL from a share payload.
 *
 * @param webUrl the share library's pre-parsed link, if any
 * @param text   the raw shared text, which may embed a URL among other words
 */
export function extractSharedUrl(webUrl?: string | null, text?: string | null): string | null {
  for (const candidate of [webUrl, text]) {
    if (!candidate) continue;
    const match = candidate.match(URL_RE);
    if (match) {
      const cleaned = match[0].replace(TRAILING_JUNK, '');
      if (cleaned.length > 0) return cleaned;
    }
  }
  return null;
}
