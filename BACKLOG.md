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

**Status**: Auth complete (2026-04-27). Sync protocol is next.

**Auth (DONE)**:
- ~~Auth on iOS~~ — Native Google Sign-In SDK. Flow: native Google
  sheet → ID token → `POST /auth/mobile/google` → server verifies via
  `google-auth` → JWT. "Continue without signing in" for local-only use.
- Server redeployed to Cloud Run (2026-04-28) with `google-auth` +
  `requests` dependencies. Endpoint live and verified.

**Sync protocol (TODO)**:

*First login flow*:
1. User signs in with Google for the first time.
2. App detects no server-side recipes for this user.
3. All local SwiftData recipes uploaded to server in bulk
   (`POST /api/v1/recipes` per recipe, or batch endpoint).
4. Each local recipe gets a `serverId` stored locally for future sync.

*Ongoing sync*:
- On app launch + pull-to-refresh: fetch server recipe list with
  `updatedAt` timestamps. Compare against local `updatedAt`.
- **Server newer** → pull and overwrite local copy.
- **Local newer** → push to server (`PUT /api/v1/recipes/:id`).
- **New local recipe** (no `serverId`) → push to server, store returned ID.
- **Deleted on server** (server returns 404 for known `serverId`) → mark
  local as deleted (soft-delete, recoverable for 30 days).
- **Deleted locally** → `DELETE /api/v1/recipes/:id` on server.
- **Conflict** (both changed since last sync) → server wins, but stash
  local version as "conflicted copy" the user can review.

*Data safety (critical)*:
- **Never delete without confirmation**: conflicting changes produce a
  recoverable copy, not silent overwrite.
- `needsSync: Bool` + `lastSyncedAt: Date?` + `serverId: String?` on
  local `Recipe` model.
- Offline edits queue locally and push on next connectivity.
- All sync operations are idempotent (PUT with full recipe payload).

*Server-side backup*:
- Weekly automated DB backup (pg_dump or equivalent).
- Keep 4 rolling backups (1 month of coverage).
- Store in Cloud Storage bucket with lifecycle policy to auto-delete
  older backups.
- Manual restore script for disaster recovery.

*Schema alignment*:
- Server `Recipe`/`Ingredient` models already mirror iOS.
- Verify field parity: `isFavorite`, `cuisine`, `course`, `tags`,
  `sourceUrl`, `difficulty`, `isPublished`, `imageData`.
- Add any missing fields to server before starting sync work.

**Research done (2026-04-28)**:
- Web frontend at `recipes.ouryearofwander.com` reads from server
  Postgres via `GET /api/v1/recipes`. Currently shows placeholder data.
- Frontend has full CRUD: `RecipeListPage`, `RecipeDetailPage`,
  `RecipeEditorPage`. Auth-guarded editing. Login page exists at `/login`.
- Server API already has `POST`, `PUT`, `PATCH`, `DELETE` for recipes.
- iOS `Recipe` SwiftData model fields: `name`, `summary`, `instructions`,
  `prepTimeMinutes`, `cookTimeMinutes`, `servings`, `cuisine`, `course`,
  `tags`, `sourceUrl`, `difficulty`, `isFavorite`, `isPublished`,
  ingredients (relationship).
- Server `Recipe` SQLAlchemy model fields: same set, plus `created_at`,
  `updated_at`, `user_id`.

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

### Auto-populated staples from purchase history
"Remove Checked" in the grocery store is a natural purchase signal. Use
it to build purchase history and auto-suggest staples.

**Model changes**:
- `GroceryItem`: add `checkedAt: Date?` (set on check toggle),
  `archivedAt: Date?` (set on "Remove Checked" — soft delete).
- "Remove Checked" = archive (soft delete), not hard delete.
  Items disappear from active view but stay in DB as purchase history.
- Settings → "Clear Purchase History" for hard delete.

**Staple suggestion logic**:
- Query archived items grouped by normalized name.
- Compute frequency: `appearances / weeks_of_history`.
- Items with frequency >= 0.6 AND not already in template →
  "Suggested Staples" section in TemplateEditorView.
- User taps "Add" to promote a suggestion to the template.

**Files to change**: `GroceryItem.swift`, `GroceryItemRow.swift`,
`ShoppingListDetailView.swift`, `ShoppingViewModel.swift`,
`TemplateEditorView.swift`, Settings view (new "Clear Purchase History").

**User context**: Nick uses "Remove Checked" while walking through the
store to keep the view clear. This workflow naturally captures purchase
events with no extra taps.

### Re-seed grocery list with Staples
There is currently **no way to re-populate a grocery list from the staples
template** — you can build a template but not one-tap seed a fresh/active
grocery list from it. Add an explicit "Add Staples" (or "Re-seed from
template") action on the grocery list.

- Action lives on the Grocery/Lists view: pick a `ShoppingTemplate` (default
  to the primary staples template if one exists) → its `TemplateItem`s are
  appended to the active `GroceryList` as `GroceryItem`s.
- Skip items already present (match on normalized name) so re-seeding an
  in-progress list doesn't create duplicates.
- Carry over `category`/`unit`/`quantity` from the template item.
- Related but distinct from *Auto-populated staples from purchase history*
  above: that one *suggests* staples from history; this one just *seeds* a
  list from an existing template on demand.

**Files to change**: `GroceryListView.swift`, `ShoppingViewModel.swift`
(or grocery VM), possibly `ShoppingTemplate` accessor for "primary" template.

### Server-side recipe backup
Weekly automated backup of the recipe Postgres database. Protects
against sync bugs, accidental deletions, and data corruption.

- `pg_dump` via Cloud Scheduler → Cloud Storage bucket.
- 4 rolling weekly backups (1 month retention).
- Lifecycle policy auto-deletes older backups.
- Manual restore script (`scripts/restore-db-backup.sh`).
- Consider: also export recipes as JSON for human-readable backup.

**Anomaly detection**: Before writing the new backup, compare record
count and file size against the previous week's backup. If either
changes by more than 20%, **fail the backup** and email an alert
(via `$RECIPIENT_EMAIL`). This catches sync bugs, runaway deletes,
or corruption before the good backup gets rotated out. The previous
week's backup is preserved untouched when the check fails.

### Imperial ↔ metric unit toggle on any recipe
Let the user flip a recipe's ingredient units between imperial and metric on
the recipe detail screen (a toggle/segmented control), without mutating the
stored recipe.

- Display-only conversion by default — the canonical stored `quantity`/`unit`
  stays as entered; the toggle is a view-layer transform. (Optionally persist a
  per-user "preferred units" setting so it defaults correctly everywhere.)
- Conversion table for common cooking units: volume (cup/tbsp/tsp/fl oz ↔
  ml/l), weight (oz/lb ↔ g/kg), temperature in instructions (°F ↔ °C).
- Round to sensible cooking precision (e.g. 240 ml, not 236.588 ml) — reuse /
  extend `RecipeDetailView.formatQuantityAsFraction` on the imperial side.
- Non-convertible units (e.g. "1 egg", "to taste", "clove") pass through
  unchanged.
- Consider a pure `UnitConverter` module in `SharedLogic/` (framework-free,
  Windows-testable) so it's covered by the Swift test suites and reusable by
  the web frontend.

**Files to change**: `RecipeDetailView.swift` (toggle + display), new
`SharedLogic/UnitConverter.swift` (+ TestFixtures suite), possibly
`SettingsView.swift` for a global default.

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
