# Recipe App — Staged Work Plan

## Overview

Full-stack recipe & grocery list iOS app with local-first architecture.
- **iOS client**: SwiftUI + MVVM + SwiftData (on-device persistence)
- **Cloud sync**: CloudKit private database (single-user), CloudKit sharing via SQLiteData (Phase 4)
- **Backend**: Google Cloud Run + Gemini API (stateless vision proxy, Phase 3)
- **Build pipeline**: Windows → GitHub → Codemagic → iPhone (OTA install)

For detailed architecture decisions and rationale, see `ARCHITECTURE_PROPOSAL.md`.

---

## Phase 1: Local-Only iOS App (Recipe Storage + Grocery Lists)
**Status**: Complete (milestones 1A–1E)

### Milestone 1A: Environment Setup — DONE
- [x] Swift toolchain on Windows
- [x] VS Code extensions
- [x] GitHub repo created (seanick80/recipe-app, private, branch `master`)
- [x] Git init + push initial boilerplate

### Milestone 1B: Pure Swift Model Validation (Windows) — DONE
- [x] Models compile and all 12 tests pass on Windows
- [x] Codable round-trips validated

### Milestone 1C: SwiftUI Views — Recipes — DONE
- [x] Recipe list with search and empty state
- [x] Recipe detail view
- [x] Recipe create/edit form
- [x] Delete recipes with swipe

### Milestone 1D: SwiftUI Views — Grocery Lists — DONE
- [x] Grocery list overview with completion counts
- [x] Grocery list detail with categorized items
- [x] Add item form with category picker
- [x] Check/uncheck items
- [x] Generate grocery list from selected recipes

### Milestone 1E: First Build & Install — DONE
- [x] Apple Developer Program enrolled
- [x] Codemagic account + repo connected
- [x] App ID + CloudKit container created
- [x] SwiftData models refactored for CloudKit
- [x] xcodegen build system chosen
- [x] Persistent signing identity (.p12) uploaded to Codemagic
- [x] codemagic.yaml rewritten for API-key signing
- [x] First green Codemagic build (signed IPA)
- [ ] Install IPA on iPhone + CloudKit smoke test

---

## Phase 1.5: Shopping List Enhancement (free, no backend)
**Status**: Not started — next up

### Milestone 1.5A: Persistent Weekly Shopping List
- [ ] New `ShoppingTemplate` + `TemplateItem` SwiftData models (CloudKit-safe)
- [ ] "Start New Week" stamps a fresh `GroceryList` from template
- [ ] "Edit Staples" template editor (add/remove/reorder items)
- [ ] Category-grouped display sorted by store aisle order:
      Vegetables → Eggs/Dairy → Meat → Dry & Canned → Household → Frozen
- [ ] Checked items sink to bottom of their category
- [ ] User-reorderable category sort in settings
- [ ] "Add from Recipe" pulls ingredients into active list
- [ ] Manual "+" button for one-off additions
- [ ] `GroceryList.archivedAt` field for list history
- [ ] `Ingredient.category` field for recipe → shopping list flow
- Estimated effort: 1-2 sessions

### Milestone 1.5B: UX Polish
- [ ] Unit picker improvements
- [ ] Additional input improvements based on user testing feedback

---

## Phase 2: On-Device Vision Foundation (free, no backend)
**Status**: In progress (milestones 2A–2C complete)

### Milestone 2A: Camera Capture Infrastructure — DONE
- [x] `AVCaptureSession` + `AVCapturePhotoOutput` for guided photo mode
- [x] `CMMotionManager` coaching overlays (tilt, stability)
- [x] Brightness heuristics for lighting warnings (EV-based dim/bright detection)
- [x] Camera preview via UIViewRepresentable
- [x] Coaching badge UI (pill-shaped warnings)
- [ ] Zone-by-zone guided capture UI with thumbnail strip (deferred to 2D)

### Milestone 2B: Barcode Scanning + Open Food Facts — DONE
- [x] AVFoundation `VNDetectBarcodesRequest` for UPC-E/EAN-8/EAN-13 detection
- [x] Open Food Facts API v2 integration (free, no key needed)
- [x] Product name + brand + category returned for scanned barcodes
- [x] Debounce (3s) to prevent re-scanning same barcode
- [x] "Add to Shopping List" flow from scan result
- [x] Camera permission request + Settings redirect

