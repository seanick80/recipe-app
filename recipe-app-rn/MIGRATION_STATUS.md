# RN Migration — Status & Handoff

Living handoff doc for the React Native rewrite. **Read this first** when
starting a new conversation on this work. Canonical plan:
`../docs/REACT_NATIVE_MIGRATION_PLAN.md`.

- **Branch:** `react-native` (all RN work lives here; branch off it per phase or
  commit directly during early phases)
- **Location:** `recipe-app-rn/` — sibling folder in the `recipe-app` repo,
  sharing `server/` + `schema/canonical.yaml` with the SwiftUI app
- **Last updated:** end of Phase 3

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
| 1 | Prove Pile 1: port `GroceryCategorizer` + 31 tests to TS | ✅ Done |
| 2 | Auth + networking + read-only Recipes tab | ✅ Done |
| 3 | Local DB + sync spike (expo-sqlite + REST SyncService) — **high risk, do early** | ✅ Done |
| 4 | Full CRUD UI (all tabs, gluestack components) | ⬜ Next |
| 5 | Camera + Vision spike (vision-camera + ML Kit OCR/barcode) — **high risk** | ⬜ |
| 6 | Share Extension + polish + cutover eval | ⬜ |

Front-load the two risk spikes (Phase 3 sync, Phase 5 camera) before the big UI
build so a "no-go" is cheap.

## Cost calibration & discipline

Real anchor (measured via `/cost`): one long, subagent-heavy Opus session that
shipped ~4 workstreams cost **~$29**. The old "~20–40M token" figure is a poor
unit (dominated by cheap cache-replay) — track **dollars**. Rough remaining
projection, wide error bars: Phase 2 ~$15–30, Phase 3 ~$30–60, Phase 4
~$50–100+, Phase 5 ~$30–60, Phase 6 ~$20–40 → **~$150–300 total**. The local
Android emulator should pull Phase 3/5 toward the low end.

Two levers proven by `/cost` — do these:
1. **`/clear` between phases.** ~78% of cost came at >150k context; don't bundle
   phases into one session. Each phase = a fresh session (re-read this doc first).
2. **Use the `migration-scout` subagent (Sonnet), not built-in Explore, for
   search/exploration.** ~95% of cost came from subagent-heavy work; search
   doesn't need Opus. Defined at repo-root `.claude/agents/migration-scout.md`.
   Reserve Opus for porting/implementation; batch investigation into few scouts.

Mechanical `SharedLogic` ports (like Phase 1) are cheap and need no subagents;
cost lives in the iterative spikes (3, 5) and the UI build (4).

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

- **gluestack-ui still deferred (now to Phase 4).** Its CLI is still a v5 alpha,
  interactive and unverifiable headless. Phase 2 screens are built with
  NativeWind-styled RN primitives (`View`/`Text`/`Pressable`/`FlatList`), which
  is enough for a read-only list+detail. Generate gluestack components via its
  CLI on macOS when the full CRUD UI (Phase 4) lands.
- **`expo-sqlite` instead of WatermelonDB** (plan said "WatermelonDB/SQLite").
  Same reasoning as SecureStore: expo-sqlite is a first-party Expo module whose
  config plugin is auto-handled by prebuild (no extra native wiring), it bundles
  and opens headlessly-verifiably, and WatermelonDB's decorator/observable model
  is overkill for ~dozens of recipes. We drive it through a thin
  `RecipeRepository` interface, so swapping the backend later is localized.
- **`expo-secure-store` instead of `react-native-keychain`** (plan said keychain).
  SecureStore is a first-party Expo module — its config plugin is auto-handled by
  prebuild (no extra native config), Keychain-backed on iOS and Keystore-backed on
  Android. Cleaner fit for an Expo dev-client project; same security properties.
- **Component render tests still deferred.** `@testing-library/react-native` v14
  + React 19.2 + RN 0.86 still don't wire up headless. Phase 2 is covered by
  pure-logic unit tests (jwt, apiClient with mocked `fetch`, recipeFormat) +
  `expo export`; finalize the render harness on macOS when convenient.

## Environment gotchas discovered (save future debugging)

