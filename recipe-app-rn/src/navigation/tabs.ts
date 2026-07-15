import type { ComponentProps } from 'react';
import type { Ionicons } from '@expo/vector-icons';

export type TabConfig = {
  /** Bottom-tab route name. */
  name: string;
  /** Home route name inside this tab's native stack. */
  home: string;
  /** Display title (tab label + stack header). */
  title: string;
  /** Placeholder subtitle until the real screen lands. */
  subtitle: string;
  /** Ionicons glyph for the tab bar. */
  icon: ComponentProps<typeof Ionicons>['name'];
};

/**
 * Tab set: Recipes, Shopping, Scan, Settings.
 *
 * Deliberately excludes the SwiftUI app's "Pantry" tab — Pantry (on-device
 * food classification) is out of scope for the RN app per the migration plan.
 * The former separate "Lists" tab was folded into Shopping: the app keeps a
 * single persistent shopping list, so there is no multi-list manager.
 */
export const TABS: TabConfig[] = [
  {
    name: 'Recipes',
    home: 'RecipesHome',
    title: 'Recipes',
    subtitle: 'Your recipes will live here.',
    icon: 'book-outline',
  },
  {
    name: 'Shopping',
    home: 'ShoppingHome',
    title: 'Shopping',
    subtitle: 'Your shopping list and staples.',
    icon: 'cart-outline',
  },
  {
    name: 'Scan',
    home: 'ScanHome',
    title: 'Scan',
    subtitle: 'Barcode and photo capture.',
    icon: 'barcode-outline',
  },
  {
    name: 'Settings',
    home: 'SettingsHome',
    title: 'Settings',
    subtitle: 'Account and sync.',
    icon: 'settings-outline',
  },
];
