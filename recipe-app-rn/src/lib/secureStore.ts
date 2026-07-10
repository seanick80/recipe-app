import * as SecureStore from 'expo-secure-store';

import { KEYCHAIN_SERVICE, TOKEN_KEY } from '../config';

/**
 * JWT token storage — the RN equivalent of the SwiftUI `KeychainService`.
 * `expo-secure-store` is Keychain-backed on iOS and Keystore-backed on Android.
 * `AFTER_FIRST_UNLOCK` mirrors the SwiftUI app's
 * `kSecAttrAccessibleAfterFirstUnlock` (readable by background refresh after the
 * first unlock following a boot).
 */
const OPTIONS: SecureStore.SecureStoreOptions = {
  keychainService: KEYCHAIN_SERVICE,
  keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK,
};

export function getToken(): Promise<string | null> {
  return SecureStore.getItemAsync(TOKEN_KEY, OPTIONS);
}

export function setToken(token: string): Promise<void> {
  return SecureStore.setItemAsync(TOKEN_KEY, token, OPTIONS);
}

export function deleteToken(): Promise<void> {
  return SecureStore.deleteItemAsync(TOKEN_KEY, OPTIONS);
}
