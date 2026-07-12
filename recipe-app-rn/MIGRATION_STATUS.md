# RN Migration — Status & Handoff

Living handoff doc for the React Native rewrite. **Read this first** when
starting a new conversation on this work. Canonical plan:
`../docs/REACT_NATIVE_MIGRATION_PLAN.md`.

- **Branch:** `react-native` (all RN work lives here; branch off it per phase or
  commit directly during early phases)
- **Location:** `recipe-app-rn/` — sibling folder in the `recipe-app` repo,
  sharing `server/` + `schema/canonical.yaml` with the SwiftUI app
- **Last updated:** RN iOS → TestFlight pipeline fully working + robust (2026-07-13; modular-headers + export-compliance + non-fatal-publish fixes landed). Next: finish Phase 5 headless parser ports, then adopt gluestack (planned eval). Native camera spike deferred to its own device session. See "Suggested next session".

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
| 4 | Full CRUD UI (all tabs) | 🔄 Nearly done — Recipes, Shopping, Lists, Settings all real ✅; UnitPicker + polish ⬜ |
| 5 | Camera + Vision spike (vision-camera + ML Kit OCR/barcode) — **high risk** | 🔄 Started — vision parsers porting; native camera device-blocked |
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

- **gluestack-ui dropped for Phase 4 (decision 2026-07-10).** Its CLI is a v5
  alpha, interactive and unverifiable headless (macOS-only). Rather than block
  Phase 4 on a Mac, the CRUD UI continues on NativeWind-styled RN primitives
  (`View`/`Text`/`Pressable`/`FlatList`/`TextInput`/`Switch`) — buildable AND
  verifiable on this box (typecheck/lint/jest + `expo export` + emulator).
  gluestack can still be adopted later as a pure styling pass if desired; it is
  not a data-layer dependency.
  **UPDATE (2026-07-13): the original blocker is gone.** It was "can't verify
  without a Mac"; on-device verification now exists (TestFlight installs + the
  Codemagic mac build both work). gluestack is a **planned deliverable** — the
  port doubles as a gluestack evaluation for a separate work project, so adopt
  it deliberately, not just "if desired". Readiness: architecturally yes —
  NativeWind (its styling engine) is already installed/configured, the data
  layer is decoupled, and screens are componentized for an incremental
  screen-by-screen swap (`View`/`Text`/`Pressable`/`TextInput`/`Switch` →
  gluestack `Box`/`Text`/`Button`/`Input`/`Switch`). **The one remaining risk to
  de-risk first is version compat**: gluestack-ui alpha vs this bleeding-edge
  stack (React 19.2 / RN 0.86 / Expo 57 / NativeWind 4.2). Do a **compat spike**
  (install + convert ONE screen, e.g. `RecipeEditScreen` → verify via
  `expo export` / Codemagic build / on-device) before the full pass. Also note
  headless component render tests still don't wire up (RNTL v14 + React 19.2), so
  gluestack components are verified visually on-device, not by unit tests.
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

## Build / deploy notes

**Both RN workflows are wired into the repo's `codemagic.yaml`** (no expo.dev
account / EAS needed — reuses the existing Apple Distribution cert + ASC key).

