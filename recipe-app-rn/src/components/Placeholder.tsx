import { Text, View } from 'react-native';

type PlaceholderProps = {
  title: string;
  subtitle?: string;
};

/**
 * Empty-state screen used by every Phase 0 tab. Styled with NativeWind
 * `className` so we prove the Tailwind styling pipeline end to end before
 * building real screens (and adopting gluestack-ui components) in Phase 2.
 */
export function Placeholder({ title, subtitle }: PlaceholderProps) {
  return (
    <View className="flex-1 items-center justify-center bg-app-surface px-6">
      <Text className="text-2xl font-semibold text-app-text-primary">{title}</Text>
      <Text className="mt-2 text-center text-base text-app-text-secondary">
        {subtitle ?? 'Coming soon'}
      </Text>
    </View>
  );
}
