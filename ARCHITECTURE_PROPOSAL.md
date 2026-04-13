# Recipe App — Architecture Proposal & Feature Roadmap

**Date:** 2026-04-13 (updated from 2026-04-12 draft)
**Status:** Draft — awaiting decision on architecture choices marked with [DECISION NEEDED]

---

## Executive Summary

Four features are proposed. Two require a hosted backend service (pantry scanner,
recipe photo import). Two can be built on the existing CloudKit-only stack but
benefit from a backend for the sharing feature. This document groups work by
shared infrastructure dependencies and presents architecture options where
tradeoffs exist.

A significant amount of the pantry scanner and recipe photo import can be built
and tested using free, on-device APIs (Apple Vision, AVFoundation barcode, CoreML)
before committing to any paid cloud API. The roadmap is structured to maximize
this free runway.

### Cost Summary

| Feature | Hosting Required? | Per-Use API Cost | Monthly (1 user) |
|---|---|---|---|
| Recipe photo import | Yes (API key custody) | ~$0.0001–0.01/recipe | < $0.10 |
| Pantry scanner | Yes (API key custody) | ~$0.002–0.02/session | < $0.15 |
| Persistent shopping list | No | $0 | $0 |
| Shared shopping list | Depends on option chosen | $0–15/mo | $0–15 |

---

## Feature 1: Pantry Scanner (Fridge/Pantry Photos → Ingredient Inventory)

### What It Does

User scans their fridge, pantry, and freezer. The app identifies ingredients and
builds a structured inventory. This inventory later integrates with meal planning
("what can I cook with what I have?") and shopping lists ("what do I need to buy?").

### Recommended Architecture: Four-Tier Hybrid Pipeline

A four-tier identification strategy, in priority order. Tiers 1-3 are free and
on-device. Tier 4 is the cloud fallback for ambiguous items only.

1. **Barcode scan** (on-device, free, ~99% accuracy for packaged goods)
   - AVFoundation barcode detection on each captured frame
   - UPC/EAN lookup via Open Food Facts API (free, 3M+ products)
   - Covers ~50-60% of a typical fridge

2. **OCR for visible labels** (on-device, free, ~85-95% accuracy)
   - Apple VisionKit `VNRecognizeTextRequest` in `.accurate` mode
   - Extracts product names from cans, boxes, bottles where barcode isn't visible
   - Text normalization can happen on-device with simple heuristics initially

3. **On-device object detection** (free, ~82-85% mAP on food)
   - YOLO11 exported to CoreML via Ultralytics one-command export
   - Runs at 60+ FPS on iPhone Neural Engine — fast enough for real-time video
   - Fine-tuned on food data (Food-101, Freiburg groceries, or custom)
   - Provides bounding boxes + class labels for produce and unlabeled items
   - **This tier is new** — it fills the gap between OCR and cloud LLM

4. **Cloud LLM vision** (paid, ~$0.002/photo — only for ambiguous items)
   - Send cropped regions of low-confidence detections to cloud API
   - Handles edge cases: unusual produce, cluttered shelves, bulk items
   - Provider decision deferred (see Vision API Comparison below)

### Vision API Comparison

#### Tier A: General-Purpose LLM Vision (cloud, highest flexibility)

| Provider | Model | Cost/Image | Food Accuracy | Backend? | Notes |
|---|---|---|---|---|---|
| **Google** | Gemini 2.5 Flash-Lite | ~$0.0001 | Very good | Yes | Cheapest; generous free tier (1K req/day) |
| **Anthropic** | Claude Haiku 4.5 | ~$0.0003–0.005 | Very good | Yes | Best structured JSON output |
| **Google** | Gemini 2.5 Pro | ~$0.0003–0.003 | Excellent | Yes | Best Google option for complex scenes |
| **OpenAI** | GPT-4o-mini | ~$0.001 | Good | Yes | Budget option |
| **OpenAI** | GPT-4o | ~$0.003–0.006 | Excellent | Yes | Best on cluttered/complex layouts |

All of these can identify specific food items (not just "food"), return structured
JSON, and handle produce + packaged goods in the same frame. The hybrid architecture
makes the provider choice low-stakes — only ambiguous items go to the cloud, so
you can swap providers trivially.

#### Tier B: Dedicated Vision APIs (cloud, purpose-built)

| Provider | Capability | Cost/Image | Food-Specific? | Verdict |
|---|---|---|---|---|
| **Clarifai** | Food Model | Usage-based (free tier) | Yes — 1000+ food items | Best dedicated food API |
| **Google Cloud Vision** | Label Detection | ~$0.002 | Generic only ("fruit", "dairy") | Too broad for ingredients |
| **Amazon Rekognition** | Label Detection | ~$0.001 | Generic only | Same problem as Google |

**Skip Google Cloud Vision and Rekognition** — they return generic labels, not
ingredient-level identification. Clarifai's food model is the only dedicated API
worth considering, but an LLM vision call is more flexible (returns structured
JSON with quantities, categories, confidence) for similar cost.

#### Tier C: On-Device Models (free, private, no backend)

