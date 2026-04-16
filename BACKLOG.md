# Recipe App — Backlog

Unscheduled ideas for evaluation. Items here are not committed work — they
are things to consider, research, or explicitly decline before they accrete
into the active plan. Move an item out of this file when a decision is
made (into an issue, into the plan, or deleted with a reason).

## Build / Tooling

### Duplicate-payload guard in `scripts/build.sh`
**Why**: We just shipped a fix for a 330MB IPA caused by `project.yml`
bundling the `.mlpackage` twice (raw + compiled). As more ML/vision models
land (Food-101 ViT today; possibly BERT-SQuAD, YOLOv3 later — see
"On-device models to evaluate" below), a second duplicate-bundling
regression is plausible.

**Proposal**: Add a check to `build.sh` (or a dedicated script invoked
by it) that inspects what the iOS target will actually ship and flags:
- Two sources entries that resolve to the same file
- A resource file and a source file with the same basename that would
  both land in `Resources/`
- Individual resources over a configurable size threshold (e.g. 50MB)
- Total estimated bundle payload over a threshold (e.g. 250MB)

**Hard bit**: xcodegen's input is declarative YAML, but the *actual*
compiled+copied set is only knowable after xcodebuild. On Windows we can
only analyze `project.yml` statically; the full truth ships from Codemagic.
One option is a post-archive step in `codemagic.yaml` that `unzip`s the
IPA, walks its contents, and fails the build if it exceeds bounds — that
at least catches regressions pre-delivery.

**Priority**: Medium. Do after any new ML model is added to the bundle.

---

## Scanner UX follow-ups

These were noticed during dogfooding after GM-6/7/8 landed (2026-04-16).
None are crash bugs — they're UX papercuts where the current behavior is
"wrong shape" rather than broken.

### Recipe-in-shopping-scan detection
**Problem**: When the user photographs a recipe but fires it from the
"Scan Shopping List" button, the OCR text obviously looks like a recipe
(has "Ingredients:", "Method:", step numbers, etc.), but it gets jammed
through the shopping-list parser anyway. The resulting grocery list is
mostly garbage tokens from the method paragraphs.

**Direction**: After OCR, peek at the text before choosing a parser.
`QualityGate.sectionFromHeader` already recognizes recipe section
headers — reuse that. If >= 2 recipe-shape markers are present in a
shopping-list scan, surface a "This looks like a recipe — switch to
Recipe mode?" prompt in the review sheet rather than just showing
parser garbage.

**Priority**: Medium. Real recipes fail silently today.

### Per-tab scan button instead of global Scan tab
**Problem**: The Scan tab is a hub that asks "what are you scanning?"
before you've picked a list / recipe / pantry. Users land on a grocery
list, want to scan into *that* list, and have to: leave the list →
Scan tab → pick mode → then the list picker at the bottom defaults to
"some list" which may not be the one they came from.

**Direction**: Put scan buttons on the views that own the data:
- Shopping list detail → "Scan into this list" (OCR + barcode)
- Recipe list → "Scan recipe" (OCR only, mode=.recipe)
- Pantry → "Scan pantry" (already has camera button in PantryView)

The Scan tab stays as a fallback / debug surface for the scan log.

**Priority**: Low-Medium. Current flow works, just takes extra taps.

### Food-101 classifier is the wrong model for pantries
**Problem**: The shipped `FoodClassifier.mlpackage` is a fine-tune of
Food-101 ViT, whose 101 classes are all *plated dishes* ("baklava",
"beef carpaccio", "huevos rancheros"). Photographing a pantry shelf
shows tomato cans and cereal boxes and the model confidently picks a
plated-dish label at 100%+ confidence. GM-7 clamped the display to
100%, but the underlying "plated dish for raw pantry goods" problem
remains.

**Direction**: See "YOLOv3 — pantry object detection" section below.
YOLOv3's COCO classes are also a poor match (only ~8 overlap with
real pantry stock), so the honest answer is probably a fine-tuned
detector on a grocery-store vocabulary. Until that's trained, the
pantry scan feature should be marked experimental in the UI.

**Priority**: Blocked on model work. Cosmetic fix (experimental
badge) is cheap; real fix (new model) is a significant project.

### Post-OCR text correction for common misreads
**Problem**: Handwritten-list scans produce items like "E995" (should
be "Eggs"), "Milz" (Milk), "Bbanana" (Banana). Current pipeline
trusts Vision output verbatim and then runs `GroceryCategorizer`,
which can't categorize these garbled tokens so they land in "Other".

**Direction**: After `parseShoppingListText`, run each item name
through a lightweight fuzzy match against `GroceryCategorizer`'s
known-items vocabulary (edit distance 1-2, prefer exact substring
matches). Surface corrections in the review sheet with a subtle
"Did you mean X?" affordance rather than auto-replacing, so the
user stays in control.

**Priority**: Medium. This is the main reason handwritten-list scans
feel "almost working but not quite".

---

## On-device models to evaluate

Both are listed in Apple's public CoreML model gallery, so they have
first-party CoreML conversions and license terms that permit shipping
them inside the app (unlike random HuggingFace weights).

### BERT-SQuAD — question answering over recipe text
**Use case**: "What ingredients do I need for this recipe?" /
"How long does this bake?" / "What temperature?" asked in natural
language while looking at a saved recipe. Runs entirely on-device so
no privacy concerns, no API costs.

