# Recipe App — Design Decisions Archive

Curated archive of design research and architectural decisions. Source:
`ARCHITECTURE_PROPOSAL.md` (929 lines, deleted in commit `080fb90`). This
is not current-state documentation — see `docs/ARCHITECTURE.md` for that.
Listed here so the *why* behind architectural choices and the research
backing them isn't lost when the source doc was consolidated.

Items below are either:
- **Decided** — the rationale for a choice already baked into the current
  architecture, kept so it can be re-evaluated later with the original
  context.
- **Research** — comparison tables, cost projections, and accuracy
  expectations that informed choices and would be expensive to
  reconstruct from scratch.

---

## Decisions

### Cloud LLM provider → Gemini

**Chosen**: Gemini 2.5 Flash-Lite for production, Gemini 2.5 Pro fallback
for complex scenes.

**Rationale**:
- Cheapest option (~$0.0001/image for Flash-Lite)
- Generous free tier (1K req/day) covers dev and likely single-household production
- Existing Google Cloud account (travel-map project) — no new billing setup
- Existing Google OAuth integration reused from `goodmorning` project
- Structured JSON output via Gemini's response schema feature
- Can upgrade to Pro for complex scenes without changing infrastructure

**Alternatives rejected**:
- **GPT-4o / GPT-4o-mini** — 10-30x more expensive for similar accuracy at our volume
- **Claude Haiku 4.5** — best structured JSON output but no existing billing relationship
- **Google Cloud Vision / Rekognition** — returns generic labels ("fruit", "dairy") not
  ingredient-level identification. Skip.
- **Clarifai food model** — only dedicated food API worth considering, but an LLM vision
  call is more flexible (quantities, categories, confidence in one JSON response) for
  similar cost.

**Note**: Current architecture is **no cloud LLM calls, everything on-device**
(see `docs/ARCHITECTURE.md`). This decision stands as the vetted plan if/when
a cloud tier is added. See also BACKLOG.md "Cloud vision fallback".

### Backend approach → Cloud Run (stateless proxy)

**Chosen**: FastAPI container on Cloud Run, stateless API-key proxy for
Gemini. No database, no auth, no sessions.

**Rationale**:
- Scales to zero — pay nothing when idle. Single-household volume stays
  in free tier (2M requests/mo) indefinitely.
- Real FastAPI app structure that grows with the project — adding Google
  OAuth or a database is just new dependencies and routes, no infra
  migration.
- Same GCP project as Gemini API, same billing as travel-map project.
- Cold start (0.5-2s) is invisible because the Gemini API call itself
  takes 2-5s.

**Alternatives rejected**:

| Option | Monthly Cost | Why rejected |
|---|---|---|
| Cloud Functions | ~$0 free tier | Works today but awkward when adding auth/middleware later |
| GKE Autopilot | ~$6-15+ minimum | Massive overkill — Kubernetes for a 2-endpoint proxy |
| Compute Engine | ~$5-15 | Always-on VM for a few requests/week is wasteful |

**Endpoints planned**:
- `POST /pantry/scan` — cropped JPEG regions → structured ingredient JSON
- `POST /recipes/scan` — OCR text OR 1-4 photos → structured recipe JSON

**Note**: Not deployed. `server/` is a placeholder. This stands as the
vetted plan for when/if the cloud tier is built.

### Shared shopping architecture → Option A (SQLiteData + CloudKit sharing)

