# RN Migration — Status & Handoff

Living handoff doc for the React Native rewrite. **Read this first** when
starting a new conversation on this work. Canonical plan:
`../docs/REACT_NATIVE_MIGRATION_PLAN.md`.

- **Branch:** `react-native` (all RN work lives here; branch off it per phase or
  commit directly during early phases)
- **Location:** `recipe-app-rn/` — sibling folder in the `recipe-app` repo,
  sharing `server/` + `schema/canonical.yaml` with the SwiftUI app
- **Last updated:** end of Phase 0

## Where the app came from

Re-implementation (not a port) of the SwiftUI app in `RecipeApp/`
(~7,700 lines app Swift + ~3,600 lines framework-free `SharedLogic/`). The
SwiftUI app stays the shipping app; RN is built in parallel until a deliberate
cutover. **Pantry is dropped** from the RN app (on-device food classification —
not worth porting).

## Phase status

| Phase | What | Status |
|---|---|---|
| 0 | Decision + scaffold (Expo/TS/nav/styling, 4 empty tabs, CI) | ✅ Done |
| 1 | Prove Pile 1: port `GroceryCategorizer` + 31 tests to TS | ⬜ Next |
| 2 | Auth + networking + read-only Recipes tab | ⬜ |
| 3 | Local DB + sync spike (WatermelonDB/SQLite + REST SyncService) — **high risk, do early** | ⬜ |
| 4 | Full CRUD UI (all tabs, gluestack components) | ⬜ |
| 5 | Camera + Vision spike (vision-camera + ML Kit OCR/barcode) — **high risk** | ⬜ |
| 6 | Share Extension + polish + cutover eval | ⬜ |

Rough total token estimate for the whole migration: **~20–40M** (Phase 0 was a
small fraction). Front-load the two risk spikes (Phase 3 sync, Phase 5 camera)
before the big UI build so a "no-go" is cheap.

## What Phase 0 delivered

- Expo SDK 57 + TypeScript scaffold (dev-client oriented)
- React Navigation: bottom-tabs + a native-stack per tab
- 4-tab shell (**Recipes, Shopping, Scan, Lists**) from a single `TABS` config
  in `src/navigation/tabs.ts`
- NativeWind v4 styling wired through babel + metro
- CI gate `npm run ci` → typecheck + eslint + jest (4/4 green)
- Validated headlessly with a full Metro bundle (`expo export`) — the box has no
  iOS/Android simulator, so booting is done on macOS

See `README.md` for stack table, decisions, and commands.

## Deviations from the plan (deliberate)

- **gluestack-ui deferred to Phase 2.** Its current CLI is a v5 *alpha* on
  Tailwind v4, interactive and unverifiable headless. NativeWind (the engine
  gluestack sits on) is in now; generate gluestack components via its CLI on
  macOS when real screens land.
- **Component render tests deferred to Phase 2.** `@testing-library/react-native`
  v14 + React 19.2 + RN 0.86 don't wire up headless (render returns an empty
  result). Finalize the render harness alongside the first real screens.

## Environment gotchas discovered (save future debugging)

- The dev box is **Linux, no iOS/Android simulator** — verify via
  typecheck/lint/jest + `expo export`; boot on macOS.
- `babel-preset-expo` had to be added explicitly as a devDep (referenced by
  `babel.config.js`, not auto-installed).
- `@types/jest` globals don't auto-load under `moduleResolution: bundler` +
  the `react-native` custom condition → `tsconfig.json` sets
  `compilerOptions.types: ["jest"]`.
- `*.css` side-effect import needs a module decl (`nativewind-env.d.ts`).
- reanimated v4's babel plugin lives at `react-native-worklets/plugin`.

## Build / deploy notes (for when there's something to install)

- **No expo.dev account required.** Build via **Codemagic** (recommended —
  reuses existing Apple Distribution cert/profile + App Store Connect key, and
  builds Android too): `npm install → expo prebuild → xcode build-ipa →
  publish TestFlight`. Or build locally on a Mac. EAS Build (cloud) is optional
  and is the only path that needs an Expo account.
- Use a **separate bundle ID** during parallel dev (e.g.
  `com.seanick80.recipeapp.rn`) so it installs alongside the SwiftUI app.
- Device-build config (Codemagic RN workflow / `eas.json`) isn't needed until
  ~end of Phase 2 (first real screen worth installing).

## Next action (Phase 1)

Port `SharedLogic/GroceryCategorizer` (Swift, ~564 lines) → TypeScript under
`recipe-app-rn/src/lib/`, and port its 31-test suite to jest. This establishes
the porting + test-mirroring convention for the remaining ~10 `SharedLogic`
modules.
