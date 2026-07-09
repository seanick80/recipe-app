# recipe-app-rn

React Native (Expo) re-implementation of the SwiftUI Recipe App. Lives as a
**sibling folder** in the `recipe-app` repo so it can share `server/` and
`schema/canonical.yaml` with the iOS app during early development (per
`docs/REACT_NATIVE_MIGRATION_PLAN.md`). The SwiftUI app in `RecipeApp/` stays
the shipping app; this project is built in parallel until a deliberate cutover.

## Status: Phase 0 complete (scaffold)

The app boots to a 4-tab shell — **Recipes, Shopping, Scan, Lists** (the SwiftUI
"Pantry" tab is intentionally dropped from the RN app). Every tab is an empty
placeholder screen inside its own native stack.

## Stack

| Concern | Choice |
|---|---|
| Framework | Expo SDK 57 (dev client) + TypeScript |
| Navigation | `@react-navigation` bottom-tabs, native-stack per tab |
| Styling | **NativeWind v4** (Tailwind for RN) |
| Icons | `@expo/vector-icons` (Ionicons) |
| Tests | jest-expo |

## Phase 0 decisions

- **Sibling folder, not a separate repo (yet).** Split to `recipe-app-rn` its
  own repo at the first release; until then keep schema + server in one checkout.
- **Expo + dev client, not bare RN.** Camera/ML modules (Phase 5) need native
  code, but Expo prebuild handles that without ejecting.
- **NativeWind now; gluestack-ui deferred to Phase 2.** gluestack's current CLI
  is a v5 *alpha* on Tailwind v4 and is interactive/unverifiable in CI. NativeWind
  is the Tailwind styling engine gluestack sits on either way, so we adopt it now
  and generate gluestack components (via its CLI, on macOS) when real screens are
  built in Phase 2.
- **Component render tests deferred to Phase 2.** `@testing-library/react-native`
  v14 + React 19.2 + RN 0.86 don't wire up cleanly headless yet; the render
  harness gets finalized alongside the first real screens (bootable on a Mac).
  Pure-logic tests run in CI today.

## Commands

```bash
npm install
npm start            # Expo dev server (scan QR with a dev client build)
npm run ios          # iOS simulator (macOS only)
npm run android      # Android emulator

# CI gate (mirrors what should run on every push):
npm run typecheck    # tsc --noEmit
npm run lint         # eslint
npm test             # jest
npm run ci           # all three
```

## Layout

```
App.tsx                     SafeAreaProvider > NavigationContainer > RootTabs
src/navigation/tabs.ts      TABS config (single source of truth for the tab set)
src/navigation/RootTabs.tsx bottom-tabs, one native-stack per tab
src/components/Placeholder.tsx  shared empty-state screen (NativeWind styled)
```