**Open questions**:
- Model size — BERT-base SQuAD from Apple is ~210MB CoreML. Added on
  top of the ~164MB Food-101 model, total shipped weights would be
  ~375MB. Combined with app code + assets, IPA could push 500MB.
  Need the duplicate-payload guard above to prevent surprises.
- Latency on iPhone — SQuAD inference on BERT is slow (~1–3s on A17).
  Acceptable for a "ask a question" flow; not acceptable as a live
  autocomplete.
- Scope — just the current recipe's text, or across the user's whole
  SwiftData store? Start with single-recipe to keep context short.

**Windows-evaluability**: Partial. Can run SQuAD inference on Windows
with `transformers` + PyTorch to validate accuracy against a small
hand-labeled set of recipe Q&A pairs before committing to CoreML
conversion + iOS integration. Cannot measure iPhone latency from
Windows — that needs Codemagic or a TestFlight build.

### YOLOv3 — pantry object detection
**Use case**: Originally planned in Phase 2D (pantry scanning). Still
not implemented.

**Open questions**:
- Apple's published YOLOv3 CoreML model is trained on COCO's 80 classes
  (person, dog, bicycle, …). Only a handful of those overlap with
  pantry items (banana, apple, orange, broccoli, carrot, sandwich,
  pizza, donut, cake, …). Not great coverage for a real pantry.
- A Food-101 classifier (already shipped in-bundle) is classification,
  not detection — it expects one dominant food per image. YOLOv3 is
  detection: multiple items per image with bounding boxes. These are
  complementary, not substitutes.
- Realistic path is probably: evaluate YOLOv3 on a set of 20–30 pantry
  photos to decide if its 80-class vocabulary is useful enough, or if
  we need a custom-trained detector with grocery-store vocabulary.

**Windows-evaluability**: Yes. `ultralytics` / raw YOLOv3 ONNX runs on
Windows. Can score the bundled classes against representative pantry
images in the existing `scripts/layout-bench/` style pipeline before
deciding whether to ship.

---

## Productionization (far-future, not planned)

### Multi-language recipe support
**Status**: Not planned. Listed here so the limitation is explicit.

**Current behavior**: All OCR, parsing, and categorization code
hard-codes English vocabulary. Specifically:
- `VNRecognizeTextRequest` in `ScanProcessor` sets
  `recognitionLanguages = ["en-US"]`
- `GroceryCategorizer` matches English keyword tables
- `QualityGate.sectionFromHeader` matches English headers only
  ("Ingredients", "Method", "Step N", …)
- `OCRParser` time/servings parsing assumes English words
  ("minutes", "serves", "yield")

**What a real multi-language release would need**:
- Per-locale keyword tables for the categorizer
- Per-locale section headers + recipe-vocabulary regex
- Vision recognition language selected from user locale (or auto)
- Localized UI strings (all hardcoded today)
- Test fixtures in each supported locale

**Decision**: Revisit only if the app moves from single-user
(Nick's household) to a public release. Document the English-only
assumption in README when docs are cleaned up so future-Claude doesn't
assume otherwise.

---

## Future direction (not planned)

These were phases on the original Phase 1–5 roadmap (see pre-cleanup
`README.md` / `WORKPLAN.md` in git history before commit `080fb90`).
They're not scheduled work and architecture may have shifted since the
roadmap was written — listed here so the intent isn't lost.

### Backend sync server
FastAPI skeleton exists in `server/` but nothing is deployed. CloudKit
private DB covers single-user persistence today. A real backend would be
needed for cross-household or cross-platform features (shared lists that
span an Android user, web dashboard, household-level analytics). Revisit
only when a concrete cross-boundary use case appears.

### Meal planning + calendar
Weekly meal plan UI: pick recipes for each day, auto-generate that week's
grocery list from the plan. Would pair with a calendar view and
carry-over logic for leftovers. No current work; listed to pin the idea.

### Shared shopping lists (spouse/household)
Already noted in `docs/ARCHITECTURE.md` as a future phase. Expected path:
migrate SwiftData → SQLiteData, use CKShare zone sharing for
`GroceryList` + `GroceryItem` (recipes stay private). Native Apple share
sheet for inviting. Not started.

### Spouse voting / meal ideas
"Family members vote on candidate meals for the week." Requires shared
shopping lists (above) as a prerequisite, plus a voting model and probably
push notifications. Pure idea — no design yet.

### Recipe ↔ pantry integration
Two queries against the existing `PantryItem` store:
- "What can I cook?" — match recipes whose ingredients are mostly in pantry
- "What do I need?" — diff recipe ingredients against pantry, auto-populate
  shopping list with the missing items
Both feasible on-device today (pantry + recipes are both local SwiftData).
Blocked only by not having been prioritized.

### Cloud vision fallback (Gemini / hosted LLM)
Current architecture is explicit: **no cloud LLM calls, everything on-device**.
The original roadmap had a Phase 3 that proposed a Cloud Run + Gemini proxy
for the hard cases OCR + CoreML can't handle (cursive handwriting, dense
cookbook layouts, low-confidence pantry shelves). Rejecting this is a
deliberate cost / privacy choice; recording it as an alternative so the
decision is re-evaluable. If revisited, spend monitoring (GCP budget
alerts + per-request token logging) is a hard prerequisite, not a nice-to-have.
The vetted-at-the-time plan with vendor comparisons, cost projections, and
the stateless Cloud Run proxy design lives in `docs/DESIGN_DECISIONS.md`.
