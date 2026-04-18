# GM-16: Grocery Categorizer Investigation

## Status: IN PROGRESS (2026-04-18 night)

## Problem

The current `GroceryCategorizer.swift` has ~200 keywords across 11 categories. Common
staples like "chicken thighs", "garam masala", "fresh ginger", and "tomato sauce" fall
through to "Other" because:

1. Multi-word matching doesn't cover enough variants
2. Missing categories entirely: **Spices/Seasonings**, **Baking**
3. Single-word matching misses items with adjectives ("fresh ginger" — "ginger" IS in
   the list but "fresh" prefix + tokenization may cause issues)

### Specific failures from build 67 screenshots

| Item | Got | Expected |
|------|-----|----------|
| 16-Oz (450G) Tomato Sauce | Other | Dry & Canned |
| Chicken Thighs | Other | Meat |
| Fresh Ginger | Other | Produce |
| Fresh Parsley, Mint, Or Cilantro | Other | Produce |
| Garam Masala | Other | Spices |
| Ground Cumin | Other | Spices |
| Chili Powder | Other | Spices |
| Cloves Garlic Minced | Other | Produce |
| Granulated Sugar Or Honey | Other | Baking/Dry & Canned |

## Current architecture

`SharedLogic/GroceryCategorizer.swift` — pure Swift, no external deps:
1. Multi-word exact matches (highest priority)
2. Compound overrides ("broth", "stock" → Dry & Canned)
3. Suffix matching ("berries" → Produce)
4. Single-word exact matching with plural normalization

~200 keywords, 11 categories: Produce, Dairy, Meat, Bakery, Dry & Canned, Frozen,
Snacks, Beverages, Condiments, Household, Other.

## Investigation areas

### 1. Why did the screenshot items fail?

Need to trace each item through the categorizer to understand the failure mode.
Some look like they SHOULD match ("ginger" is in Produce, "chicken" is in Meat).
Hypothesis: compound overrides are intercepting — "powder" is in dryCannedOverrides,
so "chili powder" → Dry & Canned override. But "chicken thighs" should work...

### 2. Missing categories

- **Spices/Seasonings**: garam masala, cumin, turmeric, paprika, cinnamon, etc.
  Currently these are under "Condiments" but users expect a separate Spices section.
- **Baking**: flour, sugar, baking soda/powder, vanilla extract, cocoa powder.
  Currently scattered between Dry & Canned and Condiments.

### 3. External data sources for comprehensive grocery taxonomy

Research needed:
- Grocery store APIs (Coles, Woolworths, Kroger/Fred Meyer, Safeway)
- Open data sets (USDA, Open Food Facts categories)
- Existing open-source grocery categorizers
- App Store competitors — what categories do they use?

### 4. Architecture options

- A: Expand current keyword list (500+ items)
- B: Use a structured taxonomy JSON file loaded at runtime
- C: Use an external API for categorization
- D: ML-based text classifier (CoreML)
- E: Hybrid: large keyword list + fuzzy matching for unknown items

---

## Checkpoint 1: Failure trace analysis (COMPLETE)

### Surprise: most items DON'T actually fail in code

Tracing each item through the matching pipeline reveals that **only 3 of 9 items
truly fail**. The others match correctly in the categorizer — the "Other" display
in the screenshot may be a UI-layer or import-layer issue (items may arrive with
different string formatting than what the categorizer sees).

| Item | Expected | Actual (traced) | Failure Point |
|------|----------|-----------------|---------------|
| 16-Oz (450G) Tomato Sauce | Dry & Canned | **Dry & Canned** | Correct — `"tomato sauce"` multi-word match |
| Chicken Thighs | Meat | **Meat** | Correct — `"chicken thigh"` substring match |
| Fresh Ginger | Produce | **Produce** | Correct — `"ginger"` exact word match |
| Fresh Parsley, Mint, Or Cilantro | Produce | **Produce** | Correct — `"fresh parsley"` multi-word match |
| **Garam Masala** | Spices | **Other** | Neither token in any list; no Spices category |
| **Ground Cumin** | Spices | **Condiments** | `"cumin"` hits Condiments; no Spices category |
| **Chili Powder** | Spices | **Dry & Canned** | `"powder"` compound override fires first |
| **Cloves Garlic Minced** | Produce | **Condiments** | `"cloves"→"clove"` hits Condiments before `"garlic"` hits Produce |
| Granulated Sugar Or Honey | Dry & Canned | **Dry & Canned** | Correct — `"sugar"` exact word match |

### Key finding: the import path may not be calling categorizeGroceryItem()

If "Chicken Thighs" shows as "Other" in the UI but the categorizer correctly returns
"Meat", the problem is upstream — the share extension import path may be setting a
default category or the category isn't being passed through. Need to check:
- `PendingImportService.confirmImport()` — does it call `categorizeGroceryItem()`?
- `GenerateGroceryListView` — does it categorize imported recipe ingredients?
- The shopping list in the screenshot may have items added without categorization.

