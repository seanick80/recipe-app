# React Native + gluestack-ui Migration Plan

**Status:** Proposal
**Author:** (drafted with Claude Code)
**Date:** 2026-07-05

## Goal

Evaluate and (optionally) execute a rewrite of the SwiftUI iOS app as a
React Native app using **gluestack-ui** for the component layer, primarily to
gain Android support and converge on a TypeScript codebase shared with the
existing web `frontend/`.

This is a **re-implementation, not a port**. Three subsystems that SwiftUI and
Apple frameworks provide for free today become code we own. This plan sequences
the work so the risky subsystems are proven early, and so the existing Swift app
stays shippable the entire time.

## Non-goals

- Retiring the SwiftUI app before the RN app reaches feature parity. Both ship
  in parallel until a deliberate cutover decision.
- Migrating in place. The RN app lives in a **separate location** (see below).
- Changing the backend (`server/`) or canonical schema (`schema/canonical.yaml`).
  Both are reused as-is; the RN client is just another consumer.
- **Reimplementing the Pantry feature.** Pantry (inventory, camera food
  detection via the `FoodClassifier` CoreML model, detection-review flow) is
  **dropped** from the RN app. It isn't working well today and isn't worth
  porting. This removes the single hardest subsystem (on-device CoreML/TFLite
  food classification) from scope entirely. New features the RN app should carry
  instead are tracked separately (see `BACKLOG.md`).

## Where it lives

A **separate repo** (`seanick80/recipe-app-rn`) or a **sibling folder**
(`recipe-app-rn/`) — not in `RecipeApp/`. Rationale:

- SwiftUI app stays untouched and shippable during the entire build-out.
- Clean git history, separate CI, separate `package.json` — no entanglement
  with the xcodegen / Codemagic / provisioning pipeline.
- The `server/` and `schema/canonical.yaml` are shared by both clients without
  either owning the other.

Recommendation: **separate repo** if the RN app will have its own release
cadence; **sibling folder** if we want to keep sharing schema + server in one
checkout during early development. Start as a sibling folder, split to its own
repo at the first release.

## The three piles

The ~10,500 lines of app Swift (excluding tests) split into three buckets with
very different effort/risk profiles.

### Pile 1 — Free wins: `SharedLogic/` (~3,400 lines)

The 13 modules under `SharedLogic/` are already pure, framework-free Swift
(they compile with `swiftc` on Windows by design). Porting to TypeScript is
mechanical — pure functions, pure data. Their `TestFixtures/` suites (300 tests)
port to Jest as the safety net.

| Module | Lines | Notes |
|---|---|---|
| RecipeSchemaParser | 618 | JSON-LD / Schema.org extraction from HTML |
| GroceryCategorizer | 564 | Aisle categorization (exact/suffix/compound match) |
| QualityGate | 384 | Image quality + handwriting gating for OCR |
| ListLineParser | 289 | OCR lines → structured list items |
| OCRParser | 276 | OCR text → recipe fields |
| ZoneClassifier | 260 | OCR blocks → recipe zones |
| DebugLog | 223 | On-device JSONL logger w/ rotation |
| ~~PantryItemMapper~~ | ~~197~~ | **Dropped — Pantry out of scope** |
| PrepNoteStripper | 153 | Strip prep notes from ingredient names |
| ~~DetectionClassifier~~ | ~~136~~ | **Dropped — Pantry food-detection triage** |
| FuzzyMatcher | 130 | Edit-distance post-OCR correction |
| BarcodeProductMapper | 130 | Open Food Facts JSON → product info |
| ContentDetector | 78 | List-vs-recipe classification |

Two modules (`PantryItemMapper`, `DetectionClassifier`) exist only to support
Pantry food detection and are not ported. That leaves **11 modules (~3,100
lines)** to port.

**Effort: low. Risk: low.** This is where RN/TS is actively easier than Swift.

### Pile 2 — Straightforward re-implementation: UI + nav + networking (~5,100 lines)

~3,657 lines of SwiftUI Views, plus `APIClient` (232), `AuthService` (248),
`KeychainService` (44), `ServerConfig` (9). Different idioms, no fundamental
obstacle. This is where gluestack-ui lives.

| Today (SwiftUI) | RN + gluestack-ui |
|---|---|
| `ContentView` `TabView` (was 5 tabs; **4 without Pantry**) | React Navigation bottom-tabs |
| Per-tab `NavigationStack` + `NavigationLink` | Native-stack navigator per tab |
| `.sheet` modals | gluestack `Modal` / `Actionsheet` / bottom-sheet |
| Recipe/grocery/shopping forms | gluestack `Input`, `Select`, `Checkbox`, `Button` + `FlatList` |
| `UnitPicker` | gluestack `Select` / `Actionsheet` |
| `LoginView` | `@react-native-google-signin` + gluestack layout |
| `APIClient` (URLSession) | `fetch`/axios client, same REST endpoints |
| `KeychainService` | `react-native-keychain` |
| `AuthService` (GIDSignIn → JWT) | `@react-native-google-signin` → same `auth/mobile/google` exchange |