| Option | Accuracy | Food-Specific? | iOS Integration | Notes |
|---|---|---|---|---|
| **YOLO11 + CoreML** | 82-85% mAP (food-tuned) | Yes, if fine-tuned | CoreML export, 60+ FPS | Best on-device food detector |
| **GrocerEye (YOLOv3)** | 84.6% mAP | Yes — grocery shelf items | Needs CoreML conversion | Freiburg grocery dataset |
| **Apple Vision** (VNClassifyImageRequest) | Moderate | No — general classification | Native, trivial | "food" vs "not food" only |
| **Apple VisionKit OCR** | 85-95% on text | N/A — reads labels | Native, trivial | Great for packaged goods |
| **Google ML Kit** | Moderate | No — general detection | Firebase SDK dependency | Similar to Apple Vision |

#### Tier D: Hugging Face Models (self-hosted or HF Inference API)

| Model | Architecture | Categories | Notes |
|---|---|---|---|
| **BinhQuocNguyen/food-recognition-model** | YOLO v8 + EfficientNet-B0 | 101 (Food-101) | Includes portion estimation + USDA calorie DB |
| **Kaludi/food-category-classification-v2.0** | Image classifier | Food categories | Simpler category-level classification |
| **nateraw/food** | Fine-tuned on Food-101 | 101 | Straightforward food classifier |
| **openfoodfacts/nutriscore-yolo** | YOLO | Nutrition labels | From Open Food Facts — useful for label scanning |

**Hosting**: HF Inference API (pay-per-call, essentially free at low volume) or
Inference Endpoints (~$0.60/hr for dedicated GPU). At a few scans/week, Inference
API cost is negligible.

**Fine-tuning path**: Fine-tune YOLO11 on Food-101 + Freiburg groceries + custom
pantry photos, then export to CoreML for on-device use. This maximizes accuracy
for *this specific use case* but requires collecting/labeling training data. This
is an optimization for later — start with a general food YOLO model first.