### Milestone 2C: On-Device OCR Pipeline — DONE
- [x] Apple Vision `VNRecognizeTextRequest` (.accurate mode, language correction)
- [x] Per-line confidence scoring via `VNRecognizedTextObservation`
- [x] Two scan modes: Shopping List import + Recipe import
- [x] OCR text → `ListLineParser` (pure Swift) → structured items
- [x] Review/edit screen with checkbox toggle per item
- [x] Retake flow if no text found
- [x] Keyword-based category auto-assignment

### Milestone 2D: On-Device Food Detection (CoreML ViT)
- [x] Source pre-trained food model (nateraw/food — ViT-base-patch16-224, Food-101, 101 classes, Apache-2.0)
- [x] Convert to CoreML .mlpackage via `scripts/convert-food-model.py` (PyTorch → TorchScript → coremltools → iOS17 ML Program)
- [x] FoodClassifier.mlpackage (164MB) committed to repo via Git LFS
- [x] `FoodDetectionViewModel` — CoreML inference wrapper with state machine
- [x] Integrate with camera pipeline (`PantryCaptureView`)
- [ ] Test accuracy on real fridge/pantry photos
- [x] Text-based grocery categorizer (`GroceryCategorizer.swift`, 200+ keywords, 99 tests)
- [x] Replaced `guessCategory()` in `ScanProcessor` with comprehensive categorizer

### Milestone 2E: Confirmation & Correction UI
- [x] Confidence-based triage (auto-add ≥ 0.85 / confirm 0.55-0.85 / reject < 0.55)
- [x] Card-swipe review pattern (`DetectionReviewSheet`)
- [ ] Voice correction via `SFSpeechRecognizer` (simple dictation)
- [ ] Shelf-level and item-level retake flows
- [x] `PantryItem` model + CloudKit sync (`@Model` with safe defaults)
- [x] `PantryViewModel` — triage orchestration, confirm/reject/edit actions
- [x] Pantry tab in `ContentView` with grouped item list

### Milestone 2F: Recipe Photo Import — OCR Tier
- [ ] Photo capture + crop/rotate
- [ ] On-device OCR text extraction
- [ ] Review/edit screen with all fields editable
- [ ] Save to recipe collection
- Estimated effort: 1-2 sessions

### Milestone 2G: Shopping List Photo Import — OCR Tier
- [ ] Photograph handwritten or printed shopping list
- [ ] Line-by-line OCR → parsed into item name + optional quantity
- [ ] Review/edit screen: each line becomes a `GroceryItem` candidate
- [ ] Confirm, edit, or remove items before adding to active list
- Estimated effort: 1 session

### CI/Build Infrastructure Updates (during Phase 2)
- [x] Codemagic XCTest results piped to separate `xctest.log` artifact
- [x] CI step copies shared parser modules from `Models/` into `RecipeApp/RecipeApp/Parsers/` before xcodegen
- [x] `scripts/poll-build.sh` — polls Codemagic REST API for build status, auto-downloads artifact zip, extracts and analyzes `xctest.log` inline
- [x] Simulator destination updated to `iPhone 17` (Xcode 26.2 runner only has iPhone 17-series)
- [x] `.env` stores `CODEMAGIC_API_TOKEN` + `CODEMAGIC_APP_ID` (gitignored)
- [x] `build/ci-artifacts/` for downloaded artifacts (gitignored)
- [x] Codemagic dual-workflow: `ios-workflow` (auto on push) + `ml-model-conversion` (manual trigger)
- [x] ML model conversion pipeline (`scripts/convert-food-model.py` → `ml-model-conversion` Codemagic workflow → `.mlpackage` artifact → Git LFS commit)
- [x] Git LFS for CoreML models (`RecipeApp/RecipeApp/MLModels/*.mlpackage/**`) — required for GitHub 100MB limit
- [x] MLModelTests in XCTests (XCTSkipUnless pattern — gracefully skips when model not in bundle, auto-activates when committed)
- [x] HuggingFace token wired via `recipe_app_ml` Codemagic env group (HF_TOKEN)
- [x] `recipe_app_notifications` Codemagic env group (RECIPIENT_EMAIL)
- [x] `scripts/update-models.sh` — manual model update script (macOS only)
- [x] CRLF lint check inspects git index (not working copy) — correct for Windows with core.autocrlf=true