- **`rn-ios-workflow`** — ✅ **proven working (2026-07-12)**. `mac_mini_m2`,
  **manual-trigger only** (start from the Codemagic dashboard; select the
  `react-native` branch). Flow: `npm ci → expo prebuild → pod install →
  build-ipa → app-store-connect publish --testflight`. Installs side-by-side
  with the SwiftUI app under bundle `com.seanick80.recipeapp.rn`.
  Apple-side setup done: `.rn` App ID registered, App Store provisioning profile
  uploaded to Codemagic as `ios_rn_distribution_profile`, ASC app record created
  (SKU `com.seanick80.recipeapp.rn.sku`). Signing reuses `ios_distribution_cert`.
  Two build-time fixes were needed and are now permanent (2026-07-13):
    - **Modular headers** — `plugins/withModularHeaders.js` (registered in
      `app.json`) injects `use_modular_headers!` into the generated Podfile;
      without it `pod install` fails because GoogleSignIn→AppCheckCore depends on
      non-modular pods (GoogleUtilities, RecaptchaInterop) that can't integrate
      as static libraries. Chosen over `useFrameworks:"static"` (riskier with
      Hermes + reanimated).
    - **Export compliance** — `ios.infoPlist.ITSAppUsesNonExemptEncryption=false`
      in `app.json` auto-clears `MISSING_EXPORT_COMPLIANCE` so internal testers
      get each build without manual per-build answering (app uses only standard
      HTTPS/TLS → exempt).
    - **Publish step** tolerates external beta-review gaps (non-fatal) — the IPA
      upload is what matters; internal testing needs no beta review. Fill in Test
      Info + Beta App Review contact in ASC only if enabling *external* testers.
  Install path for a comparison build: TestFlight → add yourself as an *internal*
  tester → install. No external review needed.
- **`rn-android-workflow`** — wired but **dormant**: `linux_x2`, auto-triggers on
  `master` pushes touching `recipe-app-rn/`, publishes a debug-signed release APK
  artifact for sideloading. Won't fire until `react-native` merges to `master`.
  TODO before a real Android release: (a) generate an upload keystore + wire it
  into `signingConfigs.release`; (b) register an **Android Google OAuth client**
  in the Google console with that keystore's SHA-1 — until then `signIn()` fails
  on Android and only "Continue without signing in" works. iOS sign-in already
  works with the existing iOS client ID + reversed-scheme URL.
- Both workflows are `when.changeset`-scoped, so SwiftUI and RN never trigger
  each other's builds. See `codemagic.yaml` for the full definitions.
- Backend: dev points at `10.0.2.2:8000` on Android / `localhost` on iOS
  (`src/config.ts`); release builds (`__DEV__=false`) auto-target the Cloud Run
  URL, so TestFlight/APK builds need no backend config.

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

## Phase 4 — in progress

Full CRUD UI on NativeWind primitives (gluestack dropped — see deviation).
Built in slices; the offline-first store + `SyncService` from Phase 3 are the
data layer every write goes through.

### Slice 1 — Recipe CRUD ✅ (2026-07-10)

Create / edit / delete recipes, writing through the Phase 3 store. `npm run ci`
green (**106 tests**, 8 new); Android bundle exported clean.

**What landed** (all under `src/`):

- `sync/recipeDraft.ts` (+`.test.ts`, 8 tests) — pure, React-free form helpers:
  `emptyDraft`/`localToDraft`/`cleanDraft`/`validateDraft`/`isDraftValid`,
  `draftToNewLocal` (create → `needsSync=true`, `serverId=null`),
  `applyDraft` (edit → merge content, `needsSync=true`, preserve identity +
  `createdAt` + `lastSyncedAt`), `markDeleted` (soft-delete +
  `pendingRemoteDelete=true`). The editable payload IS `RecipeInput`, so a draft
  round-trips to the API with no re-mapping. `cleanDraft` renumbers ingredient
  `display_order` by row position and drops blank-named rows (matches SwiftUI).
- `contexts/SyncContext.tsx` — added `createRecipe`/`updateRecipe`/`deleteRecipe`:
  persist → refresh the list immediately → kick a background `syncNow()` to push
  (no-op for guests/offline; the record keeps its flags and retries next sync).
- `screens/RecipeEditScreen.tsx` — the create/edit form (port of SwiftUI
  `RecipeEditView`): name/summary/instructions, free-text cuisine/course/
  difficulty, comma-separated tags, source_url, ±steppers for prep/cook
  (0–480, step 5) + servings (1–50), and an ingredient editor (add/remove/
  move-up-down; qty kept as a string buffer so decimals type correctly, parsed
  on save). Header Save is disabled until name is non-empty.
