import { Platform } from 'react-native';

/**
 * Google OAuth client IDs (safe to commit — public per the app's secrets policy).
 * Ported from the SwiftUI app's `Info.plist` / `AuthService.swift`.
 * - `IOS_CLIENT_ID` → passed to `GoogleSignin.configure({ iosClientId })`.
 * - `WEB_CLIENT_ID` is the *server* client ID (SwiftUI's `serverClientID`) →
 *   passed as `webClientId` so the returned ID token is minted for the backend.
 */
export const IOS_CLIENT_ID =
  '972511622379-mak8qoj1corsaria7f2k8ainq715al7u.apps.googleusercontent.com';
export const WEB_CLIENT_ID =
  '972511622379-s2ivecpg4492gg7dbq21c3ev3slqeukp.apps.googleusercontent.com';

/**
 * API base URL, mirroring the SwiftUI `ServerConfig`.
 * In dev on Android the host loopback is `10.0.2.2`, not `localhost` (which is
 * the emulator itself) — see the Android emulator toolchain in the migration notes.
 */
const DEV_HOST = Platform.OS === 'android' ? '10.0.2.2' : 'localhost';
export const API_BASE_URL = __DEV__
  ? `http://${DEV_HOST}:8000/api/v1`
  : 'https://recipe-api-972511622379.us-west1.run.app/api/v1';

/**
 * Web origin that serves the public recipe SPA (the same Cloud Run service that
 * hosts the API, minus the `/api/v1` suffix). A published recipe is viewable at
 * `${WEB_BASE_URL}/recipes/{serverId}` without signing in — used for share links.
 */
export const WEB_BASE_URL = API_BASE_URL.replace(/\/api\/v1\/?$/, '');

/** Sent on every request (matches the SwiftUI client's `User-Agent`). */
export const USER_AGENT = 'RecipeApp-RN/0.1.0';

/**
 * Secure-store key + service, mirroring the SwiftUI KeychainService
 * (`service = com.seanick80.recipeapp`, `account = jwt_token`). The service is
 * namespaced with `.rn` so the RN build and the SwiftUI build never collide
 * while both are installed side by side during parallel development.
 */
export const TOKEN_KEY = 'jwt_token';
export const KEYCHAIN_SERVICE = 'com.seanick80.recipeapp.rn';
