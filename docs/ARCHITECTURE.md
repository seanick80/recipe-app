# Recipe App — Architecture

Current, implemented architecture of the Recipe App. For active work items
and future ideas see `BACKLOG.md`. For the archived research and rationale
behind architectural decisions (cloud LLM provider, backend approach,
sharing architecture, etc.) see `docs/DESIGN_DECISIONS.md`. For day-to-day
build/test/lint commands see `README.md` and `CLAUDE.md`.

## One-screen summary

- Single-user iOS app. Persistence is **SwiftData + CloudKit private DB**.
- **Web editor**: FastAPI backend deployed on **Google Cloud Run**
  (`https://recipe-api-972511622379.us-west1.run.app`), React SPA frontend,
  Neon PostgreSQL. iOS and web are not yet synced (Step 3).
- Windows is the primary dev environment. The iOS build is cross-compiled
  on **Codemagic** from the pushed git repo. No Mac is involved in the
  dev loop.
- Logic that can run on Windows is deliberately kept in pure-Swift modules
  under `SharedLogic/` so it can be unit-tested without Apple frameworks.

## Repository layout

```
RecipeApp/                   xcodegen project
  project.yml                Source of truth for the Xcode project
                             (.xcodeproj is generated at CI time, gitignored)
  RecipeApp/                 Swift sources the iOS target compiles
    RecipeAppApp.swift       @main entry; wires ModelConfiguration with
                             cloudKitDatabase: .private(...)
    ContentView.swift        Top-level tab view
    Models/                  SwiftData @Model classes (Recipe, Ingredient,
                             GroceryList, GroceryItem, ShoppingTemplate,
                             TemplateItem, PantryItem)
    Views/                   SwiftUI, grouped by feature
      Recipes/               Recipe list, detail, edit, generate-grocery
      Grocery/               Grocery list views + add/edit item
      Shopping/              Template editor + shopping tab
      Scanner/               Camera + OCR + barcode + debug-log tabs
      Pantry/                Pantry capture + detection review
      UnitPicker.swift       Shared unit picker (recipe vs shopping)
    ViewModels/              @Observable VMs; one per feature area
    Services/                APIClient, LocalStorageService (mostly stubs)
    Assets.xcassets/         AppIcon + colors
    MLModels/                CoreML .mlpackage(s), shipped via Git LFS
    RecipeApp.entitlements   iCloud + CloudKit container

SharedLogic/                 Pure-Swift modules shipped into the iOS app.
                             Copied into RecipeApp/RecipeApp/Parsers/ by
                             codemagic.yaml's "Copy shared parser modules"
                             step at build time. No Apple frameworks —
                             compilable with plain `swiftc` on Windows.
TestFixtures/                Windows-only mirror structs for the SwiftData
                             @Model types, plus all Test*.swift suites
                             (520 assertions). Never copied into iOS.

scripts/                     Bash scripts that glue everything together
  build.sh                   Canonical build/validate entrypoint. Modes:
                             full | quick | validate.
  test.sh                    Pure-Swift test runner (SharedLogic + TestFixtures)
  lint.sh                    swift-format + YAML/XML + CRLF checks
  layout-bench/              Separate Python/PyTorch pipeline for evaluating
                             document layout models on recipe pages (Windows).
                             See scripts/layout-bench/README.md.
  convert-food-model.py      CoreML conversion helper run by the
                             ml-model-conversion Codemagic workflow.

docs/                        This file
secrets/                     Local-only key material (gitignored). Signing
                             identities actually live in Codemagic's store.
server/                      FastAPI backend (deployed on Cloud Run)
database/                    SQL schema + seed (not used by iOS today)
data/                        Layout-bench fixtures + golden outputs

codemagic.yaml               Two CI workflows (see "Build pipeline" below)
BACKLOG.md                   Unscheduled ideas and explicit not-plans
CLAUDE.md                    Conventions and Claude-specific instructions
README.md                    Onboarding + day-to-day commands
```

## Build pipeline

1. Developer pushes to GitHub `master`.
2. Codemagic's `ios-workflow` picks up the push and runs on a Mac M2:
   - `brew install xcodegen`
   - Copy `SharedLogic/*.swift` into `RecipeApp/RecipeApp/Parsers/`
     (files aren't tracked there — the directory is gitignored — because
     iOS sources and cross-platform modules live in different trees)
   - `xcodegen generate` produces `RecipeApp.xcodeproj`
   - `xcode-project use-profiles` installs the provisioning profile and
     flips CODE_SIGN_STYLE to Manual
   - `xcodebuild test` on the iPhone 17 simulator (XCTests in
     `RecipeAppTests/`)
   - `xcode-project build-ipa` produces the signed IPA
   - IPA + xcodebuild logs uploaded as artifacts; notification email sent
3. Install via OTA link on device.

The second workflow, `ml-model-conversion`, is manual-only. It runs
`scripts/convert-food-model.py` to produce `.mlpackage`s from upstream
Food-101 weights. The resulting `.mlpackage` is downloaded, committed via
Git LFS, and pushed — that's how CoreML models get into the repo.

## Signing