- `screens/RecipeListScreen.tsx` — header "+" (create, authed only);
  long-press a row → confirm → delete (no gesture-handler dep, so long-press
  rather than swipe).
- `screens/RecipeDetailScreen.tsx` — header Edit + Delete.
- `navigation/RecipesStack.tsx` — `RecipeEdit` route (`localId?` — present=edit,
  absent=create), presented modally.

**Deviations from the SwiftUI original** (both minor, documented inline):
- **Added a Favorite toggle in the edit form.** iOS has *no* way to set
  `is_favorite` from its UI (read-only star only, per the port scout); the RN
  form exposes it via the normal draft → `needsSync` → PUT path.
- **Ingredient `category` is preserved on edit** (iOS silently reset it to
  "Other" because its edit form dropped category on load). Category still isn't
  user-editable (no picker yet — folded into the deferred UnitPicker work).

**Not driven on-device this slice.** Create/edit/delete UI sits behind the auth
gate, and this emulator has no real Google sign-in (no Play Store on the
`google_apis` image) — same blocker as Phases 2–3. Coverage is CI (repo writes +
form logic) + `expo export` + the Phase 3 on-device DB proof. Drive the CRUD
flow end-to-end on a real device / `_playstore` image + reachable backend.

### Slice 2 — Settings ✅ (2026-07-10)

Surfaces the Phase 3 sync engine that nothing displayed until now, plus account.
`npm run ci` green (106 tests); Android bundle exported clean; **on-device smoke
PASSED** (emulator, guest path — Settings tab renders, no crash).

**What landed:**

- `contexts/SyncContext.tsx` — exposed `lastSyncedAt`, `deletedRecipes`
  (Recently Deleted), `restoreRecipe(localId)`, and `forceFullSync()`; a shared
  `applyResult` folds any sync's outcome into state and stamps `lastSyncedAt`;
  `refresh` now populates both the active + deleted lists.
- `screens/SettingsScreen.tsx` — Account (name/email/role + Sign out, or a guest
  sign-in prompt), Sync (last-synced time, Sync Now, Force Full Sync, error /
  write-failure / last-result summary), and Recently Deleted with per-row
  Restore. Guests see only the account prompt.
- `navigation/SettingsStack.tsx` + `RootTabs.tsx` — **Settings is now a 5th tab**
  (Recipes/Shopping/Scan/Lists/Settings). `RootTabs` maps real stacks via a
  `REAL_STACKS` lookup (Recipes, Settings); the rest stay placeholders.
- `tabs.ts` (+ updated `tabs.test.ts`, now asserts 5 tabs).

**Restore caveat (documented inline):** restoring re-queues the recipe with
`needsSync=true`. If its server-side deletion already synced and the row was
hard-purged, the re-push PUT may 404 (surfaced as a write-failure); the local
copy is always preserved. A future pass can use the server restore endpoint /
re-create path for that edge.

### Slice 3 — Grocery / Lists (local-only) ✅ (2026-07-10)

Decision (2026-07-10): Shopping/Grocery are **local-only** — not server-synced
(the server only syncs recipes). So these models live only in device SQLite with
no sync metadata. `npm run ci` green (**124 tests**, 18 new); bundle exports clean.

**What landed:**

- `lib/prepNoteStripper.ts` (+8 tests) — 1:1 port of `SharedLogic/PrepNoteStripper`
  (strips "chopped", "large", "(1 cup)" etc. from ingredient names). Needed by
  generate-from-recipes. (Second Pile-1 module ported, after GroceryCategorizer.)
- `grocery/types.ts` — `ShoppingTemplate`/`TemplateItem`/`GroceryList`/`GroceryItem`
  (ports of the SwiftUI @Models, no sync metadata) + `GenerateRecipe`.
- `grocery/groceryLogic.ts` (+10 tests) — the pure core: `CATEGORY_ORDER` +
  `categorySortIndex` (SwiftUI store-aisle order), `groupByCategory`
  (unchecked-first then name), `makeGroceryItem` (auto-categorize), `staplesToAdd`
  (name-dedup), `mergeInto` (name|unit sum + unchecked-wins), and the two-stage
  `generateFromRecipes` consolidation (strip → categorize → sum-when-units-match →
  union provenance).