**TODO: trace the import→shopping list category assignment path.**

### Root causes (for the 3 real categorizer failures)

**1. No "Spices" category exists.** Spice words are scattered:
- Condiments: cumin, paprika, turmeric, cinnamon, nutmeg, clove, allspice, cardamom,
  coriander, cayenne, chili, curry
- These should be a separate "Spices" aisle section

**2. `"powder"` compound override is too aggressive (line 228).** It was meant to catch
`"baking powder"` and `"powdered sugar"`, but it intercepts ALL items with "powder":
chili powder, garlic powder, onion powder, curry powder, cocoa powder — all spices/baking.

**3. Token order matters in matchExactWord.** `"cloves garlic minced"` processes
left-to-right: `"cloves"→"clove"` hits Condiments before `"garlic"` can hit Produce.
Fix: Produce should take priority over Condiments, or "garlic" as a food word should
outweigh "clove" as a spice word.

### Import path verification

The import path DOES call `categorizeGroceryItem()`:
- `PendingImportService.confirmImport()` line 90: `ingredient.category = categorizeGroceryItem(ingredient.name)`
- `GenerateGroceryListView.generate()` line 110-111: uses stored category or falls back

All models default `category = "Other"`. If the trace says items should categorize correctly
but the screenshot shows "Other", the items may have been added via a path that skips
categorization (manual add?), or the ingredient strings at runtime differ from what we traced.

**Action needed:** Add DebugLog to `categorizeGroceryItem()` for runtime evidence.

### Immediate fixes (no external data needed)

1. Add "Spices" category, move spice words out of Condiments
2. Remove "powder" from dryCannedOverrides, add specific multi-word entries instead:
   "baking powder" → Baking, "powdered sugar" → Baking
3. Add food-word priority: if any token matches Produce or Meat, that should win over
   Condiments/Spices (since "5 cloves garlic" is garlic, not cloves-the-spice)
4. Consider adding "Baking" category: flour, sugar, baking soda, baking powder,
   vanilla extract, cocoa powder, yeast, etc.

---

## Checkpoint 2: External data source research (COMPLETE)

### Best sources for offline iOS embedding

| Source | Aisle Granularity | Item Count | License | Embed Size | Effort |
|--------|-------------------|------------|---------|------------|--------|
| **Instacart 2017 dataset** | High (134 aisles, 21 depts) | 50,000 products | Non-commercial (check ToS) | ~2MB CSV | Low |
| **Spoonacular API** | High (~25 aisles) | 2,600 ingredients | Extract once via free API | <100KB | Medium |
| **Google Shopping taxonomy** | Food-type (not aisles) | 6,000+ categories | Free | ~50KB food subset | Low |
| **Open Food Facts** | Food-type (not aisles) | Thousands of nodes | ODbL (open) | ~2MB | Medium |
| **GroceryGenius** | Medium | ~130 items | Open source | <10KB | Very Low |
| **KitchenOwl** | Medium | Seed data | Open source | Small | Low |
| Kroger API | Store-specific | Large | ToS prohibits embedding | N/A | N/A |
| Woolworths API | Store-specific | Large | ToS prohibits embedding | N/A | N/A |
| USDA FoodData | No aisle data | 500k | Public domain | 300MB+ | High |
| GroceryDB (Barabasi) | Retailer categories | 50k | Academic | ~10MB | Medium |

### Key findings

**Retailer APIs (Kroger, Woolworths, Coles):** All gate-keep behind registration and
ToS prohibits embedding/redistributing product data. Not viable for offline use.

**Instacart 2017 dataset (Kaggle):** Best single source. 50,000 product names mapped to
134 aisles in 21 departments. Departments: alcohol, babies, bakery, beverages, breakfast,
bulk, canned goods, dairy eggs, deli, dry goods pasta, frozen, household, international,
meat seafood, missing, other, pantry, personal care, pets, produce, snacks.
The 134 aisles include fine-grained subdivisions like "specialty cheeses", "marinades
meat preparation", "pasta sauce", etc. CSV format, ~2MB total. Non-commercial license
needs ToS review.

**Spoonacular API:** The go-to for ingredient→aisle mapping. ~2,600 ingredients with
aisle fields like "Baking", "Spices and Seasonings", "Produce", "Canned and Jarred".
Free tier: 150 requests/day. One-time extraction of all ingredients would produce a
static JSON lookup table (<100KB). The aisle taxonomy itself (category names) is not
copyrightable — only the specific data mapping.

**Google Shopping taxonomy:** Free downloadable .txt file. 6,000+ categories with deep
food hierarchy (e.g., "Food, Beverages & Tobacco > Beverages > Tea > Green Tea").
Not store-aisle-oriented but excellent for food type classification. Small file (~500KB).