**Chosen**: Replace SwiftData with [SQLiteData](https://github.com/pointfreeco/sqlite-data)
(Point-Free, 1.0 release) to get first-class CloudKit zone sharing via
`CKShare`. Native Apple share sheet for inviting; no custom auth.

**Rationale**:
- Zero backend cost (CloudKit is free)
- No custom auth — both users use their own iCloud
- Standard Apple share sheet — no custom invite flow
- Recipes stay private; only grocery data is shared
- Migration isn't wasted: if we later add a backend, local persistence
  stays the same and the backend becomes an additional sync target.

**Alternatives considered**:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. SQLiteData + CloudKit sharing** | Zero cost, native UX, no auth | New 1.0 library; SwiftData migration needed | **Chosen** |
| B. Firebase Firestore | Native Google Sign-In, free tier fits | Two persistence layers (SwiftData local + Firestore shared), SDK dep | Rejected: complexity without benefit for 2-person use case |
| C. Custom FastAPI + PostgreSQL backend | Full control; foundation for web/Android | $7-15/mo, 4-6 sessions impl | Deferred: premature until a cross-platform feature demands it |
| D. NSPersistentCloudKitContainer / Core Data | Apple-native sharing | Requires Core Data migration; UIKit bridging | Rejected: SwiftUI-first app, not worth the complexity |

**Migration cost**: Estimated 2-3 sessions (model declarations, query
wrappers, view updates). Not started.

### YOLO model starting point → BinhQuocNguyen/food-recognition-model

**Chosen**: BinhQuocNguyen/food-recognition-model (YOLO v8 + EfficientNet-B0,
Food-101, 101 categories, includes portion estimation and USDA calorie DB).
Fine-tune on Food-101 + Freiburg + custom data only if accuracy gaps warrant.

**Current state**: Actually shipped the **nateraw/food** ViT classifier
(`FoodClassifier.mlpackage`, 164MB, 101 classes) for pantry item
classification. YOLO detection (multi-object bounding boxes) is still
open — see BACKLOG.md "YOLOv3" for the open question of whether Apple's
COCO-trained YOLOv3 is useful for pantry use or if a custom detector is
needed.

### Authentication stance → iCloud-only, Google auth deferred

**Current**: No auth. iCloud identity handles single-user sync.

**When Google auth would be needed**:

| Future feature | Requires Google auth? | Why |
|---|---|---|
| Web dashboard | Yes | No iCloud identity in a browser |
| Android support | Yes | No iCloud on Android |
| Sharing with non-Apple users | Yes | Can't use CloudKit sharing |
| Cross-platform spouse voting | Yes | Platform-agnostic identity needed |
| Meal planning calendar sync | Maybe | Could use Google Calendar API |

**App Store constraint**: If you ever add Google Sign-In, Apple requires you to
*also* offer Sign in with Apple (App Store Review Guideline 4.8). So adding
Google auth means implementing two providers, not one.

**Cost of deferring**: ~2-3 sessions (FastAPI + Google OAuth + Sign in with
Apple + household model). Same effort now or later, so no penalty for
deferring until a feature requires it.

---

## Research reference

### Vision API comparison (cloud LLMs)

| Provider | Model | Cost/Image | Food accuracy | Notes |
|---|---|---|---|---|
| **Google** | Gemini 2.5 Flash-Lite | ~$0.0001 | Very good | Cheapest; 1K req/day free tier |
| **Anthropic** | Claude Haiku 4.5 | ~$0.0003–0.005 | Very good | Best structured JSON output |
| **Google** | Gemini 2.5 Pro | ~$0.0003–0.003 | Excellent | Best Google option for complex scenes |
| **OpenAI** | GPT-4o-mini | ~$0.001 | Good | Budget option |
| **OpenAI** | GPT-4o | ~$0.003–0.006 | Excellent | Best on cluttered layouts |

All can identify specific food items (not just "food"), return structured
JSON, and handle produce + packaged goods in the same frame. The hybrid
architecture makes the provider choice low-stakes — only ambiguous items
go to the cloud, so swapping providers is trivial.

### Dedicated vision APIs (purpose-built)

| Provider | Capability | Cost/Image | Food-specific? | Verdict |
|---|---|---|---|---|
| Clarifai | Food Model | Free tier | Yes — 1000+ items | Best dedicated food API |
| Google Cloud Vision | Label Detection | ~$0.002 | Generic only | Too broad for ingredients |
| Amazon Rekognition | Label Detection | ~$0.001 | Generic only | Same problem |

### On-device options

| Option | Accuracy | Food-specific? | iOS integration |
|---|---|---|---|
| YOLO11 + CoreML | 82-85% mAP (food-tuned) | Yes if fine-tuned | CoreML export, 60+ FPS |
| GrocerEye (YOLOv3) | 84.6% mAP | Yes — grocery shelves | Needs CoreML conversion |
| Apple Vision (`VNClassifyImageRequest`) | Moderate | No — general | Native, trivial |
| Apple VisionKit OCR | 85-95% on text | N/A | Native, trivial |

### Pantry scanner accuracy expectations (v1 targets)

| Item type | Expected accuracy | Detection tier |
|---|---|---|
| Packaged goods (barcode visible) | ~99% | Barcode + Open Food Facts |
| Packaged goods (label visible) | ~85-90% | OCR |
| Common produce | ~75-85% | On-device classifier |
| Uncommon produce | ~40-60% | Cloud LLM fallback |
| Cluttered/overlapping items | ~60-70% | Cloud LLM fallback |

**Planning rule**: Users will always need to review and correct. Plan for
~20-30% of items needing manual adjustment. The value is getting 70-80%
done automatically.

### Pantry scanner — 4-tier hybrid pipeline

Originally proposed architecture for pantry scanner, free-to-paid in
priority order. Tiers 1-3 are on-device and shipped; tier 4 is the open
cloud-fallback question.

1. **Barcode scan** (free, ~99%) — AVFoundation barcode detection →
   Open Food Facts lookup. Covers ~50-60% of a typical fridge.
2. **OCR for visible labels** (free, ~85-95%) — `VNRecognizeTextRequest`
   `.accurate` mode extracts product names from cans/boxes.
3. **On-device classification** (free, ~82-85% mAP) — currently Food-101
   ViT classifier, originally proposed YOLO11 for detection. Provides
   bounding boxes + class labels for produce and unlabeled items.
4. **Cloud LLM vision** (paid, ~$0.002/photo, open) — cropped regions of
   low-confidence detections only. Handles edge cases: unusual produce,
   cluttered shelves, bulk items.

### Cost projections (single household, if cloud tier is enabled)

| Component | Monthly cost |
|---|---|
| CloudKit (SwiftData sync) | Free |
| On-device detection (barcode + OCR + classifier) | Free |
| Open Food Facts API | Free |
| Cloud LLM (4 pantry scans × ~5 ambiguous items each) | ~$0.01–0.10 |
| Cloud LLM (10 recipe scans) | ~$0.01–0.05 |
| Cloud Run backend hosting | $0 (free tier) |
| **Total range** | **$0.02 – $0.15** |

Cloud LLM costs are low because the hybrid architecture only sends
ambiguous items to the cloud, not every photo.

---

## UX specs worth preserving

### Pantry scanner confirmation & correction flow

**Confidence thresholds** (still used by `DetectionClassifier.swift`):

| Confidence | Action | UI treatment |
|---|---|---|
| > 0.85 | Auto-added | Collapsed "Added" section, green indicator |
| 0.55–0.85 | "Please confirm" queue | Expanded card with photo crop + label |
| < 0.55 | "Unrecognized" | Photo crop shown, user names or skips |

**Correction methods**:
- **Card-swipe**: Swipe right = confirm, left = dismiss, tap = edit
- **Voice correction** (not built): Tap mic → `SFSpeechRecognizer`
  (on-device iOS 17+) → "two cans of diced tomatoes" → parsed. Auto-stops
  after 2-3s silence.
- **Shelf-level retake**: Re-scan a section; results merge (dedupe by
  identity, not name).
- **Item-level retake**: Camera icon on any card.
- **Manual add**: "+" for items scanner missed entirely.

**Progressive coaching disclosure**:

| Scan # | Guidance level |
|---|---|
| 1st | Full hand-holding — animated overlay |
| 2-5 | One contextual tip per scan |
| 6+ | No guidance unless quality problem detected |

### Recipe photo import — edge cases

- **Multi-page recipes**: Sequential capture, concatenate OCR text with `[PAGE BREAK]` marker
- **Metric vs imperial**: Preserve original units; don't silently convert
- **Serving adjustments**: Store original servings + raw quantities; scale client-side
- **"Use sauce from step 3"**: Preserve as-is in instruction text (don't try to resolve references)

### Recipe photo import — output schema (LLM tier, not built)

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
    "Season chicken with salt and pepper."
  ]
}
```

---

## API spend monitoring (planned, for when cloud tier lands)

Defense-in-depth against unexpected API costs:

| Layer | Mechanism | Alert |
|---|---|---|
| GCP Budget | Billing → Budgets & Alerts, $1/mo initial threshold | Email at 50%/90%/100% |
| Per-request logging | Cloud Run logs token count + cost per request | Cloud Monitoring dashboard |
| Infrastructure caps | Cloud Run `max-instances=1`, FastAPI per-IP rate limiting | Requests rejected beyond limit |
| Local monitor | `scripts/check-api-spend.sh` queries GCP Billing API, cron on Raspberry Pi | Email/pushover on daily spend spike |

Independent check outside GCP's own alerting — belt and suspenders.

---

## Research sources

- [Google Cloud Vision pricing](https://cloud.google.com/vision/pricing)
- [Clarifai food detection](https://www.clarifai.com/customers/grocery-retailer)
- [YOLO CoreML export (Ultralytics)](https://docs.ultralytics.com/integrations/coreml/)
- [GrocerEye — YOLO grocery detection](https://github.com/bhimar/GrocerEye)
- [Best iOS object detection models (Roboflow)](https://blog.roboflow.com/best-ios-object-detection-models/)
- [BinhQuocNguyen/food-recognition-model](https://huggingface.co/BinhQuocNguyen/food-recognition-model)
- [Food-101 dataset](https://huggingface.co/datasets/ethz/food101)
- [Food Portion Benchmark](https://huggingface.co/datasets/issai/Food_Portion_Benchmark)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Apple Vision framework](https://developer.apple.com/documentation/vision)
- [VNTrackObjectRequest](https://developer.apple.com/documentation/vision/vntrackobjectrequest)
- [Samsung Food ingredient scanning](https://www.sammobile.com/news/samsung-food-update-scan-ingredients-using-phone/)
- [FridgeVisionAI](https://fridgevisionai.com/)
- [SpeechAnalyzer iOS 26](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [SQLiteData (Point-Free)](https://github.com/pointfreeco/sqlite-data)
- [App Store Review Guideline 4.8 — Sign in with Apple](https://developer.apple.com/app-store/review/guidelines/#sign-in-with-apple)