**Datasets for fine-tuning:**
- [ethz/food101](https://huggingface.co/datasets/ethz/food101) — 101K images, 101 categories
- [issai/Food_Portion_Benchmark](https://huggingface.co/datasets/issai/Food_Portion_Benchmark) — food detection + portion estimation
- Freiburg Groceries — grocery shelf object detection

#### [DECIDED] Cloud LLM Provider: Gemini

**Gemini 2.5 Flash-Lite** for production, **Gemini 2.5 Pro** as fallback for
complex scenes. Rationale:

- Cheapest option (~$0.0001/image for Flash-Lite)
- Generous free tier (1K req/day) covers dev and likely production
- Existing Google Cloud account (used by travel map project) — no new billing setup
- Existing Google OAuth integration (calendar + photos in goodmorning project)
- Structured JSON output via Gemini's response schema feature
- Can upgrade to Pro for complex scenes without changing infrastructure

### Data Model

New `PantryItem` model (additive, CloudKit-safe):

```
PantryItem
  id: UUID
  name: String = ""
  category: String = "Other"      (Produce, Dairy, Protein, Pantry, Frozen, etc.)
  quantityEstimate: String = ""   ("3 apples", "about half", "full bag")
  detectionMethod: String = ""    (barcode, ocr, yolo, vision, voice, manual)
  confidence: Double = 0          (0.0–1.0, from detection pipeline)
  scannedAt: Date = Date()
  expiresAt: Date? = nil           (future: expiration tracking)
```

### UX Flow: Two Scan Modes

#### Default: Guided Photo Mode (4-6 shots)

Recommended for first-time users and thorough scans.

1. **Zone-by-zone prompts**: App shows a simple fridge/pantry diagram with zones
   highlighted in sequence — "Top shelf", "Middle shelf", "Door", "Freezer", etc.
2. **Real-time coaching overlays** during capture:
   - Lighting warning via `AVCaptureDevice.exposureTargetOffset` ("Too dark — turn on the fridge light")
   - Tilt correction via `CMMotionManager` ("Tilt the phone upright")
   - "Move closer" if no items detected after 3 seconds
   - Motion blur detection via Laplacian variance ("Hold the phone still")
3. **Per-shot feedback**: After each photo, show "Found 6 items" before moving
   to next zone. Thumbnail strip at bottom shows completed zones — tap to retake.
4. **Confirmation screen** (mandatory — see below)

#### Optional: Quick Scan Video Mode

For routine top-ups ("I just got groceries"). Faster but slightly less accurate.

1. Single "Start Scan" button — user sweeps camera slowly across shelves
2. On-device YOLO runs at 3-5 fps during recording via `AVCaptureVideoDataOutput`
3. **Key frame extraction** using:
   - Sharpness score (Laplacian variance) — reject blurry frames
   - Object count delta — new key frame when new items appear vs. previous
   - Scene change detection — large optical flow = panning to new shelf
4. `VNTrackObjectRequest` deduplicates items across frames (tracks up to 16
   objects simultaneously) — prevents "counted the same milk 30 times"
5. ~20 key frames extracted from a 2-min walkthrough, ~2-4 MB total if uploaded

**LiDAR for size/quantity** (iPhone Pro models only, ~35% of active iPhones):
- ±1cm accuracy under 4m — enough for "tall bottle" vs "small can"
- Nice-to-have for quantity hints, not required
- Graceful degradation: fall back to relative size or ask user

#### Confirmation & Correction Flow

**Confidence thresholds:**

| Confidence | Action | UI Treatment |
|---|---|---|
| > 0.85 | Auto-added | Collapsed "Added" section, green indicator |
| 0.55–0.85 | "Please confirm" queue | Expanded card with photo crop + label |
| < 0.55 | "Unrecognized" | Photo crop shown, user names or skips |

**Correction methods:**

- **Card-swipe**: Swipe right = confirm, left = dismiss, tap = edit name/quantity
- **Voice correction**: Tap mic icon on any card, say "two cans of diced tomatoes"
  — parsed via `SFSpeechRecognizer` (on-device since iOS 17, no network needed).
  Transcription shown on screen before committing. Auto-stops after 2-3s silence.
- **Shelf-level retake**: "Re-scan a section" button re-enters capture for one
  zone. New results merge into existing list (deduplicated by identity, not name).
- **Item-level retake**: Camera icon on any card for single-photo re-detection.
- **Manual add**: "+" button for items the scanner missed entirely.

#### Coaching (Progressive Disclosure)

| Scan # | Guidance Level |
|---|---|
| 1st | Full hand-holding — one step at a time, animated overlay |
| 2–5 | One contextual tip per scan (lighting, angle, distance) |
| 6+ | No guidance unless quality problem detected |
| Settings | "Scanning Tips" accessible on demand for power users |

### Accuracy Expectations (v1)

| Item Type | Expected Accuracy | Detection Tier |
|---|---|---|
| Packaged goods (barcode visible) | ~99% | Barcode + Open Food Facts |
| Packaged goods (label visible) | ~85-90% | OCR |
| Common produce | ~75-85% | YOLO on-device |
| Uncommon produce | ~40-60% | Cloud LLM fallback |
| Cluttered/overlapping items | ~60-70% | Cloud LLM fallback |

**Users will always need to review and correct.** Plan for ~20-30% of items
needing manual adjustment. This is acceptable — the value is getting 70-80%
done automatically.

### Requires Backend

Only for Tier 4 (cloud LLM) — and only for items that fail on-device detection.
The API key must live server-side, not in the iOS app.

`POST /api/v1/pantry/scan` accepts cropped image regions (not full photos) and
returns a JSON ingredient list. Much smaller payloads than the original 15-photo
upload design.

---

## Feature 2: Recipe Photo Import (Cookbook Photo → Structured Recipe)

### What It Does

User photographs a recipe from a cookbook, printed card, or screen. The app
extracts title, ingredients (with quantities/units), instructions, prep/cook
times, and servings into a structured recipe ready to save.

### Recommended Architecture: Two-Tier OCR + LLM

**Tier 1 — Printed text (fast path, ~$0.0001–0.0003/recipe):**
1. Apple VisionKit `VNRecognizeTextRequest` extracts raw text on-device (free)
2. Raw text sent to cloud LLM with structured outputs → parsed JSON
3. Works well for clear printed cookbook text

**Tier 2 — Handwritten/complex layouts (fallback, ~$0.003-0.01/recipe):**
1. Send photo directly to cloud LLM vision (skip OCR)
2. Triggered when OCR confidence score < 0.75 or user taps "Scan not working"
3. Handles handwriting, two-column layouts, recipes with interspersed photos

### [DECIDED] LLM Provider: Gemini

Same as pantry scanner — Gemini 2.5 Flash-Lite for OCR text → structured JSON
parsing, Gemini 2.5 Pro as fallback for handwritten/complex layout photo analysis.
Leverages existing Google Cloud account and free tier for development.

### Output Schema

```json
{
  "title": "Chicken Parmesan",
  "servings": 4,
  "prepTimeMinutes": 20,
  "cookTimeMinutes": 35,
  "ingredients": [
    {"name": "chicken breast", "quantity": 2, "unit": "lb", "preparation": "pounded thin"},
    {"name": "marinara sauce", "quantity": 1.5, "unit": "cup"}
  ],
  "instructions": [
    "Preheat oven to 425°F.",
    "Season chicken with salt and pepper.",
    "..."
  ]
}
```

### UX Flow

1. Single photo capture (covers ~90% of cases)
   - Optional: "Add another page" for multi-page recipes (cap at 4)
   - Crop/rotate control before processing
2. Processing screen: "Scanning recipe..."
3. **Review/edit screen** (mandatory):
   - All fields editable
   - "View original photo" toggle for cross-checking
   - Null/uncertain fields highlighted
4. Save to recipe collection

### Edge Cases

- **Multi-page recipes**: Sequential capture, concatenate OCR text with `[PAGE BREAK]`
- **Metric vs imperial**: Preserve original units, don't silently convert
- **Serving adjustments**: Store original servings + raw quantities, scale client-side
- **"Use sauce from step 3"**: Preserve as-is in instruction text

### Requires Backend

Only for Tier 2 (cloud LLM). Tier 1 OCR is fully on-device.
`POST /api/v1/recipes/scan` accepts 1-4 photos, returns structured recipe JSON.

---

## Feature 3: Persistent Weekly Shopping List

### What It Does

User maintains a recurring weekly shopping list of staples. Each week they
check items off as they shop, then reset for the next week. Items can also
be added from recipes or manually.

### Recommended Architecture: Template + Instance Model

**Does NOT require a backend.** Works entirely on existing SwiftData + CloudKit.

### Data Model

Two new models (additive, CloudKit-safe):

```
ShoppingTemplate                    (the master weekly list)
  id: UUID
  name: String = ""                 e.g. "Weekly Staples"
  sortOrder: Int = 0
  createdAt: Date = Date()
  items: [TemplateItem]?            cascade, inverse: \TemplateItem.template

TemplateItem                        (one entry in the template)
  id: UUID
  name: String = ""
  quantity: Double = 0
  unit: String = ""
  category: String = "Other"
  sortOrder: Int = 0
  template: ShoppingTemplate?       back-reference
```

The existing `GroceryList` / `GroceryItem` models become the active shopping
instance. "Start New Week" creates a `GroceryList` by copying `TemplateItem`s
into `GroceryItem`s.

### Enhancements to Existing Models

- `GroceryList`: add `archivedAt: Date? = nil` (keep old lists for history)
- `Ingredient`: add `category: String = "Other"` (for recipe → shopping list flow)

All changes are additive — no CloudKit migration needed. Deploy schema changes
in CloudKit Dashboard after release.

### UX Flow

- **"Start New Week"** button stamps a fresh `GroceryList` from the template
- While shopping: check items off (checked items sink to bottom of category)
- **"Edit Staples"** opens the template editor (add/remove/reorder items)
- **"Add from Recipe"** pulls ingredients from a recipe into the active list
- Manual "+" button for one-off additions

### Sort Order: Store Aisle Layout (not alphabetical)

Default category sort order matches a typical grocery store walkthrough:
1. Vegetables/Produce
2. Eggs/Dairy
3. Meat/Protein
4. Dry & Canned Goods
5. Household
6. Frozen

This is the default. Categories are user-reorderable in settings so the order
can be adjusted for a different store layout. Items within a category sort by
template order (user-defined), not alphabetically. The `TemplateItem.sortOrder`
and a new `CategoryOrder` preference handle this — no model changes needed
beyond what's already planned.

### Integration Points

- **Recipe → Shopping List**: existing `GenerateGroceryListView` logic reusable
- **Pantry → Shopping List** (future): subtract pantry inventory from needed ingredients
- Both are additive features that layer on top of this foundation

---

## Feature 4: Shared Shopping List (Wife Can Add Items)

### What It Does

A second household member can view and edit the same shopping list from their
own iPhone. Both users see real-time updates.

### [DECIDED] Architecture: Option A — SQLiteData + CloudKit Sharing

**What**: Replace SwiftData with [SQLiteData](https://github.com/pointfreeco/sqlite-data)
(by Point-Free, 1.0 release). It's a SwiftData alternative built on GRDB + SQLite
that includes first-class CloudKit sharing (CKShare-based zone sharing).

**How sharing works**: Owner creates a shared zone containing the `GroceryList`
and its items. Sends a standard Apple share invitation (via Messages, AirDrop,
email). Spouse accepts → their app reads/writes the shared zone.

| Pros | Cons |
|---|---|
| Zero backend cost (CloudKit is free) | Requires migrating SwiftData → SQLiteData |
| No custom auth — both users use their own iCloud | Third-party dependency for core persistence |
| Standard Apple share sheet UX — no custom invite flow | Point-Free library is new (1.0 in late 2025) |
| Recipes stay private; only grocery data is shared | Migration is non-trivial (new model declarations) |
| No hosting, no monthly costs | |

**Migration scope**: Model declarations change syntax (SwiftData `@Model` →
SQLiteData macros), `@Query` property wrappers have similar equivalents, view
code changes are moderate. Estimated effort: 2-3 sessions.

### Authentication Analysis: iCloud-Only vs Google Accounts

For the immediate "wife can add items" use case, Option A requires **no
authentication UI at all** — both iPhones already have iCloud identities, and
CloudKit sharing uses those directly via the native Apple share sheet.

However, Google account support will be required for any future expansion beyond
two-iPhone-household scope:

| Future Feature | Requires Google Auth? | Why |
|---|---|---|
| Web dashboard | Yes | No iCloud identity in a browser |
| Android support | Yes | No iCloud on Android |
| Sharing with non-Apple users | Yes | Can't use CloudKit sharing |
| Spouse voting (cross-platform) | Yes | Needs platform-agnostic identity |
| Meal planning calendar sync | Maybe | Could use Google Calendar API |

**App Store constraint**: If you ever add Google Sign-In, Apple requires you to
*also* offer Sign in with Apple (Review Guideline 4.8). So adding Google auth
means implementing two auth providers, not one.

**The migration path**: Option A handles sharing now (free, no auth work). When
a future feature demands Google accounts (web dashboard is the most likely
trigger), that's the natural point to build the custom backend (Option C) with
dual auth (Google OAuth + Sign in with Apple). The SQLiteData migration isn't
wasted — the local persistence layer stays the same, and the backend becomes an
additional sync target alongside CloudKit.

**Cost of adding Google auth later**: ~2-3 sessions (FastAPI + Google OAuth +
Sign in with Apple + household model). This is the same effort whether done now
or later, so there's no penalty for deferring.

### Options Considered (for reference)

**Option B (Firebase Firestore)**: Google Sign-In is native to Firebase Auth,
making it the easiest path to Google accounts. But adds a Google SDK dependency,
creates two persistence layers (SwiftData local + Firestore shared), and recipes
would need to stay in SwiftData separately. Free tier covers a 2-person household.
Rejected in favor of A — adds complexity without enough benefit for the
immediate use case.

**Option C (Custom Backend — FastAPI + PostgreSQL)**: Full control, serves as
foundation for all future features (web dashboard, Android, spouse voting).
Google OAuth + Sign in with Apple for auth. $7-15/month hosting. Most
implementation effort (4-6 sessions). The right long-term choice if/when a
backend is needed, but premature for "wife can add items" alone. Deferred to
when a future feature requires it.

**Option D (NSPersistentCloudKitContainer / Core Data)**: Apple's native
CloudKit sharing, but requires migrating to Core Data. Not recommended — UIKit
bridging and manual lifecycle management add significant complexity in a
SwiftUI-first app.

---

## Shared Infrastructure: The Backend Question

Features 1 (pantry scanner) and 2 (recipe photo import) require a backend for
API key custody — but only for their cloud LLM tiers. The on-device tiers
(barcode, OCR, YOLO) work without any backend.

Feature 4 (sharing) uses CloudKit via Option A — no backend needed.

### [DECIDED] Backend Approach: Cloud Run (stateless API proxy)

With Option A chosen for sharing, the backend's only job is Gemini API key
custody for the cloud vision fallback in Features 1 & 2. The backend is a
**stateless API key proxy** — no database, no auth, no sessions.

#### What gets hosted

A single FastAPI app in a Docker container on Cloud Run with two endpoints:

| Endpoint | Input | Output | What It Does |
|---|---|---|---|
| `POST /pantry/scan` | ~5 cropped JPEG regions (~500KB) | Structured JSON ingredient list | Attaches Gemini API key, forwards to Gemini, returns response |
| `POST /recipes/scan` | OCR text string OR 1-4 photos (~2MB) | Structured JSON recipe | Same — API key proxy + response shaping |

No database. No auth. No background jobs. Pure request forwarding.

#### Why Cloud Run (not Cloud Functions, not GKE)

| Option | Monthly Cost | Cold Start | Verdict |
|---|---|---|---|
| **Cloud Run** | ~$0 (free tier: 2M requests/mo) | 0.5-2s (invisible — Gemini API call takes longer) | **Chosen.** Real FastAPI app structure that grows with the project |
| Cloud Functions | ~$0 (free tier: 2M invocations) | 1-3s | Works today but awkward when adding auth/middleware later |
| GKE Autopilot | ~$6-15+ minimum | None | Massive overkill — Kubernetes for a 2-endpoint proxy |
| Compute Engine | ~$5-15 (e2-micro free eligible) | None | Always-on VM for a few requests/week — wasteful |

Cloud Run advantages:
- **Scales to zero** — pay nothing when nobody's scanning. Single-household
  volume stays in free tier indefinitely.
- **Real FastAPI app** — same code structure as a full backend. When you later
  need Google OAuth, a database, or WebSocket support, just add dependencies
  and routes. No migration, no rewrite.
- **Same GCP project** as Gemini API, same billing account as travel map
  project. One project, one bill, one set of credentials.
- **Cold start is invisible** — the Gemini API call itself takes 2-5 seconds,
  so a 0.5-2s container start adds negligible latency to the user experience.

#### Future upgrade path

When a feature demands Google auth or a full backend (web dashboard, Android,
cross-platform sharing):
1. Add `google-auth` + `Sign in with Apple` middleware to the existing FastAPI app
2. Add PostgreSQL (Cloud SQL) for household/user data
3. Add new routes for sharing, voting, etc.
4. Still Cloud Run — just a bigger container. No infrastructure migration.

---

## Proposed Roadmap

The roadmap is structured to maximize free/on-device work before committing to
any paid API or hosting. Milestones marked with $ require a paid service.

### Phase 1: Shopping List Enhancement (free, no backend)

1. **Persistent weekly shopping list** (Feature 3)
   - New `ShoppingTemplate` + `TemplateItem` models
   - "Start New Week" / "Edit Staples" UX
   - Category-grouped display with checked items sinking to bottom
   - Estimated effort: 1-2 sessions

2. **UX polish on existing features**
   - Unit picker is shipping now
   - Additional input improvements based on user testing feedback

### Phase 2: On-Device Vision Foundation (free, no backend)

This is new — build all the free detection tiers before touching any paid API.

3. **Camera capture infrastructure**
   - `AVCaptureSession` + `AVCapturePhotoOutput` for guided photo mode
   - `AVCaptureVideoDataOutput` for video quick-scan mode
   - `CMMotionManager` coaching overlays (tilt, stability)
   - Brightness heuristics for lighting warnings
   - Zone-by-zone guided capture UI with thumbnail strip
   - Estimated effort: 2-3 sessions

4. **Barcode scanning + Open Food Facts lookup**
   - AVFoundation `VNDetectBarcodesRequest` for UPC/EAN detection
   - Open Food Facts API integration (free, no key needed)
   - Product name + category returned for scanned barcodes
   - Estimated effort: 1 session

5. **On-device OCR pipeline**
   - Apple VisionKit `VNRecognizeTextRequest` (.accurate mode)
   - Extract product names from visible labels
   - Confidence scoring per text region
   - Estimated effort: 1 session

6. **On-device YOLO food detection**
   - Source a pre-trained food YOLO model (start with BinhQuocNguyen
     or Ultralytics food-tuned checkpoint)
   - Export to CoreML
   - Integrate with camera pipeline — bounding boxes + class labels
   - Test accuracy on real fridge/pantry photos
   - Estimated effort: 2-3 sessions

7. **Confirmation & correction UI**
   - Confidence-based triage (auto-add / confirm / unrecognized)
   - Card-swipe review pattern
   - Voice correction via `SFSpeechRecognizer`
   - Shelf-level and item-level retake flows
   - `PantryItem` model + CloudKit sync
   - Estimated effort: 2-3 sessions

8. **Recipe photo import — OCR tier only**
   - Photo capture + crop/rotate
   - On-device OCR text extraction
   - Review/edit screen with all fields editable
   - Save to recipe collection
   - (Structured parsing is manual at this stage — user reviews raw OCR
     text and fills in fields. Still useful, just not automated.)
   - Estimated effort: 1-2 sessions

9. **Shopping list photo import — OCR tier**
   - Photograph a handwritten or printed shopping list
   - On-device OCR via same `VNRecognizeTextRequest` pipeline as milestone 5
   - Line-by-line text extraction → parsed into item name + optional quantity
   - Review/edit screen: each detected line becomes a `GroceryItem` candidate
   - User confirms, edits, or removes items before adding to active list
   - Reuses camera capture infrastructure from milestone 3 and OCR from milestone 5
   - Estimated effort: 1 session (mostly UI — OCR pipeline already exists)

**Phase 2 checkpoint**: At this point you have a working pantry scanner using
barcode + OCR + YOLO (all free), recipe photo capture with OCR, shopping list
photo import, and real user data on where on-device detection fails. This data
informs which cloud API to choose and how much cloud usage you'll actually need.

### Phase 3: Cloud Vision Integration ($)

10. **Gemini API integration spike**
    - Set up Gemini API access via existing Google Cloud account
    - Test Flash-Lite structured JSON output on food images
    - Test Pro on handwritten recipes and cluttered shelf photos
    - Estimated effort: 0.5 sessions

11. **Cloud Run backend deployment**
    - FastAPI app in Docker container on Cloud Run (same GCP project)
    - `POST /pantry/scan` — accepts cropped image regions, proxies to Gemini
    - `POST /recipes/scan` — accepts OCR text or photos, proxies to Gemini
    - Dockerfile, Cloud Build config, deploy script
    - Estimated effort: 1-2 sessions

12. **API spend monitoring & alerting**
    - GCP Budget Alert: set monthly budget ($1 initially), email alert at
      50%/90%/100% thresholds via GCP Billing → Budgets & Alerts
    - Per-request cost logging: Cloud Run logs each request with token
      count and estimated cost (structured JSON to Cloud Logging)
    - Local monitoring script (`scripts/check-api-spend.sh`): queries
      GCP Billing API for current-month spend, outputs summary. Designed
      to run as a cron job on Raspberry Pi (daily check, alert via email
      or pushover if spend exceeds threshold)
    - Cloud Run request quotas: set max-instances=1 on Cloud Run to
      cap concurrent spend; add per-IP rate limiting in FastAPI middleware
    - Dashboard: simple Cloud Monitoring dashboard showing requests/day,
      tokens/day, cost/day trend
    - Estimated effort: 0.5-1 session

13. **Recipe photo import — LLM parsing tier**
    - OCR text → cloud LLM → structured JSON
    - Handwritten/complex layout fallback (send photo directly)
    - Estimated effort: 1 session

14. **Pantry scanner — cloud fallback tier**
    - Low-confidence YOLO detections → cropped regions → cloud LLM
    - Merge cloud results into confirmation UI
    - Estimated effort: 1 session

### Phase 4: Sharing (Option A — SQLiteData + CloudKit)

15. **Shared shopping list** (Feature 4)
    - Migrate SwiftData → SQLiteData (model declarations, query wrappers, view updates)
    - Implement CKShare-based zone sharing for GroceryList + GroceryItems
    - Native Apple share sheet for inviting spouse
    - Recipes stay in private zone (not shared)
    - Estimated effort: 2-3 sessions

### Phase 5: Integration & Advanced Features

16. **Recipe ↔ Pantry integration**
    - "What can I cook?" query (match recipes against pantry)
    - "What do I need?" auto-populates shopping list with missing ingredients
    - Estimated effort: 1-2 sessions

17. **Video quick-scan mode** (optional, if photo mode proves limiting)
    - Key frame extraction + `VNTrackObjectRequest` deduplication
    - LiDAR depth hints on Pro iPhones
    - Estimated effort: 2-3 sessions

### Phase 6+: Future Features

- Fine-tune YOLO on custom pantry dataset (HF training pipeline)
- Meal planning + calendar
- Spouse voting on meal ideas
- Web dashboard
- Expiration date tracking (extend pantry scanner)
- Purchase history analytics

---

## Open Questions

### Resolved

1. ~~**LLM provider for vision features**~~ → **Gemini.** Flash-Lite for
   production, Pro for complex scenes. Existing Google Cloud account (travel
   map), existing Google OAuth integration (goodmorning), free tier covers
   dev + likely production at single-household volume. API billing is
   pay-per-token via Google Cloud, completely separate from any consumer
   Google subscription.

2. ~~**Dedicated vision APIs (Google Vision, Rekognition)**~~ → **Skip.** Too
   generic for food identification. LLM vision + on-device YOLO is better.

3. ~~**Sharing architecture**~~ → **Option A (SQLiteData + CloudKit Sharing).**
   Zero cost, no auth UI, uses existing iCloud identities. Google account
   support deferred — required for any future expansion (web dashboard,
   Android, cross-platform sharing) but unnecessary for two-iPhone household.
   When Google auth is needed, build custom backend (Option C) at that point;
   SQLiteData migration is not wasted (local persistence stays, backend
   becomes additional sync target).

4. ~~**Backend scope**~~ → **Cloud Run (stateless FastAPI proxy).** Two
   endpoints forwarding cropped images/OCR text to Gemini API. No database,
   no auth, no sessions. Same GCP project as Gemini API and existing travel
   map billing. Scales to zero (~$0/mo). Upgrades in-place to full backend
   when/if Google auth or a web dashboard is needed — just add routes and
   dependencies, no infrastructure migration.

5. ~~**YOLO model source**~~ → **Start with BinhQuocNguyen/food-recognition-model**
   (YOLO v8 + EfficientNet-B0, 101 categories, includes portion estimation).
   Evaluate on real fridge/pantry photos. Fine-tune on Food-101 + Freiburg +
   custom data only if accuracy gaps warrant it.

### Still Open

6. ~~**Video mode priority**~~ → **Phase 5 (deferred).** Photo mode is
   sufficient for v1's goal of "what's in there" with string quantity
   estimates. Video's main advantage is depth/size estimation from multiple
   angles and motion parallax — valuable for precision but not needed until
   photo mode's limitations are understood from real usage. All Phase 2
   camera infrastructure (AVCaptureSession, YOLO pipeline, confirmation UI)
   carries forward, so video is an additive layer, not a rewrite. Reference:
   SnapCalorie's single-photo portion estimation was frequently wrong —
   video with multi-angle capture would improve this, but that's a Phase 5
   refinement.

7. ~~**Voice correction scope**~~ → **Simple dictation for v1** (user says
   item name, manually sets quantity). `SFSpeechRecognizer` runs fully
   on-device since iOS 17 — mature, no network needed. Natural language
   parsing ("two cans of diced tomatoes" → quantity + item + prep) added
   as a Phase 6+ polish milestone. The NLP parsing itself isn't complex
   (regex or small on-device model), just lower priority than core detection.

8. **Progressive disclosure details**: How many zones to prompt for guided
   photo mode? Current proposal is 4-6 (top shelf, middle shelf, door,
   crisper, freezer, pantry). Needs real-world testing to calibrate.

---

## Testing Strategy

Modeled after the fractal drawing app's test infrastructure (JUnit 5 with
size-tagged categories, TestHelpers factory, golden-value checksums, headless
execution). Key constraint: **tests must run locally on Windows** via `swiftc`,
not just on macOS/Xcode.

### Two-Tier Test Architecture

**Tier 1: Pure Swift model tests (Windows-compatible, run on every commit)**

Compiled and executed via `swiftc` on Windows. No Foundation networking, no
SwiftData, no UIKit/SwiftUI. These test all domain logic in isolation.

| Category | Analogue to | What It Tests | Target Runtime |
|---|---|---|---|
| `small` | Drawing app `@SmallTest` | Model init, computed properties, validation, formatters | < 50ms |
| `medium` | Drawing app `@MediumTest` | Codable round-trips, category sorting, template→list stamping, ingredient consolidation | < 200ms |

Runs via: `scripts/test.sh` (already wired into pre-commit hook)

**Tier 2: Integration tests (macOS/Codemagic only)**

XCTest-based, run via `xcodebuild test` on Codemagic or local Mac. These test
SwiftData persistence, CloudKit constraints, and view model logic.

| Category | What It Tests |
|---|---|
| `persistence` | SwiftData CRUD, CloudKit constraint compliance (defaults, optional relationships) |
| `viewmodel` | ViewModel state transitions, data flow |
| `api` | Cloud Run endpoint contract tests (mock HTTP, validate request/response shapes) |
| `ocr` | OCR pipeline output parsing (given known OCR text, validate parsed items) |

### Test Helpers (`Models/TestHelpers.swift`)

Factory pattern matching the drawing app's `TestHelpers.java`:

```swift
// Fixture factories (pure Swift, Windows-compatible)
struct TestHelpers {
    static func recipe(name: String = "Test Recipe", ingredients: Int = 0) -> RecipeModel { ... }
    static func groceryList(name: String = "Weekly", items: Int = 3) -> GroceryListModel { ... }
    static func ingredient(name: String = "Salt", quantity: Double = 1) -> IngredientModel { ... }
    static func shoppingTemplate(name: String = "Staples", items: Int = 5) -> ShoppingTemplateModel { ... }

    // Assertion helpers
    static func assertSortedByCategory(_ items: [GroceryItemModel], order: [String]) -> Bool { ... }
    static func assertCodableRoundTrip<T: Codable & Equatable>(_ value: T) -> Bool { ... }
}
```

### What Gets Tested Per Phase

| Phase | New Test Coverage |
|---|---|
| 1.5 (Shopping list) | Template CRUD, "Start New Week" stamping, category sort order, archive, ingredient consolidation |
| 2 (On-device vision) | OCR text → item parsing, barcode → product lookup mapping, confidence thresholds, YOLO label → PantryItem mapping |
| 3 (Cloud vision) | Request/response contract tests (mock Gemini response shapes), cost logging accuracy, rate limiting |
| 4 (Sharing) | SQLiteData model equivalence with SwiftData models, share zone scoping |

### Running Tests

```bash
# Windows (pre-commit, pre-push) — pure Swift model tests
./scripts/test.sh

# macOS / Codemagic — full suite including XCTest
xcodebuild test -scheme RecipeApp -destination 'platform=iOS Simulator,name=iPhone 16'

# Backend (when Phase 3 is built)
cd server && pytest -v
```

### Test Expansion Plan

As new models and logic are added in each phase, corresponding pure-Swift test
files are added to `Models/` and compiled into the existing `test.sh` pipeline.
The `TestModels.swift` file grows (or splits into `TestShopping.swift`,
`TestPantry.swift`, etc.) following the same pattern as the drawing app's
per-package test files.

---

## API Spend Monitoring

Deployed alongside Phase 3 (milestone 12). Defense-in-depth against unexpected
API costs:

| Layer | Mechanism | Alert |
|---|---|---|
| **GCP Budget** | Billing → Budgets & Alerts, $1/mo initial threshold | Email at 50%/90%/100% |
| **Per-request logging** | Cloud Run logs token count + estimated cost per request | Cloud Monitoring dashboard |
| **Infrastructure caps** | Cloud Run max-instances=1, FastAPI per-IP rate limiting | Requests rejected beyond limit |
| **Local monitor script** | `scripts/check-api-spend.sh` queries GCP Billing API | Cron on Raspberry Pi, daily, alerts via email/pushover on spike |

The local monitor script is designed to run as a cron job on the Raspberry Pi
(already used for the goodmorning dashboard). It provides an independent check
outside of GCP's own alerting — belt and suspenders.

---

## Appendix A: Monthly Cost Projections (Single Household)

| Component | Monthly Cost |
|---|---|
| CloudKit (SwiftData sync) | Free |
| On-device detection (barcode + OCR + YOLO) | Free |
| Open Food Facts API (barcode lookup) | Free |
| Cloud LLM (4 pantry scans × ~5 ambiguous items each) | ~$0.01–0.10 |
| Cloud LLM (10 recipe scans) | ~$0.01–0.05 |
| Backend hosting (if needed) | $0–15 |
| Firebase (if Option B) | Free tier |
| **Total range** | **$0.02 – $15.15** |

Note: Cloud LLM costs are much lower than the original estimate because the
hybrid architecture only sends ambiguous items to the cloud, not every photo.

## Appendix B: Research Sources

- [Google Cloud Vision Pricing](https://cloud.google.com/vision/pricing)
- [Clarifai Food Detection](https://www.clarifai.com/customers/grocery-retailer)
- [YOLO CoreML Export — Ultralytics](https://docs.ultralytics.com/integrations/coreml/)
- [GrocerEye — YOLO Grocery Detection](https://github.com/bhimar/GrocerEye)
- [Best iOS Object Detection Models — Roboflow](https://blog.roboflow.com/best-ios-object-detection-models/)
- [BinhQuocNguyen/food-recognition-model](https://huggingface.co/BinhQuocNguyen/food-recognition-model)
- [Food-101 Dataset](https://huggingface.co/datasets/ethz/food101)
- [Food Portion Benchmark](https://huggingface.co/datasets/issai/Food_Portion_Benchmark)
- [Gemini API Pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Apple Vision Framework](https://developer.apple.com/documentation/vision)
- [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)
- [Samsung Food Ingredient Scanning](https://www.sammobile.com/news/samsung-food-update-scan-ingredients-using-phone/)
- [FridgeVisionAI](https://fridgevisionai.com/)
- [SpeechAnalyzer iOS 26](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