- The dev box is **Linux, no iOS simulator** (iOS still needs macOS). But a
  **headless, KVM-accelerated Android emulator is now available** — see the
  shared, repo-independent toolchain at `/home/nicha/src/android/`
  (`README.md` there). Quick start: `source /home/nicha/src/android/env.sh`
  then `start-emulator.sh` → `adb`/`expo run:android`. Cold boots in ~20s;
  drive/verify via `adb` + `adb exec-out screencap`. Reusable for the HERMES
  RN project too. (Non-UI work still verifies fastest via
  typecheck/lint/jest + `expo export`.)
- `babel-preset-expo` had to be added explicitly as a devDep (referenced by
  `babel.config.js`, not auto-installed).
- `@types/jest` globals don't auto-load under `moduleResolution: bundler` +
  the `react-native` custom condition → `tsconfig.json` sets
  `compilerOptions.types: ["jest"]`.
- `*.css` side-effect import needs a module decl (`nativewind-env.d.ts`).
- reanimated v4's babel plugin lives at `react-native-worklets/plugin`.
- **Fabric SIGSEGV on cold launch under swiftshader is flaky, not our bug.**
  Under headless software rendering the RN Fabric renderer intermittently
  crashes on the very first shadow-tree mount (`libreactnative.so`,
  `MountingCoordinator::pullTransaction` — no app/JS frames, no sqlite frames).
  It survives on a relaunch; just retry the launch a few times before
  screencapping. Same class as the Phase 2 Pixel Launcher ANR instability.

## Build / deploy notes (for when there's something to install)

- **No expo.dev account required.** Build via **Codemagic** (recommended —
  reuses existing Apple Distribution cert/profile + App Store Connect key, and
  builds Android too): `npm install → expo prebuild → xcode build-ipa →
  publish TestFlight`. Or build locally on a Mac. EAS Build (cloud) is optional
  and is the only path that needs an Expo account.
- Use a **separate bundle ID** during parallel dev (e.g.
  `com.seanick80.recipeapp.rn`) so it installs alongside the SwiftUI app.
- Device-build config (Codemagic RN workflow / `eas.json`) isn't wired up yet.
  Phase 2 is the first screen worth installing, but on-device verification is
  blocked on two external prerequisites (below) — do these before Phase 4:
  1. **Android Google OAuth client**: native Google sign-in on Android needs an
     Android OAuth client registered in the Google console with the debug (and
     later release) keystore SHA-1. We only have the iOS + web client IDs today.
     Without it, `signIn()` will fail on Android (iOS works with the existing
     iOS client ID + reversed-scheme URL, already configured in `app.json`).
  2. A reachable backend: dev points at `10.0.2.2:8000` on Android / `localhost`
     on iOS (`src/config.ts`), prod at the Cloud Run URL.

## Phase 1 — done

Ported `SharedLogic/GroceryCategorizer` (~564 lines Swift) → TypeScript at
`recipe-app-rn/src/lib/groceryCategorizer.ts`, with its 31-assertion suite
mirrored 1:1 to jest (`groceryCategorizer.test.ts`). `npm run ci` green.

**Porting convention established** (apply to the remaining ~10 `SharedLogic`
modules): one `src/lib/<name>.ts` per Swift module, keep the algorithm and
data tables structurally identical (same ordering/priorities), export named
functions/types, and mirror the Swift `Test*` suite 1:1 as
`src/lib/<name>.test.ts` using jest `describe`/`it.each`.

## Phase 2 — done

Auth + networking + a read-only Recipes tab. `npm run ci` green (79 tests, 44
new); full Metro bundle validated via `expo export`.

**Deps added:** `@react-native-google-signin/google-signin`, `expo-secure-store`
(both via `expo install`; config plugins + iOS reversed-client-ID URL scheme +
separate bundle IDs `com.seanick80.recipeapp.rn` wired in `app.json`).

**What landed** (all under `src/`):

- `config.ts` — API base URL (dev `localhost`/`10.0.2.2`, prod Cloud Run),
  Google client IDs, secure-store key/service. Ports SwiftUI `ServerConfig`.
- `types/recipe.ts`, `types/auth.ts` — wire-format types matching the server's
  `RecipeResponse`/`IngredientResponse` **verbatim in snake_case** (no client
  transform — one fewer place for a mapping bug).