**Open Food Facts:** ODbL-licensed (can embed with attribution). Hierarchical food
taxonomy, not store aisles. Useful as a supplementary layer mapping food science
categories to our aisle categories.

**Open-source apps:**
- **GroceryGenius** (Android): `default_products.json` with ~130 items + categories
- **KitchenOwl** (Flutter): MIT/AGPL, seed JSON with item→category mappings
- **Aislander** (Flask): Confirms Spoonacular is the standard API for ingredient→aisle

### Recommended build strategy

**Phase 1 — Immediate fixes (no external data):**
- Add "Spices" category, fix compound override bugs, add category priority
- Expand keyword list to 500+ from domain knowledge
- This alone would fix the build 67 screenshot issues

**Phase 2 — Spoonacular extraction (one-time, ~100KB result):**
- Use free API tier to query all ~2,600 ingredients
- Extract ingredient→aisle mappings as a static JSON file
- Adopt their ~25 aisle taxonomy (or map to our categories)
- Result: comprehensive ingredient lookup, fully offline

**Phase 3 — Instacart 2017 keyword mining (~2MB):**
- Download from Kaggle, join products.csv + aisles.csv + departments.csv
- Extract product name keywords → department/aisle mappings
- 50,000 product names = massive keyword expansion
- Map 21 Instacart departments → our category scheme

**Phase 4 — Google taxonomy for food type classification:**
- Download taxonomy.en-US.txt, extract food subtree
- Use as fallback: if keyword match fails, check if item name contains
  any node from the food taxonomy hierarchy
- Bridges food science names to store navigation

### Category scheme recommendation

Merge insights from Spoonacular + Instacart into a unified scheme:

| Our Current | Proposed | Notes |
|-------------|----------|-------|
| Produce | Produce | Keep |
| Dairy | Dairy & Eggs | Rename to match convention |
| Meat | Meat & Seafood | Rename to match convention |
| Bakery | Bakery | Keep |
| Dry & Canned | Pantry / Dry Goods | Consider split |
| Frozen | Frozen | Keep |
| Snacks | Snacks | Keep |
| Beverages | Beverages | Keep |
| Condiments | Condiments & Sauces | Rename |
| Household | Household | Keep |
| — | **Spices & Seasonings** | NEW — split from Condiments |
| — | **Baking** | NEW — split from Dry & Canned |
| — | **Deli** | NEW — from Instacart |
| — | **International** | NEW — from Instacart |
| — | **Breakfast** | MAYBE — cereal, oatmeal, syrup |
| Other | Other | Keep as fallback |

---

## Checkpoint 3: Recommended implementation plan

### Phase 1: Quick fixes to GroceryCategorizer.swift (do first)

1. **Add "Spices" category** with words currently in Condiments:
   cumin, paprika, turmeric, cinnamon, nutmeg, clove, allspice, cardamom,
   coriander, cayenne, chili, curry, oregano, thyme, rosemary, sage, dill,
   basil, parsley, mint, bay leaf, saffron, fennel seed, mustard seed,
   garam masala, masala, five spice, za'atar, sumac, etc.

2. **Add "Baking" category:**
   flour, sugar, baking soda, baking powder, vanilla extract, cocoa powder,
   yeast, gelatin, pectin, cornstarch, cream of tartar, food coloring,
   sprinkles, powdered sugar, brown sugar, confectioner's sugar, etc.

3. **Fix compound overrides:**
   - Remove "powder" from dryCannedOverrides
   - Remove "seasoning" from dryCannedOverrides
   - Add specific multi-word entries: "baking powder" → Baking,
     "powdered sugar" → Baking, "garlic powder" → Spices, etc.

4. **Add category priority system:**
   Produce > Meat > Dairy > ... > Spices > Condiments
   If multiple tokens match different categories, highest-priority wins.
   This fixes "cloves garlic" → Produce (garlic outranks clove).

5. **Move herb words from Produce to Spices** (or keep in both with priority):
   Fresh herbs at the store are in Produce, dried herbs are in Spices.
   Decision: if "fresh" or "dried" modifier present, route accordingly.
   Default: Produce (buying fresh is more common for cooking).

### Phase 2: Spoonacular data extraction

- Create a one-time script that queries Spoonacular's ingredient database
- Extract all ingredient→aisle pairs
- Save as `SharedLogic/GroceryAisles.json` or expand the Swift keyword list
- This gives us authoritative aisle assignments for 2,600 common ingredients

### Phase 3: Instacart keyword mining

- Download Instacart 2017 dataset from Kaggle
- Script to extract unique product name tokens → department mappings
- Use to expand keyword lists, especially for branded/compound items
- Validate against our category scheme

### Tests

- Expand `TestFixtures/TestGroceryCategorizer.swift` with the screenshot failures
- Add regression tests for compound override false positives
- Add tests for the new Spices and Baking categories
- Target: every item from the build 67 screenshot categorizes correctly