- `db/schema.ts` + `db/database.ts` — **schema v2** (incremental migration): 4 new
  tables (`grocery_lists`, `grocery_items`, `shopping_templates`, `template_items`).
- `grocery/groceryRepo.ts` — `SqliteGroceryRepo` (aggregates; item sets written
  wholesale in a transaction).
- `contexts/GroceryContext.tsx` — the local store + all list/item/template/merge/
  generate operations. No auth gate (grocery works for guests too).
- `lib/ids.ts` — shared `newLocalId` (extracted from SyncContext; both use it).
- **Lists tab now real** (`navigation/ListsStack.tsx` + `RootTabs` REAL_STACKS):
  `GroceryListsScreen` (all lists + create + generate entry), `GroceryListDetailScreen`
  (category-grouped, tap-to-check, inline add bar, uncheck/remove-checked/clear
  menu), `GenerateGroceryListScreen` (multi-select recipes → new list).

### Slice 3b — Shopping (staples) tab ✅ (2026-07-11)

The staples workflow (port of SwiftUI `ShoppingListTab`). All four content tabs
are now real screens. `npm run ci` green (124 tests); bundle exports clean.

- Extracted `components/GroceryListBody.tsx` (inline add bar + category-grouped
  checkable rows) — shared by the Lists-tab detail and the Shopping tab, so the
  item UI isn't duplicated. `GroceryListDetailScreen` slimmed to it + its menu.
- `screens/ShoppingScreen.tsx` — operates on the first active list: header menu
  for Add Staples / Edit Staples / Merge active lists / Archived Lists; empty
  state offers "add staples to a new list" / "new empty list".
- `screens/TemplateEditorScreen.tsx` — edit the default "Weekly Staples"
  template (add/remove rows; qty string buffer; Save via `setTemplateItems`).
- `screens/ArchivedListsScreen.tsx` — archived lists with Restore + long-press
  delete.
- `navigation/ShoppingStack.tsx` + `RootTabs` REAL_STACKS (Shopping now real).

### Remaining Phase 4 slices ⬜

- **List rename** — manual lists are created as "Grocery List"/"Groceries"; add
  rename (needs a small cross-platform text-input modal — `Alert.prompt` is
  iOS-only). Multi-select merge in the Lists tab (Shopping tab merges all active).
- **UnitPicker** — the shared unit menu (recipeUnits + "Other…" free-text);
  wire into the recipe + grocery ingredient rows (currently free-text unit).
  Carries the ingredient `category` picker too.
- Port remaining Pile 1 `SharedLogic` modules as their consumers come online.

## Phase 5 — started (camera + vision spike)

High-risk spike: `react-native-vision-camera` + ML Kit for barcode + OCR, wired
to ported framework-free parsers. **The native camera half is device-blocked** —
the KVM Android emulator's virtual camera can't present a real barcode/text
target and there's no iOS simulator, so on-device camera verification needs a
**physical Android device** (or a Mac). The parser half is fully portable +
headless-testable, so that's what's landed first.

**All 14 `SharedLogic` modules import only Foundation** (scout-confirmed — zero
UIKit/Vision/AVFoundation), so every parser ports cleanly.

### Ported so far ✅ (2026-07-11)
- `lib/barcodeProductMapper.ts` (+10 tests) — Open Food Facts JSON → product
  (`parseOpenFoodFactsJSON`, `mapOFFCategory`, `formatProductDisplay`).
- `lib/contentDetector.ts` (+4 tests) — `detectContentType` (recipe vs shopping).
- `lib/fuzzyMatcher.ts` (+9 tests) — `editDistance`, `suggestCorrection`,
  `groceryVocabulary` (post-OCR handwriting correction).