- `lib/apiClient.ts` (+test) — core HTTP: Bearer + User-Agent headers, JSON body,
  3-attempt retry with `2^n`s backoff on 429/5xx only, `ApiError` with typed
  `kind`. Port of SwiftUI `APIClient.performRequest`. Token passed in explicitly.
- `lib/jwt.ts` (+test) — signature-free claim decoder (port of `JWTDecoder`) for
  optimistic session restore.
- `lib/secureStore.ts` — token get/set/delete (SwiftUI `KeychainService` equiv).
- `lib/googleSignIn.ts` — native Google sign-in wrapper (`configure` with
  iosClientId + webClientId=serverClientID, `signIn`, `signOut`).
- `lib/recipeFormat.ts` (+test) — pure display helpers matching SwiftUI list/detail
  rendering (total time, sorted ingredients, quantity/ingredient formatting,
  tag split, http-url check).
- `api/auth.ts`, `api/recipes.ts` — endpoint functions.
- `contexts/AuthContext.tsx` — `AuthProvider`/`useAuth`. Optimistic restore
  (decode claims → render instantly → background `/auth/me` validate → refresh
  on 401 → non-blocking `needsReauth`, never force logout). `signIn`, `signOut`,
  `continueAsGuest`.
- `screens/LoginScreen.tsx` — Google button + "Continue without signing in";
  maps 403 to the SwiftUI "ask Nick for an invite" copy.
- `screens/RecipeListScreen.tsx`, `screens/RecipeDetailScreen.tsx` — read-only
  list (name/star/summary/meta, pull-to-refresh, retry, guest gate) + detail
  (summary, meta, source link, tags, ingredients, instructions).
- `navigation/RecipesStack.tsx` + `RootTabs.tsx` — Recipes tab now real screens;
  other three tabs stay placeholders.
- `App.tsx` — `AuthProvider` + auth gate (loading splash / login / tab shell with
  a `needsReauth` banner).

**Gotchas discovered:**

- ESLint's React-19 `react-hooks/set-state-in-effect` rule fails the build if an
  effect reaches a synchronous `setState`. Pattern used: a pure `async` loader
  (no setState) that the effect `await`s, setting state only after the await;
  synchronous `setState` (spinner on retry/refresh) lives in event handlers.
- Android dev host is `10.0.2.2`, not `localhost` (`src/config.ts` branches on
  `Platform.OS`).

**On-device UI smoke test — PASS (Android emulator, `rn-test`).** `expo
run:android` builds a debug APK with the new native modules (google-signin +
secure-store) and launches it; Metro serves the bundle (1451 modules, no JS
errors in logcat). Verified via adb screencaps: LoginScreen renders (NativeWind
styling correct) → "Continue without signing in" → tab shell (all 4 Ionicons
tabs) → Recipes guest gate ("Sign in to browse recipes from the server.") →
tab switching (Scan placeholder). Android OAuth client is now created in the
Google console (debug keystore SHA-1 `BF:0F:79:…:A3:80`).

**Real Google sign-in + recipe fetch NOT yet exercised** — needs a Google
account signed into the emulator (the `google_apis` image has no Play Store,
making that fiddly) + a reachable backend. Do this on a real device or a
`google_apis_playstore` image. Everything up to the native Google sheet is
verified.

Emulator gotcha: under headless software rendering (`-gpu
swiftshader_indirect`) the Pixel Launcher repeatedly ANRs and draws its dialog
over the app. Our app is unaffected (it stays the resumed activity); to get a
clean screencap, `am force-stop com.google.android.apps.nexuslauncher` then
relaunch `…/.MainActivity` directly. First `expo run:android` also downloads
NDK/build-tools/CMake (~5–6 min); subsequent builds are cached.

## Phase 3 — done

Local DB + sync spike — the highest-risk piece. **Verdict: GO.** The
server-canonical sync model ports cleanly to an offline-first RN client; the
full algorithm is unit-tested headlessly and the local DB opens on a real
Android device. `npm run ci` green (98 tests, 19 new); Android bundle exported
clean (`expo export`); on-device smoke passed.