**Phase 2 checkpoint**: Working pantry scanner (barcode + OCR + YOLO, all free),
recipe photo capture with OCR, shopping list photo import. Real user data on
where on-device detection fails informs Phase 3 cloud API usage.

---

## Phase 3: Cloud Vision Integration ($)
**Status**: Not started

### Milestone 3A: Gemini API Integration Spike
- [ ] Set up Gemini API access via existing Google Cloud account
- [ ] Test Flash-Lite structured JSON output on food images
- [ ] Test Pro on handwritten recipes and cluttered shelf photos
- Estimated effort: 0.5 sessions

### Milestone 3B: Cloud Run Backend Deployment
- [ ] FastAPI app in Docker container on Cloud Run (same GCP project)
- [ ] `POST /pantry/scan` — accepts cropped image regions, proxies to Gemini
- [ ] `POST /recipes/scan` — accepts OCR text or photos, proxies to Gemini
- [ ] Dockerfile, Cloud Build config, deploy script
- Estimated effort: 1-2 sessions

### Milestone 3C: API Spend Monitoring & Alerting
- [ ] GCP Budget Alert: $1/mo threshold, email at 50%/90%/100%
- [ ] Per-request cost logging in Cloud Run (token count + estimated cost → Cloud Logging)
- [ ] Cloud Run max-instances=1, FastAPI per-IP rate limiting middleware
- [ ] `scripts/check-api-spend.sh` — queries GCP Billing API, runs as cron on Raspberry Pi
- [ ] Alert via email or pushover on daily spend spike
- [ ] Cloud Monitoring dashboard (requests/day, tokens/day, cost/day)
- Estimated effort: 0.5-1 session

### Milestone 3D: Recipe Photo Import — LLM Parsing Tier
- [ ] OCR text → Gemini → structured JSON
- [ ] Handwritten/complex layout fallback (send photo directly to Gemini Pro)
- Estimated effort: 1 session

### Milestone 3E: Pantry Scanner — Cloud Fallback Tier
- [ ] Low-confidence YOLO detections → cropped regions → Gemini
- [ ] Merge cloud results into confirmation UI
- Estimated effort: 1 session

---

## Phase 4: Sharing (Option A — SQLiteData + CloudKit)
**Status**: Not started

### Milestone 4A: Shared Shopping List
- [ ] Migrate SwiftData → SQLiteData (model declarations, query wrappers, view updates)
- [ ] Implement CKShare-based zone sharing for GroceryList + GroceryItems
- [ ] Native Apple share sheet for inviting spouse
- [ ] Recipes stay in private zone (not shared)
- Estimated effort: 2-3 sessions

---

## Phase 5: Integration & Advanced Features
**Status**: Not started

### Milestone 5A: Recipe ↔ Pantry Integration
- [ ] "What can I cook?" query (match recipes against pantry)
- [ ] "What do I need?" auto-populates shopping list with missing ingredients
- Estimated effort: 1-2 sessions

### Milestone 5B: Video Quick-Scan Mode
- [ ] Key frame extraction + `VNTrackObjectRequest` deduplication
- [ ] LiDAR depth hints on Pro iPhones (graceful degradation)
- Estimated effort: 2-3 sessions

---

## Phase 6+: Future Features

- Fine-tune YOLO on custom pantry dataset (HF training pipeline)
- Natural language voice parsing ("two cans of diced tomatoes" → quantity + item)
- Meal planning + calendar
- Spouse voting on meal ideas
- Web dashboard (triggers Google OAuth + full backend upgrade)
- Android support
- Expiration date tracking (extend pantry scanner)
- Purchase history analytics

---

## Testing Strategy

Modeled after the fractal drawing app's infrastructure. **Guiding principle:
maximize tests that run locally on Windows.** Codemagic XCTest is a safety
net, not the primary test surface.

### Tier 1: Pure Swift (Windows, every commit, ~80% of logic)

Compiled via `swiftc` on Windows. No SwiftData, no UIKit, no network, no
Apple vision frameworks. Run by `scripts/test.sh` (wired into pre-commit hook).

