# Schema Review — Recipe App

**Date:** 2026-04-13
**Status:** Proposal — awaiting review before implementation
**Context:** Before starting Phase 2D/2E (YOLO + confirmation UI), reviewing the
data model against real-world recipe apps and Google's structured data spec to
avoid painting into corners.

**Design principle:** Prefer free-text strings and optional fields over hard FK
constraints. The schema should make it *easy* to enter data, not force the user
through a normalized gauntlet. Hard FKs between tables (e.g., a master
`IngredientType` table) would make ad-hoc data entry painful — avoid that.

---

## 1. Current Model Summary

### Recipe + Ingredient (cooking domain)

```
Recipe
  id, name, summary, instructions (text blob), prepTimeMinutes, cookTimeMinutes,
  servings, imageData (binary), createdAt, updatedAt
  → has many Ingredient (cascade)

Ingredient
  id, name, quantity (Double), unit (String), category, recipe (back-ref)
```

### GroceryList + GroceryItem (shopping domain)

```
GroceryList
  id, name, createdAt, archivedAt?
  → has many GroceryItem (cascade)

GroceryItem
  id, name, quantity (Double), unit (String), category, isChecked
```

### ShoppingTemplate + TemplateItem

```
ShoppingTemplate
  id, name, sortOrder, createdAt
  → has many TemplateItem (cascade)

TemplateItem
  id, name, quantity (Double), unit (String), category, sortOrder
```

### PantryItemModel (pure Swift, not yet in SwiftData)

```
PantryItemModel
  id, name, category, quantity (Int), unit, confidence, detectedAt
```

---

## 2. Recipe Model — Proposed Additions

Fields compared against Google schema.org/Recipe structured data and common
patterns in Paprika, Mela, Crouton, and open-source recipe apps.

### 2A. New fields on Recipe

| Field | Type | Default | Why |
|---|---|---|---|
| `cuisine` | String | `""` | Filter "Italian", "Mexican". Free text, not an FK to a lookup table. |
| `course` | String | `""` | "Breakfast", "Dinner", "Dessert", "Snack". Free text. Google calls this `recipeCategory`. |
| `tags` | String | `""` | Comma-separated free text: `"quick, weeknight, kid-friendly"`. Avoids a join table. Searchable via `CONTAINS`. |
| `sourceURL` | String | `""` | Where the recipe came from (website, cookbook name). |
| `difficulty` | String | `""` | "Easy", "Medium", "Hard". Free text, not an enum — keeps it flexible. |
| `isFavorite` | Bool | `false` | Quick pin/star for the home screen concept. User-scoped — works because recipes live in the private CloudKit zone (not shared). If a multi-user backend is added in Phase 6+, migrate to a `UserFavorite` join table at that point. |

**Why free-text strings instead of normalized tables:** A `cuisine` FK to a
`Cuisines` table means the user can't type "Korean-Mexican fusion" without first
adding that to the lookup table. Same for tags — a join table
(`recipe_tags` ↔ `tags`) is the "correct" relational design but makes ad-hoc
tagging painful. Comma-separated string is good enough for a personal recipe app
with hundreds of recipes, not thousands.

**Why NOT `tags` as a join table:** CloudKit doesn't support many-to-many
relationships natively. SwiftData can model it, but CloudKit sync would need a
bridging record type. A comma-separated string syncs trivially.

### 2B. Structured instructions (deferred — flag only)

Google's spec wants `recipeInstructions` as an ordered array of `HowToStep`.
This would require a new `InstructionStep` model:

```
InstructionStep
  id, text, stepNumber, recipe (back-ref)
```

**Recommendation: defer.** The current text blob works for v1. Structured steps
would enable step-by-step cooking mode (tap to advance, voice "next step"), but
that's a Phase 5+ feature. When the time comes, migration is straightforward —
split on newlines/numbered lines to seed the new model.

The text blob does NOT block any near-term work (2D, 2E, shopping, sharing).

### 2C. Image storage (flag for later)

`imageData: Data?` stores binary in SwiftData/CloudKit. This works for now but
won't scale well with many high-res recipe photos. Future migration path:
store images in CloudKit asset fields (CKAsset) which handle large binary
data more efficiently than record fields. No action needed now — just noting
for Phase 4 (SQLiteData migration) when persistence is being reworked anyway.

---

## 3. Ingredient Model — Proposed Additions

### 3A. New fields on Ingredient

| Field | Type | Default | Why |
|---|---|---|---|
| `displayOrder` | Int | `0` | Preserve ingredient order as entered. Without this, ingredients display in arbitrary order after CloudKit sync. |
| `notes` | String | `""` | Prep notes: "finely diced", "room temperature", "divided". Keeps `name` clean for shopping list matching. |

### 3B. Keep quantity + unit + name split

The research confirms our current structured split (quantity/unit/name) is the
right call for a user-entered app. The over-normalization risk only applies when
auto-importing free-text recipes (Phase 3 LLM parsing), and even then the LLM
returns structured JSON.

