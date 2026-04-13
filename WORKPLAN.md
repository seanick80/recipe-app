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
**Status**: Not started

### Milestone 2A: Camera Capture Infrastructure
- [ ] `AVCaptureSession` + `AVCapturePhotoOutput` for guided photo mode
- [ ] `CMMotionManager` coaching overlays (tilt, stability)
- [ ] Brightness heuristics for lighting warnings
- [ ] Zone-by-zone guided capture UI with thumbnail strip
- Estimated effort: 2-3 sessions

### Milestone 2B: Barcode Scanning + Open Food Facts
- [ ] AVFoundation `VNDetectBarcodesRequest` for UPC/EAN detection
- [ ] Open Food Facts API integration (free, no key needed)
- [ ] Product name + category returned for scanned barcodes
- Estimated effort: 1 session

### Milestone 2C: On-Device OCR Pipeline
- [ ] Apple VisionKit `VNRecognizeTextRequest` (.accurate mode)
- [ ] Extract product names from visible labels
- [ ] Confidence scoring per text region
- Estimated effort: 1 session

### Milestone 2D: On-Device YOLO Food Detection
- [ ] Source pre-trained food YOLO model (BinhQuocNguyen/food-recognition-model)
- [ ] Export to CoreML
- [ ] Integrate with camera pipeline — bounding boxes + class labels
- [ ] Test accuracy on real fridge/pantry photos
- Estimated effort: 2-3 sessions

### Milestone 2E: Confirmation & Correction UI
- [ ] Confidence-based triage (auto-add > 0.85 / confirm 0.55-0.85 / unrecognized < 0.55)
- [ ] Card-swipe review pattern
- [ ] Voice correction via `SFSpeechRecognizer` (simple dictation)
- [ ] Shelf-level and item-level retake flows
- [ ] `PantryItem` model + CloudKit sync
- Estimated effort: 2-3 sessions

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

### Milestone 3C: Recipe Photo Import — LLM Parsing Tier
- [ ] OCR text → Gemini → structured JSON
- [ ] Handwritten/complex layout fallback (send photo directly to Gemini Pro)
- Estimated effort: 1 session

### Milestone 3D: Pantry Scanner — Cloud Fallback Tier
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

## Development Workflow (Day-to-Day)

1. Open project in VS Code
2. Use Claude Code to write/modify Swift and SwiftUI files
3. Review code — VS Code Swift extension highlights syntax errors
4. Test pure Swift logic locally: `swiftc Models/*.swift -o test.exe && ./test.exe`
5. Commit and push to GitHub
6. Codemagic auto-builds on push (5-15 min)
7. Install via OTA link on iPhone

## Current Focus

**Phase 1.5** — Persistent weekly shopping list with store aisle ordering.
Then Phase 2 (on-device vision) where the interesting work begins.