All parsing and decision logic is extracted into pure Swift modules in `Models/`
that have zero Apple-framework dependencies. The iOS app imports these same
files, but they compile and test independently on Windows.

**Model + logic files (all implemented, 388 tests passing):**
- `Models/TestHelpers.swift` — factory methods, assertion helpers
- `Models/TestModels.swift` — recipe + grocery model tests (42 tests)
- `Models/TestShopping.swift` — shopping template tests (63 tests)
- `Models/ListLineParser.swift` + `Models/TestListParser.swift` — handwritten list → items (57 tests)
- `Models/OCRParser.swift` + `Models/TestOCR.swift` — OCR text → structured recipe (45 tests)
- `Models/DetectionClassifier.swift` + `Models/TestDetection.swift` — confidence triage (26 tests)
- `Models/BarcodeProductMapper.swift` + `Models/TestBarcode.swift` — OFF JSON → product (22 tests)
- `Models/PantryItemMapper.swift` + `Models/TestPantry.swift` — YOLO → PantryItem (34 tests)
- `Models/GroceryCategorizer.swift` + `Models/TestGroceryCategorizer.swift` — text → grocery category (99 tests)

### Tier 2: XCTest on Codemagic Simulator (~20% of logic)

Thin iOS framework wrapper tests against fixture images in
`RecipeAppTests/Fixtures/`. Runs via `xcodebuild test` on Codemagic before the
archive step. Test failure blocks the build.

**XCTest files (implemented):**
- `RecipeAppTests/RecipeModelTests.swift` — SwiftData model init + toggle
- `RecipeAppTests/ShoppingTemplateTests.swift` — SwiftData template + archive + category

### Test expansion rule

Every new parsing or decision function gets a corresponding test in `Models/`
that runs on Windows. No exceptions — enforced by the pre-commit hook. XCTest
is the safety net for framework behavior changes, not the primary test surface.

---

## Development Workflow (Day-to-Day)

1. Open project in VS Code
2. Use Claude Code to write/modify Swift and SwiftUI files
3. Review code — VS Code Swift extension highlights syntax errors
4. Test pure Swift logic locally: `scripts/test.sh` (runs on every commit via hook)
5. Commit and push to GitHub
6. Codemagic auto-builds on push (5-15 min)
7. Install via OTA link on iPhone

## Current Focus

**Phase 2A–2C complete** (2026-04-13) — Camera infrastructure, barcode scanning
(Open Food Facts), and OCR pipeline built. New "Scan" tab with barcode, shopping
list, and recipe scanning modes. Pure Swift parsers (5 modules, 181 tests) wired
into iOS views via CI copy step. Build 22 on Codemagic passed (Xcode 26.2,
iPhone 17 simulator). IPA with Scan tab available.

**Schema review complete** (2026-04-14) — Added fields to Recipe (cuisine, course,
tags, sourceURL, difficulty, isFavorite), Ingredient (displayOrder, notes),
GroceryItem (sourceRecipeName, sourceRecipeId). Split UnitPicker into recipe vs
shopping context. All additive, zero migration risk. See `SCHEMA_REVIEW.md`.
Model tests: 12 → 42 (286 total across all suites).

**Phase 2D–2E nearly complete** (2026-04-14) — CoreML food detection pipeline
operational. nateraw/food ViT model converted to FoodClassifier.mlpackage (164MB,
101 classes) and committed via Git LFS. FoodDetectionViewModel, PantryViewModel
(triage orchestration), PantryItem SwiftData model, Pantry tab with capture +
DetectionReviewSheet all implemented. GroceryCategorizer (200+ keywords, 99 tests)
replaces old `guessCategory()`. Codemagic dual-workflow (ios-workflow +
ml-model-conversion) operational. MLModelTests added to XCTests with XCTSkipUnless
pattern. AVFoundation import added to PantryTabView.swift (was missing, caused CI
build failure). 388 tests across 8 suites (pure Swift) + MLModelTests in XCTests.

**Remaining for Phase 2D–2E**: voice correction via SFSpeechRecognizer, shelf-level
and item-level retake flows, real-world accuracy testing on fridge/pantry photos.

**Next phase**: Phase 2F — Recipe Photo Import (OCR tier).
