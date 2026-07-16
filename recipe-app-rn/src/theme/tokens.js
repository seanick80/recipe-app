// Single-source design tokens for the RecipeApp RN client.
//
// This module is consumed from TWO very different runtimes:
//   1. tailwind.config.js — evaluated by plain Node (NOT Metro/Babel), so this
//      file MUST stay CommonJS (`module.exports`) with no TS/ESM syntax.
//   2. TSX call sites — imported as `import { colors } from '../theme/tokens'`
//      for raw hex props (Ionicons/ActivityIndicator/RefreshControl color=...).
//      Types come from the co-located `tokens.d.ts`.
//
// HARD RULE: every value here is the CURRENT hardcoded value, verbatim. This is
// a rename/indirection layer, not a restyle — reskin by editing values here.
// One token per distinct current value; near-duplicate shades are kept distinct
// on purpose (do not collapse). Each token has at least one live call site.

// Colors. Comment shows the Tailwind class / raw hex it replaced.
const colors = {
  // Brand / accent
  primary: '#2563eb', // blue-600 (links, actions, icons)
  primaryLight: '#3b82f6', // blue-500 (log category label)

  // Surfaces
  background: '#f9fafb', // gray-50 (screen background)
  surface: '#ffffff', // white (cards, sheets, inputs)
  surfaceDark: '#111827', // gray-900 (dark action buttons)

  // Text
  textPrimary: '#111827', // gray-900 (headings / primary text)
  textSecondary: '#6b7280', // gray-500 (secondary text)
  textSecondaryMid: '#4b5563', // gray-600 (secondary text, mid)
  textSecondaryStrong: '#374151', // gray-700 (secondary text, strong)
  textBody: '#1f2937', // gray-800 (body copy: ingredients/steps)
  textMuted: '#9ca3af', // gray-400 (muted / placeholder / hints)
  textDisabled: '#d1d5db', // gray-300 (disabled text)
  textOnDark: '#ffffff', // #fff/#ffffff (text/spinner on dark buttons)

  // Borders
  border: '#e5e7eb', // gray-200 (default border)
  borderStrong: '#d1d5db', // gray-300 (stronger border)
  borderSubtle: '#f3f4f6', // gray-100 (hairline dividers)

  // Chips / pills
  chipBg: '#f3f4f6', // gray-100 (tag chip background)

  // Danger
  danger: '#dc2626', // red-600 (destructive text/icons)
  dangerStrong: '#b91c1c', // red-700 (error banner text)
  dangerBg: '#fef2f2', // red-50 (error banner background)

  // Success
  success: '#16a34a', // (checked grocery item icon)

  // Warning
  warning: '#f59e0b', // (favorite star icon)
  warningBg: '#fef3c7', // amber-100 (warning banner background)
  warningBgSubtle: '#fffbeb', // amber-50 (subtle warning banner background)
  warningText: '#92400e', // amber-800 (warning banner text)
  warningTextSoft: '#b45309', // amber-700 (soft warning text)
};

// Corner radii. These mirror the current Tailwind default radius scale the app
// uses (via `rounded*` classes). Exported for single-sourcing a future reskin;
// class usages are intentionally left untouched by the token sweep so there is
// zero visual change.
const radii = {
  sm: 2, // rounded-sm
  DEFAULT: 4, // rounded
  lg: 8, // rounded-lg
  xl: 12, // rounded-xl
  '2xl': 16, // rounded-2xl
  full: 9999, // rounded-full
};

module.exports = { colors, radii };