The `notes` field resolves the main pain point — "1 lb chicken breast, pounded
thin" becomes `quantity=1, unit="lb", name="chicken breast", notes="pounded thin"`
instead of cramming "pounded thin" into the name.

---

## 4. Unit Picker — The Big Change

### The Problem

Current `commonUnits`:
```
"", "tsp", "tbsp", "cup", "oz", "fl oz", "lb", "g", "kg", "ml", "l",
"pinch", "dash", "whole", "clove", "slice", "piece", "bunch", "can",
"bag", "box", "bottle", "jar", "packet"
```

This is a single list shared between recipe editing and shopping list entry.
But these are two fundamentally different contexts:

**Recipe context:** Precision matters. "2 tsp vanilla extract" is meaningful.
The current list is mostly fine here, but missing a few:
- `"large"`, `"medium"`, `"small"` (for eggs, onions, potatoes)
- `"head"` (garlic, lettuce, cauliflower)
- `"stalk"` (celery)
- `"sprig"` (rosemary, thyme)
- `"stick"` (butter, cinnamon)

**Shopping context:** Purchase quantities matter. You never buy "1 tsp" of
something at a grocery store. Missing:
- `"carton"`, `"dozen"`, `"loaf"`, `"container"`, `"pack"`, `"case"`
- And honestly, most shopping items don't need a unit at all — "Eggs",
  "Milk", "Bread" are self-explanatory on a shopping list.

### Proposed Solution: Two Unit Lists + Free Text Default for Shopping

**Option A (recommended): Context-aware picker**

```swift
/// Units shown when editing recipe ingredients
let recipeUnits = [
    "", "tsp", "tbsp", "cup", "oz", "fl oz", "lb", "g", "kg", "ml", "l",
    "pinch", "dash", "whole", "large", "medium", "small",
    "clove", "slice", "piece", "bunch", "head", "stalk", "sprig", "stick",
    "can", "jar", "bottle",
]

/// Units shown when adding shopping list items
let shoppingUnits = [
    "", "lb", "oz", "g", "kg",                          // weight
    "gal", "qt", "pt", "fl oz", "l", "ml",              // volume
    "dozen", "pack", "bag", "box", "can", "jar",        // containers
    "bottle", "carton", "container", "loaf", "bunch",    // containers cont.
    "head", "case",                                      // bulk
]
```

The `UnitPicker` already has an "Other…" escape hatch for custom text.
The change is just which list it shows based on context.

**Option B: Free text for shopping, picker for recipes**

Shopping list items get a plain `TextField` for unit (no dropdown at all).
Recipe ingredients keep the picker. This is the simplest approach and matches
how people actually write shopping lists — "Eggs (1 dozen)", "Milk (1 gal)",
or just "Eggs" with no unit.

**Recommendation:** Start with Option A. The picker is still useful for shopping
(weight/container units are common), but showing cooking-precision units like
`tsp` and `pinch` in a shopping context is confusing. If testing reveals that
people mostly type custom units for shopping, downgrade to Option B.

### Storage: No Schema Change Needed

`unit` is already a free-text `String` on all models. The picker is purely a UI
concern — different lists shown in different contexts. The underlying data model
doesn't change at all.

---

## 5. Shopping → Recipe Traceability

### The Problem

When "Add from Recipe" creates `GroceryItem`s from a recipe's `Ingredient`s,
there's no record of where the shopping item came from. This blocks:
- "Which recipe needs this item?" (useful while shopping)
- "Don't re-add if already on list from another recipe"
- Smart quantity merging (two recipes both need chicken → one shopping entry)

### Proposed Solution: Soft String References (not FKs)

Add two optional string fields to `GroceryItem`:

| Field | Type | Default | Example |
|---|---|---|---|
| `sourceRecipeName` | String | `""` | `"Chicken Tikka Masala"` |
| `sourceRecipeId` | String | `""` | `"<uuid>"` (stored as string, not FK) |

**Why strings, not FKs:**
- Deleting a recipe shouldn't cascade-delete shopping items
- CloudKit doesn't enforce cross-record-type FKs anyway
- A string reference is enough for display ("from Chicken Tikka Masala") and
  dedup logic (group by sourceRecipeId)
- If the recipe is deleted, the shopping item just shows a stale name — harmless

**Why not a proper relationship:** SwiftData `@Relationship` between
`GroceryItem` and `Recipe` would create a hard coupling. Deleting a recipe
would either cascade-delete shopping items (bad) or require `.nullify` delete
rule and careful lifecycle management. Not worth the complexity for a display hint.

### Quantity Merging Logic

When adding recipe ingredients to a shopping list:

1. Check if an item with the same `name` (case-insensitive) already exists
2. If yes and units are compatible → merge quantities
3. If yes but units differ → add as separate line (user can merge manually)
4. If no → add new item
5. Set `sourceRecipeName` / `sourceRecipeId` on new items

This is pure business logic — no schema change beyond the two new fields.

---

## 6. PantryItem — SwiftData Model

`PantryItemModel` exists as a pure Swift struct in `Models/PantryItemMapper.swift`.
For 2E (confirmation UI) it needs a SwiftData counterpart.

