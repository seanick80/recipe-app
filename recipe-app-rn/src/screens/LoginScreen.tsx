import { useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';

import { useAuth } from '../contexts/AuthContext';
import { ApiError } from '../lib/apiClient';

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
    <View className="flex-1 items-center justify-center bg-white px-8">
      <Text className="text-3xl font-bold text-gray-900">Recipe App</Text>
      <Text className="mt-2 text-center text-base text-gray-500">
        Sign in to browse your recipes.
      </Text>

      {error ? <Text className="mt-6 text-center text-sm text-red-600">{error}</Text> : null}

      <Pressable
        accessibilityRole="button"
        disabled={busy}
        onPress={handleSignIn}
        className="mt-8 w-full flex-row items-center justify-center rounded-xl bg-gray-900 px-6 py-4 active:opacity-80"
      >
        {busy ? (
          <ActivityIndicator color="#ffffff" />
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
        <Text className="text-base text-gray-500">Continue without signing in</Text>
      </Pressable>
    </View>
  );
}