### Remaining parser ports ⬜ (leaf-first; do next, still headless)
- `QualityGate` — `OCRLine`/`NormalizedBox` (the Vision→pure boundary),
  `assessImageQuality`, `separateHandwritten`, `sectionFromHeader` +
  `RecipeSection`, `looksLikeNumberedInstruction`/`looksLikeIngredientStart`.
  **This is what the real recipe pipeline routes on**, not ZoneClassifier.
- `ListLineParser` — `parseShoppingListText`/`parseListLine` (qty+unit+name
  grammar; fused tokens, fractions). Core of the shopping-list OCR deliverable.
- `OCRParser` — `parseRecipeText`/`parseIngredientLine` (depends on
  `ListLineParser.parseListLine`). Core of the recipe OCR deliverable.
- `ZoneClassifier`, `DetectionClassifier` — port for parity/tests only; see below.

### Scout findings that change the port (don't port 1:1 blindly)
- **`BarcodeProductMapper` is unused in the SwiftUI app** — `BarcodeViewModel`
  duplicates the OFF parsing inline. In RN, wire the barcode lookup to the ported
  module (cleaner, its original intent). RN does its own `fetch()` to
  `world.openfoodfacts.org/api/v2/product/{barcode}.json` → `parseOpenFoodFactsJSON`.
- **`ZoneClassifier` is NOT in the real recipe pipeline** — `ScanProcessor` uses
  `QualityGate.sectionFromHeader` + heuristics (an earlier geometric-zone approach
  was abandoned: dense screenshots fused into one block). The plan lists
  ZoneClassifier for Phase 5, but mirror `QualityGate` header-routing for parity.
- **`DetectionClassifier`** was Pantry/CoreML-only → Pantry is dropped; no RN
  consumer. Port only if reused.

### Native spike plan (needs a device)
- **Barcode (do first — simplest):** vision-camera v4 built-in
  `useCodeScanner`/`CodeScanner` (no frame-processor plugin; ML Kit on Android) →
  on decode, `fetch` OFF → `parseOpenFoodFactsJSON` → add to a grocery list.
- **OCR:** match the SwiftUI UX — capture a **still**, then run ML Kit text
  recognition on it (e.g. `@react-native-ml-kit/text-recognition`), NOT a live
  frame processor (avoids Worklets/Reanimated complexity). Feed recognized lines
  → `QualityGate` (quality/handwritten/section) → `ListLineParser`/`OCRParser` +
  `fuzzyMatcher` + `groceryCategorizer` + `contentDetector` + `prepNoteStripper`.
- vision-camera needs a config plugin in `app.json` + a **dev-client rebuild**
  (`expo prebuild`/`run:android`) — same native-config workflow as the Google
  sign-in / secure-store plugins added in Phase 2. Camera permission strings too.

### Suggested next session
**Decided ordering (2026-07-13): parser ports → gluestack; native camera spike
deferred.** Rationale: the user's priority is evaluating gluestack (for a
separate work project), and the native camera spike is device-gated + iterative
(not a clean single-session deliverable).

1. **Fresh `/clear`. Parser ports** — QualityGate → ListLineParser → OCRParser,
   all headless + Jest-tested (OCRParser depends on ListLineParser). This
   completes the *portable* half of Phase 5. Decide ZoneClassifier-vs-QualityGate
   routing during the eventual OCR wire-up (mirror `QualityGate.sectionFromHeader`
   per the scout finding above; ZoneClassifier is NOT in the real pipeline).
2. **Fresh `/clear`. gluestack** — compat spike first (one screen), then adopt as
   a styling pass if clean. See the gluestack UPDATE note in "Deviations from the
   plan" above for readiness + the version-compat risk.

**Deferred (own device-gated session):** native camera spike — barcode first
(vision-camera `useCodeScanner` → OFF lookup), then OCR (still capture → ML Kit
text recognition → QualityGate → parsers). Now unblocked by on-device TestFlight
installs (previously needed a physical device; the iPhone qualifies).
