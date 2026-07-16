import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { ApiError } from '../lib/apiClient';
import { colors } from '../theme/tokens';

export function LoginScreen() {
  const { signIn, continueAsGuest } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSignIn() {
    setBusy(true);
    setError(null);
    try {
      await signIn();
    } catch (e) {
      // Mirrors the SwiftUI 403 copy for un-allowlisted users.
      if (e instanceof ApiError && e.kind === 'forbidden') {
        setError('Not authorized — ask Nick for an invite.');
      } else {
        setError('Sign-in failed. Please try again.');
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <View className="flex-1 items-center justify-center bg-app-surface px-8">
      <Text className="text-3xl font-bold text-app-text-primary">Recipe App</Text>
      <Text className="mt-2 text-center text-base text-app-text-secondary">
        Sign in to browse your recipes.
      </Text>

      {error ? <Text className="mt-6 text-center text-sm text-app-danger">{error}</Text> : null}

      <Pressable
        accessibilityRole="button"
        disabled={busy}
        onPress={handleSignIn}
        className="mt-8 w-full flex-row items-center justify-center rounded-xl bg-app-surface-dark px-6 py-4 active:opacity-80"
      >
        {busy ? (
          <ActivityIndicator color={colors.textOnDark} />
        ) : (
          <Text className="text-base font-semibold text-white">Sign in with Google</Text>
        )}
      </Pressable>

      <Pressable
        accessibilityRole="button"
        disabled={busy}
        onPress={continueAsGuest}
        className="mt-4 px-6 py-3 active:opacity-60"
      >
        <Text className="text-base text-app-text-secondary">Continue without signing in</Text>
      </Pressable>
    </View>
  );
}