**Effort: medium. Risk: low.** gluestack-ui is a good fit — Tailwind-style
`className` styling, and RN-Web support means potential convergence with the
existing React `frontend/`. But gluestack is only ~15% of total effort; it does
nothing for Piles 3.

### Pile 3 — The hard pile: two things Apple gave us for free

**3a. Persistence + sync.** There is no RN equivalent to "declare `@Model`, get
automatic cross-device iCloud sync." Replacement:

- Local DB: **WatermelonDB** or **op-sqlite + Drizzle** for the `@Model` types
  (Recipe/Ingredient, GroceryList/GroceryItem, ShoppingTemplate/TemplateItem).
  PantryItem is dropped with the Pantry feature.
- Cross-device sync: lean entirely on the existing custom REST `SyncService`
  (488 lines) + backend. We already have this — it pushes `needsSync` changes,
  pulls remote, handles conflicts (`isConflictedCopy`) and soft-deletes
  (`locallyDeleted`). CloudKit's free device-sync becomes our server's job.
- Share Extension → App Group hand-off (`PendingImportService`) becomes an
  iOS Share Extension target in RN (heavier) or is deferred.

**3b. Camera / Vision.** Barcode and OCR lean on Apple frameworks. Replacements
— each is its own project:

| Today | RN replacement |
|---|---|
| AVFoundation `AVCaptureSession` | `react-native-vision-camera` |
| Vision `VNRecognizeTextRequest` (OCR) | ML Kit text recognition (frame processor) |
| Vision `VNDetectBarcodesRequest` | ML Kit barcode scanning |

**Effort: high. Risk: high (reduced).** Dropping Pantry removes the CoreML
`FoodClassifier` — the hardest single item (TFLite conversion / server-side
inference) is no longer in scope. What remains is camera capture + OCR + barcode,
all of which have mature RN libraries.

## Phases

Each phase ends in something runnable. Risky subsystems (Pile 3) are proven with
spikes *before* committing to the full UI build.

### Phase 0 — Decision + scaffold (small)
- Decide: separate repo vs sibling folder; Expo (with dev client, for native
  modules) vs bare RN. **Recommend Expo + dev client** — camera/ML modules need
  native code but Expo's prebuild handles it.
- Scaffold: Expo + TypeScript + gluestack-ui + React Navigation (bottom-tabs +
  native-stack). One placeholder tab. CI: install → typecheck → eslint → jest.
- Deliverable: app boots on iOS + Android simulators with 4 empty tabs
  (Recipes, Shopping, Scan, Lists — no Pantry).

### Phase 1 — Prove Pile 1 (small)
- Port **GroceryCategorizer** to TS + its Jest suite (31 tests) as the pattern.
- Establish the porting + test-mirroring convention for the remaining 12 modules.
- Deliverable: green Jest suite; a documented port recipe.

### Phase 2 — Auth + networking + read-only UI (medium)
- `@react-native-google-signin` → `auth/mobile/google` → JWT in
  `react-native-keychain`. Session restore via `/auth/me`.
- Port `APIClient`; build the **Recipes** tab read-only (list + detail) against
  the live server. gluestack components throughout.
- Deliverable: sign in, browse recipes from the server on both platforms.

### Phase 3 — Local DB + sync spike (large, high-risk — do early)
- Stand up WatermelonDB/SQLite with the model schema.
- Wire the existing REST `SyncService` semantics (push/pull/conflict/soft-delete)
  from the client side against the real backend.
- Deliverable: create/edit a recipe offline on device A, see it on device B.
  **This validates the single biggest CloudKit replacement — do not defer it.**

### Phase 4 — Full CRUD UI (large)
- Port remaining Pile 1 modules as their consumers come online.
- Build out all tabs: Recipes (edit/create), Shopping (templates/lists/merge/
  archive), Grocery (grouped/check-off/generate-from-recipes), Settings,
  UnitPicker. All on gluestack-ui. (No Pantry tab.)
- Deliverable: feature parity minus camera/scan.

### Phase 5 — Camera + Vision spike (large, high-risk)
- `react-native-vision-camera` capture; ML Kit OCR + barcode via frame
  processors; wire to ported `OCRParser`/`ListLineParser`/`ZoneClassifier`/
  `BarcodeProductMapper`.
- Deliverable: barcode scan → product lookup; photo → OCR → parsed recipe/list.