- App Store Connect API key integration: `recipe-app-appstore-key`.
- Persistent signing identity (`.p12`) uploaded to Codemagic's Code Signing
  Identities store as `ios_development_cert`. Never regenerated per build
  (see `feedback_ci_signing.md` in auto-memory for why).
- Provisioning profile `ios_development_profile` (Apple resource
  `U3BL9G576X`) includes Nick's iPhone (`R42YWH9Q22`).
- Identifiers (Team ID, bundle ID, CloudKit container) are all
  effectively public and safe to commit; see `CLAUDE.md` "Secrets policy".

## Persistence + sync

- **iOS**: SwiftData with `ModelConfiguration(cloudKitDatabase: .private("iCloud.com.seanick80.recipeapp"))`.
- CloudKit constraints observed on every `@Model`:
  every stored property is defaulted or optional, every relationship is
  optional with explicit `inverse:`, no `@Attribute(.unique)` anywhere.
- **Web**: FastAPI + SQLAlchemy + Neon PostgreSQL (free tier, us-west-2).
  Google OAuth + JWT cookie auth, API key for scripts.
- **Sync**: iOS (CloudKit) and web (PostgreSQL) are **independent** today.
  Step 3 (Sync Bridge) will add CloudKit server-to-server bidirectional sync.
- The `GroceryItem.sourceRecipeName` / `sourceRecipeId` fields are
  string-based traceability (not FKs) so cascade deletes don't cross zone
  boundaries.

## Scan pipeline

The scanner tab is the most algorithm-heavy part of the app. It lives in
`RecipeApp/RecipeApp/ViewModels/ScanProcessor.swift` and delegates all
parsing/classification to `SharedLogic/`:

```
UIImage from camera
     │
     ▼  VNRecognizeTextRequest (accurate mode)
[OCRLine] — text, confidence, normalized bounding box
     │
     ▼  assessImageQuality       (QualityGate.swift)
retake-if-blurry gate (median conf < 0.35 or > 60% low-conf lines)
     │
     ▼  separateHandwritten       (QualityGate.swift)
printed lines kept; margin notes dropped
     │
     ├── shopping-list mode:
     │      parseListLine         (ListLineParser.swift)
     │        → ParsedItem(name, qty, unit, category)
     │      categorizeGroceryItem (GroceryCategorizer.swift)
     │
     └── recipe mode (section-header routing):
            sectionFromHeader     (QualityGate.swift)
              routes each line by explicit "Ingredients" / "Method" /
              "Step N" header into intro | ingredients | instructions
            isLikelyMetadataJunk  (QualityGate.swift)
              drops nutrition-widget noise like "270•" / "160g." / "x1,8"
            parseIngredientLine   (OCRParser.swift)
            cleanInstructionLine  (OCRParser.swift)
            cleanRecipeTitle      (OCRParser.swift)
```

A previous iteration grouped lines geometrically
(`groupLinesIntoBlocks` + `classifyZone`) and classified each block by
content. That failed on dense web-recipe screenshots where everything
fused into one block and got labelled "instructions". The current
section-header routing walks Vision's natural reading order and never
depends on geometry. `groupLinesIntoBlocks` and `classifyZone` remain in
`SharedLogic/` but aren't called from `ScanProcessor` — they're kept for
now because their tests document the heuristics in case we revisit a
multi-column / cookbook-specific pipeline later.

Everything the pipeline sees is also written to an on-device JSONL debug
log (`DebugLog.swift`) that the user can export from the Scanner tab.

## Testing

- **Windows (every commit via `.githooks/pre-commit` → `build.sh quick`)**:
  520 pure-Swift assertions across 11 suites in `TestFixtures/`. Covers
  all `SharedLogic/` modules plus Codable round-trips on the mirror
  structs. Runs via `scripts/test.sh` in seconds.
- **Codemagic simulator (every push)**: XCTests in `RecipeAppTests/`
  exercise the SwiftData models and validate CoreML model presence
  (`MLModelTests` uses `XCTSkipUnless` so a build without LFS still
  passes).
- **Device smoke**: manual. Install the IPA, scan a recipe, verify the
  review sheet shows ingredients + instructions separately.

New parsing / classification logic gets a corresponding
`TestFixtures/Test<Thing>.swift` file before it's considered done.

## Logging

- `DebugLog` (in `SharedLogic/`) writes JSONL events to `Documents/debug.jsonl`
  with per-event category, message, scanID, and a free-form details dict.
- Every scan emits a correlation ID (`scanID`) so one scan's events can be
  filtered out of a busy log.
- Nothing is uploaded — the user explicitly shares the file when they want
  to send a log for debugging. This subsystem is debug-build-only and will
  be removed before any public release.

## What's intentionally not here

See `BACKLOG.md` for full reasoning.

- **Backend is read/write for web only.** iOS still uses CloudKit private DB
  for persistence. The FastAPI server on Cloud Run serves the React SPA and
  is not yet synced with CloudKit (Step 3: Sync Bridge).
- **No cloud LLM calls.** Every vision/OCR step runs on-device.
- **No multi-language support.** English-only assumptions are pervasive
  (Vision `recognitionLanguages`, categorizer keywords, section headers,
  time/servings parsing).
- **No shared shopping lists.** CloudKit sharing + SQLiteData are a future
  phase.