**Dep added:** `expo-sqlite` (~57.0.0, via `expo install`; config plugin +
prebuild auto-wired — see the deviation note above).

**What landed** (all under `src/`, plus one `app.json` plugin entry):

- `sync/types.ts` — `LocalRecipe` (wire content in snake_case + camelCase sync
  metadata), `RecipeInput`, `RecipeListItem`, and the two interfaces the sync
  algorithm is pure over: `RecipeRepository` + `SyncApi` (plus `SyncEnv` =
  injected clock/id, `SyncResult`).
- `db/schema.ts` — normalized SQLite DDL (`recipes` + `ingredients`, cascade),
  `PRAGMA user_version` migration versioning.
- `db/database.ts` — lazy memoised `openDatabaseAsync` + WAL + `foreign_keys`,
  runs migrations on first open.
- `db/sqliteRecipeRepo.ts` — `RecipeRepository` over expo-sqlite; recipe +
  ingredients written atomically in a transaction, ingredients always
  delete-all + re-insert (server/SwiftUI strategy).
- `sync/syncService.ts` — the spike. Faithful port of SwiftUI `SyncService.swift`
  (all 9 scenarios in `docs/sync-execution-plan.md`): `sync()` →
  first-sync **or** pull→push→processDeletions, then purge. Pure over
  repo + api + env, so it's fully testable without native modules.
- `sync/memoryRepo.ts` — clone-on-read/write in-memory repo (test double).
- `api/recipes.ts` — added `fetchRecipeList` (lightweight `?fields=id,updated_at`),
  `createRecipe`/`updateRecipe`/`deleteRecipe`, and `createSyncApi(token)` factory.
- `contexts/SyncContext.tsx` — owns the SQLite repo + `SyncService`; offline-first
  store; syncs on auth + app-foreground (`AppState`) + pull-to-refresh; exposes
  `recipes`/`syncing`/`error`/`hasWriteFailures`/`syncNow`/`getByLocalId`.
- `screens/RecipeListScreen.tsx` + `RecipeDetailScreen.tsx` — now read the local
  store (no network fetch); list has a needs-sync glyph + error/write-failure
  banners; `RecipesStack` param is `localId`, not the wire `id`.
- `sync/syncService.test.ts` — **19 tests**: all 9 scenarios + delete-failure
  (network vs 404) + purge + forceFullSync + first-sync guard + mappers.

**Two deliberate improvements over the iOS port** (documented inline in
`syncService.ts`):

1. **Sync watermark = server's `updated_at`, not device `now()`.** The
   "server is newer" check compares two server-clock timestamps, so it's immune
   to device clock skew (iOS compared a server timestamp against a local
   `Date()`, which can loop or miss under skew).
2. **A `pendingRemoteDelete` flag separates user deletes from server-detected
   deletes.** iOS conflated both under `locallyDeleted` and re-issued a
   redundant DELETE for server-side deletions, so a web-deleted recipe never
   actually rested in "Recently Deleted." The flag makes Scenario 7 behave as
   the spec documents (soft-delete locally, linger 30 days, no re-push).

**On-device smoke — PASS (Android emulator, `rn-test`).** `expo run:android`
built + installed a debug APK with the expo-sqlite native module; guest flow →
tab shell mounts `SyncProvider` → `libexpo-sqlite.so` loaded and `recipes.db`
(+ `-wal`/`-shm`) created on device with the schema migrated, no errors. Real
Google sign-in + server sync still not exercised on-device (same blockers as
Phase 2: no Play Store on the `google_apis` image + a reachable backend); the
full push/pull/conflict/delete logic is covered by the headless unit tests
instead. Verify true two-device sync on a real device or `_playstore` image
when convenient.

## Next action (Phase 4)

Full CRUD UI on gluestack-ui (generate its components via the CLI on macOS — see
the deferral note). The offline-first store + `SyncService` from Phase 3 are the
data layer the CRUD screens write through: a create/edit sets `needsSync = true`
and a swipe-delete sets `locallyDeleted = true` + `pendingRemoteDelete = true`
on the local record; the next `sync()` (already wired for foreground +
pull-to-refresh) pushes them. Port remaining Pile 1 `SharedLogic` modules as
their consumers come online.
