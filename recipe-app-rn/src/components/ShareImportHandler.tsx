/**
 * Android/iOS share-sheet → recipe-import glue.
 *
 * When the user shares a URL or text to the app (Android `ACTION_SEND`
 * `text/plain`, iOS share extension), `expo-share-intent` surfaces it through
 * {@link useShareIntentContext}. This component — rendered once inside the
 * authenticated navigation tree — pulls the first http(s) URL out of that
 * payload, runs the shared import core ({@link fetchAndParseRecipe}), and on
 * success navigates to the `ImportReview` screen via {@link navigationRef}
 * (the same review step the manual "Import from URL" flow uses). Failures are
 * surfaced with an alert.
 *
 * Works for both cold start (app launched by the share; the intent is the
 * hook's initial value) and warm resume (a new share while the app runs; the
 * hook re-fires). Renders nothing.
 *
 * Import requires no auth here — saving from `ImportReview` handles the auth
 * gate — so this works for guests too.
 */
import { useEffect, useRef } from 'react';
import { Alert } from 'react-native';
import { useShareIntentContext } from 'expo-share-intent';

import { debugLog } from '../lib/debugLog';
import { fetchAndParseRecipe } from '../lib/recipeImport';
import { extractSharedUrl } from '../lib/shareIntentUrl';
import { navigationRef } from '../navigation/navigationRef';

async function importSharedUrl(url: string): Promise<void> {
  debugLog.log('share.import', 'received shared url', { url });
  const result = await fetchAndParseRecipe(url);
  if (result.success) {
    // The network round-trip above means the container is ready by now, but
    // guard anyway — navigating a detached ref throws.
    if (navigationRef.isReady()) {
      navigationRef.navigate('Recipes', { screen: 'ImportReview', params: { recipe: result.recipe } });
    } else {
      debugLog.log('share.import', 'navigation not ready, dropping share');
    }
  } else {
    debugLog.log('share.import', 'import failed', { message: result.message });
    Alert.alert('Import failed', result.message);
  }
}

export function ShareImportHandler(): null {
  const { hasShareIntent, shareIntent, resetShareIntent } = useShareIntentContext();
  // Guard against re-processing the same share when the hook re-emits.
  const handledRef = useRef<string | null>(null);

  useEffect(() => {
    if (!hasShareIntent) return;
    const url = extractSharedUrl(shareIntent.webUrl, shareIntent.text);
    // Consume the native value so it doesn't re-fire on the next resume.
    resetShareIntent();
    if (!url || handledRef.current === url) return;
    handledRef.current = url;
    void importSharedUrl(url);
  }, [hasShareIntent, shareIntent, resetShareIntent]);

  return null;
}
