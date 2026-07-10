import { GoogleSignin } from '@react-native-google-signin/google-signin';

import { IOS_CLIENT_ID, WEB_CLIENT_ID } from '../config';

/**
 * Thin wrapper over the native Google Sign-In SDK, mirroring the SwiftUI
 * `AuthService.configureGoogleSignIn` + `login()`. `webClientId` is the server
 * client ID (SwiftUI's `serverClientID`) so the returned ID token is minted for
 * the backend, which is what `POST /auth/mobile/google` verifies against.
 */
let configured = false;

export function configureGoogleSignIn(): void {
  if (configured) return;
  GoogleSignin.configure({
    iosClientId: IOS_CLIENT_ID,
    webClientId: WEB_CLIENT_ID,
    offlineAccess: false,
  });
  configured = true;
}

/**
 * Presents the native Google sign-in sheet and returns the Google ID token,
 * or `null` if the user cancelled. Throws if the SDK returns no ID token.
 */
export async function signInWithGoogle(): Promise<string | null> {
  configureGoogleSignIn();
  await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
  const response = await GoogleSignin.signIn();
  if (response.type !== 'success') return null; // user cancelled
  const idToken = response.data.idToken;
  if (!idToken) throw new Error('Google sign-in returned no ID token');
  return idToken;
}

export async function signOutGoogle(): Promise<void> {
  try {
    await GoogleSignin.signOut();
  } catch {
    // Best-effort: the local token is cleared regardless of SDK state.
  }
}