_(Former Phase 6 — Food classifier / Pantry — removed: Pantry is out of scope.)_

### Phase 6 — Share Extension + polish + cutover eval (medium)
- iOS Share Extension target (Safari → HTML → `RecipeSchemaParser` →
  pending import). Android share intent equivalent.
- i18n, empty states, error handling, deep-linking parity.
- Deliverable: parity reached; decide dual-ship vs cutover.

#### Share import — platform design (decided)

The two platforms diverge completely; the recipe-extraction *brain*
(`RecipeSchemaParser`, already ported to TS) is shared, but the share *plumbing*
is native and per-platform.

**iOS — reuse the existing Swift extension.** The SwiftUI app's
`RecipeApp/ShareExtension/ShareViewController.swift` is host-agnostic at its
boundary: it captures the shared URL, fetches HTML, parses the recipe, and
**writes a JSON "pending import" file into a shared App Group container**
(`group.com.seanick80.recipeapp`) — it does *not* touch SwiftData/CloudKit. That
"extension writes JSON → host app reads it" contract is exactly what RN can
consume, so we reuse the Swift code rather than reimplement it. Required work:
  1. **Shared App Group** — the RN app target *and* the extension must both join
     one group (reuse `group.com.seanick80.recipeapp` or mint
     `group.com.seanick80.recipeapp.rn`). Add the App Group entitlement to the RN
     app via an Expo config plugin (prebuild regenerates entitlements) and
     register the group capability on the App IDs.
  2. **Extension target** — added via a config plugin (e.g.
     `expo-share-extension`) or a hand-written native target + prebuild plugin;
     the existing `ShareViewController.swift` drops in. Needs its **own** bundle
     ID `com.seanick80.recipeapp.rn.share-extension` + its own App Store
     provisioning profile (same ceremony as the main app — a third App ID/profile).
  3. **JS reader** — `expo-file-system` can't see App Group container paths, so a
     tiny native module returns the container path (or the pending payloads);
     JS reads the JSON on foreground and runs it through the normal import →
     SQLite → sync flow.

  Tradeoff (decided: **reuse the Swift parse**): the extension parses in Swift
  while the main app parses in TS, so extraction logic lives in two places and
  can drift. Accepted because it's iOS-only, the Swift code already works, and
  the parser rarely changes. Mitigation: cross-reference comments in both
  `ShareViewController.swift` and the TS `RecipeSchemaParser` port so an edit to
  one flags its twin. (Alternative was a *thin* extension that writes only the
  URL and lets the TS parser do the work on app open — single source of truth,
  but a rewrite and slightly slower UX; not chosen.)

**Android — no extension, just an intent filter.** Android has no extension
concept; the main app declares it accepts shared content via an `ACTION_SEND`
intent filter and becomes a share-sheet target that launches the normal app. No
separate process, bundle ID, or provisioning. Mostly declarative in `app.json`:

    "android": {
      "intentFilters": [{
        "action": "SEND",
        "data": [{ "mimeType": "text/plain" }],
        "category": ["DEFAULT"]
      }]
    }

plus JS (via `expo-linking` / an intent module) to read the incoming URL/text
and route it into the same import path — using the ported TS parser directly.
This is the cheap half of Phase 6.

## Effort summary

| Pile | Lines (Swift) | Effort | Risk |
|---|---|---|---|
| 1 — SharedLogic port (11 modules, ex-Pantry) | ~3,100 | Low | Low |
| 2 — UI + nav + networking | ~5,100 | Medium | Low |
| 3a — Local DB + sync | (replaces SwiftData+CloudKit) | High | High |
| 3b — Camera/Vision (OCR + barcode, no CoreML) | (replaces AVF/Vision) | High | Medium |

Order-of-magnitude: SharedLogic port is days; UI is a couple weeks; sync +
camera/ML are where most of the calendar goes.

## Gains vs. losses

**Gain:** Android. One TS codebase, potentially shared with `frontend/`. Easier
text/parse logic. No Mac/Codemagic/xcodegen/provisioning dance for daily dev.

**Lose:** CloudKit's zero-effort private sync (becomes the server's job).
Native-quality Vision (RN OCR/barcode equivalents are heavier, less polished).
Native SwiftUI feel. A larger surface of native-module + build-config
maintenance. (No CoreML loss — Pantry/food-classification is dropped.)

## Recommendation

Viable specifically because we already have the backend and a framework-free
logic layer — those two facts make it more than a from-scratch rebuild. If we
proceed, front-load the two risk spikes (Phase 3 sync, Phase 5 camera) before
investing in the full UI, so a "no-go" is cheap. Keep the SwiftUI app shipping
throughout; cutover is a later, separate decision.