### Proposed SwiftData Model

```swift
@Model
final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = "Other"
    var quantity: Int = 1
    var unit: String = ""
    var confidence: Double = 0
    var detectionMethod: String = ""   // "barcode", "ocr", "yolo", "manual"
    var scannedAt: Date = Date()
    var expiresAt: Date? = nil         // future: expiration tracking

    init(
        name: String = "",
        category: String = "Other",
        quantity: Int = 1,
        unit: String = "",
        confidence: Double = 0,
        detectionMethod: String = "",
    ) { ... }
}
```

This matches the `PantryItemModel` from `ARCHITECTURE_PROPOSAL.md` with
`detectionMethod` added (was listed there as `detectionMethod: String`).
No FK to Recipe or GroceryItem — pantry items are their own thing.

---

## 7. Summary of All Proposed Changes

### New fields on existing models

| Model | Field | Type | Default | Migration Risk |
|---|---|---|---|---|
| **Recipe** | `cuisine` | String | `""` | None — additive |
| **Recipe** | `course` | String | `""` | None — additive |
| **Recipe** | `tags` | String | `""` | None — additive |
| **Recipe** | `sourceURL` | String | `""` | None — additive |
| **Recipe** | `difficulty` | String | `""` | None — additive |
| **Recipe** | `isFavorite` | Bool | `false` | None — additive |
| **Ingredient** | `displayOrder` | Int | `0` | None — additive |
| **Ingredient** | `notes` | String | `""` | None — additive |
| **GroceryItem** | `sourceRecipeName` | String | `""` | None — additive |
| **GroceryItem** | `sourceRecipeId` | String | `""` | None — additive |

### New model

| Model | Purpose |
|---|---|
| **PantryItem** | SwiftData version of PantryItemModel for 2E confirmation UI |

### UI changes

| Change | Scope |
|---|---|
| Split `commonUnits` into `recipeUnits` + `shoppingUnits` | `UnitPicker.swift` + callers pass context |
| Add missing units to both lists | Same file |

### NOT doing

| Idea | Why not |
|---|---|
| `InstructionStep` model (structured instructions) | Defer to Phase 5+ — text blob works for v1 |
| `Tag` join table | CloudKit many-to-many is painful; comma-separated string is fine |
| Master `IngredientType` table with FK | Makes data entry rigid — free text is better |
| Hard FK from GroceryItem → Recipe | Cascade problems, CloudKit doesn't enforce it |
| Separate `ShoppingUnit` enum/table | Unit is already free text; just change the picker UI |
| Nutrition fields | Defer to Phase 3+ when Gemini can auto-extract them |

---

## 8. Implementation Order

If approved, implement in this order (each is independently committable):

1. **Recipe fields** — add cuisine, course, tags, sourceURL, difficulty, isFavorite
   to both `Models/Recipe.swift` and `RecipeApp/.../Models/Recipe.swift`. Update
   `RecipeEditView` to show new fields. Update tests.

2. **Ingredient fields** — add displayOrder and notes. Update recipe edit form
   to show notes field and preserve order. Update tests.

3. **Unit picker split** — create `recipeUnits` / `shoppingUnits` arrays,
   add context parameter to `UnitPicker`. Update all callers.

4. **GroceryItem traceability** — add sourceRecipeName/sourceRecipeId. Update
   "Add from Recipe" flow to populate them. Update tests.

5. **PantryItem SwiftData model** — new model for 2E. This is part of the
   2D/2E work itself.

Steps 1–4 are independent of 2D/2E and can be done first as a foundation.
Step 5 happens naturally during 2E implementation.

---

## 9. Schema vs Google Structured Data

For future interop (export recipes as JSON-LD, share via web), here's how our
proposed schema maps to Google's spec:

| Google field | Our field | Notes |
|---|---|---|
| `name` (required) | `name` | Direct match |
| `image` (required) | `imageData` | We store binary; they want URL. Convert on export. |
| `description` | `summary` | Direct match |
| `prepTime` | `prepTimeMinutes` | Convert to ISO 8601 on export |
| `cookTime` | `cookTimeMinutes` | Convert to ISO 8601 on export |
| `totalTime` | computed | Already have `totalTimeMinutes` |
| `recipeYield` | `servings` | They accept text; we store int. Fine. |
| `recipeIngredient` | `ingredients[]` | They want free text; we reconstruct: `"\(qty) \(unit) \(name)"` |
| `recipeInstructions` | `instructions` | They want HowToStep[]; we'd split on newlines for export |
| `recipeCuisine` | `cuisine` | **NEW** — direct match |
| `recipeCategory` | `course` | **NEW** — direct match |
| `keywords` | `tags` | **NEW** — direct match (comma-separated) |
| `author` | — | Not adding — single-user app |
| `nutrition` | — | Deferred to Phase 3+ |
| `aggregateRating` | — | Not adding — single-user app |

We're not trying to be a schema.org-compliant recipe publisher. The goal is just
to have the right *slots* so that if we ever want to export or integrate, the
data is there. All the new fields are optional free-text strings with empty
defaults — they cost nothing if unused.
