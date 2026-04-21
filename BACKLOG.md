# Recipe App — Backlog

Unscheduled ideas for evaluation. Items here are not committed work — they
are things to consider, research, or explicitly decline before they accrete
into the active plan. Move an item out of this file when a decision is
made (into an issue, into the plan, or deleted with a reason).

**Key architectural decisions (2026-04-21)**:
- **Server is source of truth** — not CloudKit. CloudKit becomes optional
  local-only cache for offline access.
- **Cross-platform sharing** — iOS ↔ web via share links.
- **Not real-time** — snapshot sharing; polling/pull-to-refresh is fine.

---

## P0 — High priority (blocks other work)

### Server-canonical sync (sharing prerequisite)
Currently the iOS app writes to SwiftData/CloudKit and the server is a
separate island. To share anything, the server must own the data.

**Work required**:
- **Auth on iOS**: Server has Google OAuth + JWT. Add sign-in flow to iOS
  (Google Sign-In SDK → exchange for JWT → store in Keychain).
- **Sync protocol**: On app launch and periodically, sync local SwiftData
  with server. Conflict resolution: server wins (last-write-wins by
  `updatedAt`). Offline edits queue locally and push on next connectivity.
- **Migration**: Existing local-only recipes need a one-time upload to
  server on first sign-in.
- **Schema alignment**: Server `Recipe`/`Ingredient` models already mirror
  iOS. Verify parity and add any missing fields (e.g. `isFavorite`,
  `imageData`).

### Share-by-link (read-only)
The simplest sharing primitive. Covers 80% of use cases.

User taps "Share" on a recipe or shopping list → server generates a
stable URL (`/r/<uuid>` or `/list/<uuid>`) → shareable via iOS share
sheet → anyone with the link views on web, no account needed.

**Model changes**:
- `share_token` (UUID, nullable) on `Recipe` and `GroceryList`. Non-null
  = accessible at public URL.
- `GET /api/v1/recipes/shared/<token>` — no auth, read-only.
- `GET /api/v1/grocery/shared/<token>` — same for shopping lists.

**Privacy**: Token generation is explicit. Revoke = null the token.
Tokens are unguessable UUIDs.

### `--dry-run` for destructive scripts (GM-2)
Important scripts must support `--dry-run` to avoid destructive cloud
side effects. See Linear GM-2 for full context (orphaned App Store
Connect cert from a script crash).

---

## P1 — Medium priority (valuable, not blocking)

### Recipe images: step photos + hero image
Recipes imported from the web often have images. Currently
`ImportedRecipe.imageURL` is extracted but never fetched or stored.

- New `RecipeImage` model: `id`, `data`, `displayOrder`, `isHero`,
  `stepIndex` (nullable), `sourceURL`.
- **Import**: Fetch `imageURL` (hero) and `HowToStep.image` from JSON-LD.
  Resize to 1200px wide, store as JPEG for cross-platform compat.
- **Upload**: `PhotosPicker` or camera capture from edit screen.
- **Storage**: Server-canonical. iOS caches locally via
  `@Attribute(.externalStorage)`. Max 10 images per recipe.

### Recipe-in-shopping-scan detection
When user photographs a recipe from the "Scan Shopping List" button,
it gets jammed through the shopping-list parser → garbage output.

**Direction**: After OCR, peek at text before choosing a parser.
`QualityGate.sectionFromHeader` already recognizes recipe headers.
If >= 2 recipe markers present, prompt "This looks like a recipe —
switch to Recipe mode?"

### Post-OCR text correction for common misreads
Handwritten-list scans produce "E995" (Eggs), "Milz" (Milk). Pipeline
trusts Vision output verbatim → items land in "Other".

**Direction**: After `parseShoppingListText`, fuzzy match each name
against `GroceryCategorizer`'s vocabulary (edit distance 1-2). Surface
"Did you mean X?" in review sheet rather than auto-replacing.

### Multi-user access (ACL model)
For household collaboration and recipe co-ownership. Depends on
server-canonical sync.

```
RecipeAccess    (recipe_id, user_id, role)
GroceryListAccess (list_id, user_id, role)
```
Roles: `owner` (full control), `editor` (content only), `viewer`
(read-only). Creator is always owner. Multiple owners supported.

### Test consolidation
575 test cases across 15 suites for probably fewer than 100 features.
Many tests are subsets of larger tests — if the bigger test fails, the
smaller one would too.

**Direction**: Audit each suite. Where multiple tests cover the same
function and some are strict supersets, remove the smaller ones. Goal
is fewer, more meaningful tests — not fewer assertions. Keep edge-case
tests that exercise distinct code paths; collapse tests that just repeat
simpler cases of the same path.

**Candidates to audit first** (largest suites):
- ListParser (94 tests), RecipeSchemaParser (87), GroceryCategorizer (70),
  QualityGate (63), OCR (45), Shopping (35)

### Duplicate-payload guard in `scripts/build.sh`
Post-archive step that inspects the IPA and fails if:
- Two source entries resolve to the same file
- Individual resources > 50MB or total payload > 250MB

Triggered by the 330MB IPA incident. Do after any new ML model is added.

---

## P2 — Low priority (nice-to-have)

### Per-tab scan button instead of global Scan tab
Scan tab asks "what are you scanning?" before you've picked a target.
Better: put scan buttons on the views that own the data (shopping list
detail, recipe list, pantry). Scan tab stays as debug surface.

### Public recipe library
`is_public` boolean on Recipe. Public recipes appear in a browseable
web catalog with SEO (Open Graph meta). Optional user profiles
(`/u/<username>`). Only relevant if the app grows beyond household use.

### Web interface for recipes (GM-3)
Desktop recipe creation/editing via web frontend. See Linear GM-3.
Becomes more natural once server-canonical sync is done — the web
frontend and iOS app share the same server API.

---

## Research / evaluation needed

### Food-101 classifier is wrong for pantries
Food-101 ViT classifies *plated dishes*. Pantry shelves show cans and
boxes → nonsense labels. YOLOv3 COCO classes also poor overlap (~8
pantry items). Realistic fix: fine-tuned detector on grocery vocabulary.
Until then, mark pantry scan as experimental.

### BERT-SQuAD — question answering over recipe text
On-device Q&A: "What temperature?" / "How long does this bake?" while
viewing a recipe. ~210MB CoreML model; ~1-3s inference on A17. Would push
IPA to ~500MB with Food-101. Evaluable on Windows via PyTorch.

### YOLOv3 — pantry object detection
COCO 80-class vocabulary has limited pantry overlap. Evaluate on 20-30
pantry photos to decide if useful or if custom training is needed.
Evaluable on Windows via `ultralytics`.

---

## Not planned (documented for context)

### Multi-language recipe support
All OCR, parsing, and categorization hard-codes English. Would need
per-locale keyword tables, section headers, Vision language config,
localized UI, and per-locale test fixtures. Revisit only for public
release.

### Meal planning + calendar
Weekly meal plan UI: pick recipes per day, auto-generate grocery list.
No design yet.

### Spouse voting / meal ideas
Family members vote on candidate meals. Requires shared lists + voting
model + push notifications. Pure idea.

### Recipe ↔ pantry integration
"What can I cook?" (match recipes vs pantry) and "What do I need?"
(diff recipe vs pantry → shopping list). Feasible on-device today.
Not prioritized.

### Cloud vision fallback (Gemini / hosted LLM)
Architecture is explicitly **no cloud LLM calls**. The original Phase 3
proposed a Cloud Run + Gemini proxy for hard OCR cases. Rejected as a
cost/privacy choice. Re-evaluable; design doc in `docs/DESIGN_DECISIONS.md`.
