# Server-Canonical Sync — Execution Plan

## Goal

Make the server the single source of truth for recipes. iOS pushes local recipes
on first login, then both iOS and web read/write through the server API. CloudKit
remains as a local cache for offline access but is no longer authoritative.

---

## What Has Been Implemented (Phase 1 + Partial Phase 2)

### Phase 1: Server-Side Soft Delete + Lightweight List ✅

**Files changed:**

| File | Change |
|------|--------|
| `server/models/recipe.py` | Added `deleted_at` nullable DateTime column |
| `server/routers/recipes.py` | Rewrote all endpoints — see details below |
| `server/schemas/recipe.py` | Added `RecipeListItem` schema, `deleted_at` to `RecipeResponse` |
| `database/init.sql` | Added `deleted_at TIMESTAMP WITH TIME ZONE` to recipes table |
| `server/tests/test_recipes.py` | Added 7 new tests (22 total recipe tests, 60 total server) |

**Endpoint changes:**

| Endpoint | Before | After |
|----------|--------|-------|
| `GET /recipes/` | Returns all recipes | Filters out `deleted_at IS NOT NULL` |
| `GET /recipes/?fields=id,updated_at` | N/A | Returns lightweight `{id, updated_at}` list |
| `GET /recipes/{id}` | Returns any recipe | 404 if soft-deleted |
| `PUT /recipes/{id}` | Updates any recipe | 404 if soft-deleted |
| `PATCH /recipes/{id}` | Patches any recipe | 404 if soft-deleted |
| `DELETE /recipes/{id}` | Hard deletes row | Sets `deleted_at = now()` (soft delete) |
| `GET /recipes/deleted` | N/A | **New** — admin: lists soft-deleted recipes |
| `POST /recipes/deleted/{id}/restore` | N/A | **New** — admin: restores soft-deleted recipe |

**New tests:**
- `test_soft_delete_hides_from_list` — deleted recipe excluded from GET /recipes/
- `test_soft_delete_returns_404_on_get` — GET by id returns 404 after delete
- `test_deleted_recipes_list` — deleted recipe appears in /recipes/deleted
- `test_restore_deleted_recipe` — restore sets deleted_at=null, GET works again
- `test_lightweight_list` — ?fields=id,updated_at returns only those 2 fields
- `test_lightweight_list_excludes_deleted` — lightweight list filters soft-deleted
- `test_soft_delete_blocks_update` — PUT on deleted recipe returns 404

**All 60 server tests pass.**

### Phase 2: iOS Model + APIClient (Partial) 🔧

**Files changed:**

| File | Change |
|------|--------|
| `RecipeApp/Models/Recipe.swift` | Added 6 sync metadata fields |
| `RecipeApp/Services/APIClient.swift` | Full rewrite — production URL, all CRUD, retry, DTOs |

**Recipe.swift — new sync fields:**
```swift
var serverId: String?           // Server UUID, nil = never synced
var needsSync: Bool = false     // Local changes not yet pushed
var lastSyncedAt: Date?         // Last successful sync timestamp
var locallyDeleted: Bool = false // Pending server-side deletion
var deletedAt: Date?            // When locally deleted (30-day retention)
var isConflictedCopy: Bool = false // Created by conflict resolution
```

All fields are optional/defaulted — no destructive SwiftData migration needed.
Existing recipes get `serverId = nil`, `needsSync = false`, etc.

**APIClient.swift — new capabilities:**
- Production base URL (`#if DEBUG` toggle for localhost vs Cloud Run)
- `fetchRecipeList()` → lightweight `[RecipeListItemDTO]`
- `fetchRecipe(id:)` → single recipe by UUID
- `updateRecipe(id:, _:)` → PUT
- `deleteRecipe(id:)` → DELETE
- Retry with exponential backoff (max 3 attempts, only for 429/5xx)
- `APIError` enum with `unauthorized`, `notFound`, `serverError(code)`
- `User-Agent: RecipeApp-iOS/0.3.0` header for server audit
- Full DTOs with `CodingKeys` for snake_case ↔ camelCase
- ISO8601 date decoding with fractional seconds fallback

---

## Wire Format Rules

These rules apply to ALL time fields across the entire stack. They must
be verified before any wire format change (new fields, schema migrations,
new endpoints).

1. **All timestamps are UTC.** The server stores `DateTime(timezone=True)`
   with `datetime.now(timezone.utc)`. The wire format is ISO8601 with a
   `Z` or `+00:00` suffix. iOS encodes/decodes with `ISO8601DateFormatter`.
   No local time zones ever appear in stored data or API payloads.

2. **Local time display is the view's responsibility.** Any human-facing
   timestamp (e.g., "Last synced 5 min ago", "Created Mar 12") must be
   converted from UTC to the viewer's local time zone in the SwiftUI view
   layer, not in the model or DTO.

3. **Comparison uses UTC.** Sync decisions (`server.updated_at >
   local.lastSyncedAt`) compare UTC values directly. Never convert to
   local time before comparing.

**Current state:** The server is fully UTC (`datetime.now(timezone.utc)`
on all columns). The iOS APIClient uses `.iso8601` encoding/decoding.
This is correct — do not change it.

---

## Data Flow Scenarios

**When does `sync()` run?** Two triggers:
1. **App foreground** — when the scene enters `.active` (app launch or
   returning from background), if the user is authenticated.
2. **Pull-to-refresh** — user pulls down the recipe list.

`sync()` is the single entry point. It calls `pullChanges()` then
`pushChanges()` then `processDeletions()` in sequence. Individual recipe
creates/edits/deletes never talk to the server directly — they just set
flags (`needsSync`, `locallyDeleted`) and let the next `sync()` handle it.

### Scenario 1: Upload — New Local Recipe → Server

**Trigger:** `SyncService.sync()` → `pushChanges()` finds a recipe with
`serverId == nil` and `needsSync == true`. This happens during a regular
sync cycle (app foreground or pull-to-refresh), NOT at recipe creation time.
The user creates the recipe normally; it's saved to SwiftData with
`needsSync = true`. The next `sync()` call picks it up and uploads it.

A recipe created on iOS that has never been synced (`serverId == nil`).

```
SwiftData Recipe              RecipeDTO (JSON)               Server (Postgres)
─────────────────             ───────────────                ─────────────────
1. Read @Model fields
   name, summary, ...
   ingredients relationship
        │
        ▼
2. Map to RecipeDTO
   - recipe.name → dto.name
   - recipe.summary → dto.summary
   - recipe.instructions → dto.instructions
   - recipe.prepTimeMinutes → dto.prepTimeMinutes (→ "prep_time_minutes" via CodingKeys)
   - recipe.cookTimeMinutes → dto.cookTimeMinutes (→ "cook_time_minutes")
   - recipe.servings → dto.servings
   - recipe.cuisine → dto.cuisine
   - recipe.course → dto.course
   - recipe.tags → dto.tags
   - recipe.sourceURL → dto.sourceURL (→ "source_url")
   - recipe.difficulty → dto.difficulty
   - recipe.isFavorite → dto.isFavorite (→ "is_favorite")
   - recipe.isPublished → dto.isPublished (→ "is_published")
   - dto.id = nil (server assigns)
   - dto.createdAt = nil (server assigns)
   - dto.updatedAt = nil (server assigns)

3. Map ingredients:
   for each Ingredient in recipe.ingredients:
   - ingredient.name → ing.name
   - ingredient.quantity → ing.quantity
   - ingredient.unit → ing.unit
   - ingredient.category → ing.category
   - ingredient.displayOrder → ing.displayOrder (→ "display_order")
   - ingredient.notes → ing.notes
   - ing.id = nil (server assigns)

4. imageData: SKIPPED
   imageData is not included in RecipeDTO.
   Binary image data is not synced in this phase.
   (Future: separate PUT /recipes/{id}/image endpoint)

5. Encode → POST /api/v1/recipes
   JSONEncoder.apiEncoder encodes RecipeDTO
   CodingKeys map camelCase → snake_case
   Authorization: Bearer <JWT>
   Content-Type: application/json
        │
        ▼
6. Server creates row                           ──→  INSERT INTO recipes (...)
   Server creates ingredient rows               ──→  INSERT INTO ingredients (...)
   Server assigns UUIDs + timestamps
   Returns RecipeResponse JSON
        │
        ▼
7. Decode response → RecipeDTO
   Extract server-assigned id
        │
        ▼
8. Update local SwiftData Recipe:
   recipe.serverId = response.id (as String)
   recipe.lastSyncedAt = Date()
   recipe.needsSync = false
```

**On failure at step 5–6:**
- `needsSync` remains `true`
- Recipe will retry on next `sync()` call
- If write failures accumulate, show "Could not sync recipes" warning

### Scenario 2: Upload — Edited Local Recipe → Server

**Trigger:** Same as Scenario 1 — `SyncService.sync()` → `pushChanges()`
finds a recipe with `serverId != nil` and `needsSync == true`. The user
edited the recipe in RecipeEditView, which set `needsSync = true` on save.
The next sync cycle pushes the update.

A recipe that already has a `serverId` and was edited locally (`needsSync == true`).

```
1. Same field mapping as Scenario 1 (steps 2–4)

2. Key difference: dto.id = UUID(recipe.serverId)
   This tells the server which recipe to update.

3. Encode → PUT /api/v1/recipes/{serverId}
   Full replacement — all fields sent, not a partial patch.
        │
        ▼
4. Server replaces all columns                  ──→  UPDATE recipes SET ... WHERE id = {serverId}
   Server deletes existing ingredients          ──→  DELETE FROM ingredients WHERE recipe_id = ...
   Server inserts new ingredients               ──→  INSERT INTO ingredients (...)
   Returns updated RecipeResponse
        │
        ▼
5. Update local SwiftData Recipe:
   recipe.lastSyncedAt = Date()
   recipe.needsSync = false
```

**Ingredient strategy: delete-all + re-insert (not diff).**
The server already uses this approach (`DELETE` all ingredients for recipe,
then re-insert). This is simpler than diffing and avoids orphan bugs.
The cost is trivial — recipes have ~5–20 ingredients.

### Scenario 3: Download — Server Recipe → Local (New)

**Trigger:** `SyncService.sync()` → `pullChanges()`. The sync polls
`GET /recipes?fields=id,updated_at` and compares IDs against local
SwiftData. When an ID appears on the server that has no local recipe with
a matching `serverId`, it's a new recipe — fetch it individually via
`GET /recipes/{id}`. This downloads **one recipe at a time**, not bulk.
Typical cause: someone created a recipe on the web frontend.

A recipe exists on the server but not locally (e.g., created on web).

```
Server (Postgres)              RecipeDTO (JSON)              SwiftData Recipe
─────────────────              ───────────────               ─────────────────
1. GET /api/v1/recipes/{id}
   Returns full RecipeResponse
        │
        ▼
2. Decode JSON → RecipeDTO
   CodingKeys map snake_case → camelCase
   ISO8601 date decoding (with fractional seconds fallback)
        │
        ▼
3. Create new SwiftData Recipe:
   let recipe = Recipe()
   recipe.name = dto.name
   recipe.summary = dto.summary
   recipe.instructions = dto.instructions
   recipe.prepTimeMinutes = dto.prepTimeMinutes
   recipe.cookTimeMinutes = dto.cookTimeMinutes
   recipe.servings = dto.servings
   recipe.cuisine = dto.cuisine
   recipe.course = dto.course
   recipe.tags = dto.tags
   recipe.sourceURL = dto.sourceURL
   recipe.difficulty = dto.difficulty
   recipe.isFavorite = dto.isFavorite
   recipe.isPublished = dto.isPublished
   recipe.createdAt = dto.createdAt
   recipe.updatedAt = dto.updatedAt

4. Create Ingredient objects:
   for each IngredientDTO in dto.ingredients:
     let ing = Ingredient()
     ing.name = ingDTO.name
     ing.quantity = ingDTO.quantity
     ing.unit = ingDTO.unit
     ing.category = ingDTO.category
     ing.displayOrder = ingDTO.displayOrder
     ing.notes = ingDTO.notes
   recipe.ingredients = [all new Ingredients]

5. Set sync metadata:
   recipe.serverId = dto.id (as String)
   recipe.lastSyncedAt = Date()
   recipe.needsSync = false
   recipe.imageData = nil  (not synced)

6. modelContext.insert(recipe)
```

### Scenario 4: Download — Server Recipe → Local (Update/Overwrite)

**Trigger:** `SyncService.sync()` → `pullChanges()`. Same poll as
Scenario 3, but the ID already exists locally (matched by `serverId`).
The server's `updated_at` is newer than the local `lastSyncedAt`, and the
local recipe has `needsSync == false` (no local edits pending). Typical
cause: someone edited the recipe on the web frontend.

A recipe exists both locally and on the server. Server version is newer
(`server.updated_at > local.lastSyncedAt`) and local has no pending changes
(`needsSync == false`).

```
1. GET /api/v1/recipes/{id} → decode RecipeDTO

2. Find existing local recipe by serverId

3. Overwrite all fields on existing recipe:
   recipe.name = dto.name
   recipe.summary = dto.summary
   ... (same mapping as Scenario 3, step 3)

4. Replace ingredients:
   - Delete all existing: for old in recipe.ingredients { modelContext.delete(old) }
   - Create new Ingredient objects from IngredientDTOs
   - recipe.ingredients = [new ingredients]

5. Update sync metadata:
   recipe.lastSyncedAt = Date()
   recipe.needsSync = false  (still false — no local edits)
```

**Why delete-all + re-insert for ingredients (not diff):**
Same reasoning as server-side. Diffing ingredient lists by name/quantity
is fragile (names change, quantities change, order changes). Delete + re-insert
is idempotent and correct. The SwiftData cascade delete rule handles cleanup.

### Scenario 5: Conflict — Both Sides Changed

**Trigger:** `SyncService.sync()` → `pullChanges()` detects a recipe where
BOTH conditions are true: `needsSync == true` (user edited on iOS) AND
server's `updated_at > lastSyncedAt` (someone edited on web too). Typical
cause: user edits a recipe on the phone while offline, and someone else
edits the same recipe on the web before the phone comes back online.

Local recipe has `needsSync == true` AND server's `updated_at > local.lastSyncedAt`.
Both sides edited since last sync.

```
1. Detect conflict during comparison step:
   local.needsSync == true  (edited locally)
   server.updated_at > local.lastSyncedAt  (edited on server)

2. Save local version as conflicted copy BEFORE overwriting:
   let copy = Recipe()
   copy.name = "\(recipe.name) (conflicted copy \(dateString))"
   copy.summary = recipe.summary
   copy.instructions = recipe.instructions
   ... (copy ALL fields from current local state)
   copy.ingredients = [copy of each ingredient]
   copy.isConflictedCopy = true
   copy.needsSync = true     ← will upload to server on next sync
   copy.serverId = nil        ← it's a new recipe
   modelContext.insert(copy)

3. Overwrite local recipe with server version:
   (Same as Scenario 4)

4. Show warning: "Could not sync recipes" is NOT the right message here.
   Instead show: "1 conflict resolved — check conflicted copies"
   (This is a different UI path from write errors.)
```

**Policy: server wins, local copy preserved.** The user can review the
conflicted copy, manually merge anything they want, and delete the copy.

### Scenario 6: Delete on iOS → Server

**Trigger:** Two steps. First, the user swipes to delete in RecipeListView
— this immediately sets `locallyDeleted = true` (recipe hidden from UI)
but does NOT call the server. Then, on the next `SyncService.sync()` →
`processDeletions()`, the service finds recipes with `locallyDeleted == true`
and pushes `DELETE /recipes/{serverId}` to the server.

User swipes to delete a recipe on iOS.

```
1. User swipes to delete in RecipeListView

2. Instead of modelContext.delete(recipe):
   recipe.locallyDeleted = true
   recipe.deletedAt = Date()
   Recipe immediately hidden from UI (filter locallyDeleted == false)

3. On next sync(), processDeletions():
   Find all recipes where locallyDeleted == true AND serverId != nil
   For each:
     DELETE /api/v1/recipes/{serverId}
     │
     ├─ 204 No Content → server soft-deleted → hard-delete local record
     │                    modelContext.delete(recipe)
     │
     ├─ 404 Not Found → already gone on server → hard-delete local record
     │
     └─ Network error → leave locallyDeleted = true, retry next sync

4. Recipes with locallyDeleted == true AND serverId == nil:
   These were never synced — just hard-delete immediately.
   modelContext.delete(recipe)
```

### Scenario 7: Delete on Web/Server → iOS

**Trigger:** `SyncService.sync()` → `pullChanges()`. The lightweight poll
returns the list of active server IDs. A local recipe has a `serverId` that
is NOT in that list — meaning it was deleted on the server side. The sync
service soft-deletes it locally. Typical cause: someone deleted the recipe
via the web frontend.

A recipe is deleted via the web frontend or directly on the server.

```
1. Web sends DELETE /api/v1/recipes/{id}
   Server sets deleted_at = now() (soft delete)

2. On next iOS sync:
   GET /recipes?fields=id,updated_at
   The deleted recipe is NOT in the returned list

3. SyncService compares server list against local recipes:
   Local recipe has serverId = X
   Server list does not contain id = X
   → Recipe was deleted on server

4. Soft-delete locally:
   recipe.locallyDeleted = true
   recipe.deletedAt = Date()
   Recipe hidden from main list

5. Recipe appears in "Recently Deleted" view for 30 days

6. purgeExpiredDeletions():
   Find recipes where locallyDeleted == true
     AND deletedAt < (now - 30 days)
   modelContext.delete(recipe)  ← hard delete
```

### Scenario 8: First Sync — Bulk Upload

**Trigger:** `SyncService.sync()` detects the first-sync condition:
user just authenticated (JWT in Keychain), server returns 0 recipes from
the lightweight poll, and local SwiftData has ≥ 1 recipe with
`serverId == nil`. This is the ONLY scenario that does bulk upload — all
other syncs handle recipes individually. Runs automatically after first
login with no confirmation dialog.

User signs in for the first time. Server has 0 recipes, iOS has N local recipes.

```
1. User signs in → JWT stored in Keychain

2. sync() called automatically:
   GET /recipes?fields=id,updated_at → returns empty list []

3. Detect first-sync condition:
   - Authenticated (JWT exists)
   - Server returned 0 recipes
   - Local SwiftData has ≥ 1 recipe with serverId == nil

4. Upload automatically (no confirmation dialog):
   For each local recipe (sequentially, respecting rate limits):
     POST /api/v1/recipes { RecipeDTO }
     ├─ 201 → store serverId, set lastSyncedAt, needsSync = false
     └─ Error → leave needsSync = true, continue to next recipe

5. After all attempts:
   ├─ All succeeded → silent success
   ├─ Some failed → show "Could not sync N recipes" warning
   └─ All failed → show "Could not sync recipes" warning

6. Failed recipes will retry on next sync() call
```

**Rate limit consideration:** Server allows 30 creates/minute. With sequential
uploads, 30 recipes takes ~30 seconds (network latency). If user has 60+ recipes,
the upload spans multiple minutes. The retry logic handles 429 responses with
exponential backoff.

### Scenario 9: Write Failure Warning

**Trigger:** Any of Scenarios 1, 2, 6, or 8 fail at the HTTP level — the
POST/PUT/DELETE returns an error or the network is down. This isn't a
separate sync step; it's error handling within `pushChanges()` and
`processDeletions()`. The failed recipe keeps `needsSync = true` (or
`locallyDeleted = true`) so it retries on the next sync cycle.

Any scenario where writing to the server fails (create, update, or delete).

```
1. APIClient throws an error on POST/PUT/DELETE:
   ├─ APIError.serverError(429) → retryable, exponential backoff
   ├─ APIError.serverError(500+) → retryable, exponential backoff
   ├─ APIError.unauthorized → not retryable, trigger re-auth
   ├─ URLError (network) → retryable
   └─ After max retries exhausted → mark as failed

2. SyncService tracks failed write count per sync() call

3. If any writes failed:
   syncService.lastSyncError = "Could not sync N recipes"
   syncService.hasWriteFailures = true

4. UI shows persistent warning banner in RecipeListView:
   ⚠️ "Could not sync recipes — will retry"
   (Not auto-dismissed — stays until next successful sync)

5. On next successful sync where all writes succeed:
   syncService.lastSyncError = nil
   syncService.hasWriteFailures = false
   Banner disappears
```

---

## What Remains To Be Done

### Phase 1 Addendum: Add `user_id` to Recipes

The recipes table currently has no user scoping. Every uploaded recipe needs
a `user_id` FK to `allowed_users.id`.

**Server changes:**
- `server/models/recipe.py` — add `user_id` column (UUID FK to allowed_users, nullable
  for now to avoid breaking existing data, but required on create)
- `server/routers/recipes.py` — all queries filter by `user_id = current_user.id`;
  create sets `user_id = current_user.id`
- `database/init.sql` — add `user_id UUID REFERENCES allowed_users(id)` + index
- `server/tests/test_recipes.py` — verify user scoping (user A can't see user B's recipes)

**Migration for existing data:** Any existing recipes in Postgres without a
`user_id` will be assigned to the admin user (seanickharlson@gmail.com) via a
one-time data migration script.

### Phase 2 Remaining: Dirty Marking + TestFixtures

**RecipeEditView.swift** — mark recipes dirty on save:
```swift
// In save(), after setting all fields:
target.needsSync = true
```

**TestFixtures/Recipe.swift** — add matching sync fields to `RecipeModel`:
```swift
var serverId: String?
var needsSync: Bool
var lastSyncedAt: Date?
var locallyDeleted: Bool
var deletedAt: Date?
var isConflictedCopy: Bool
```

**RecipeListView.swift** — hide locally-deleted and conflicted-copy recipes
from the default list (filter `locallyDeleted == false`).

### Phase 3: SyncService Core

**New file: `RecipeApp/Services/SyncService.swift`**

An `@Observable` class orchestrating all sync logic. Single entry point: `sync()`.

```
SyncService
  ├── sync()                    // Main: called on launch + pull-to-refresh
  ├── performFirstSync()        // Upload all local recipes (first login)
  ├── pullChanges()             // Fetch server state, apply to local
  ├── pushChanges()             // Push needsSync=true recipes to server
  ├── resolveConflict(local:server:)
  ├── processDeletions()        // Push/pull deletes
  └── purgeExpiredDeletions()   // Remove 30-day-old soft deletes
```

**Sync algorithm (on each `sync()` call):**

1. `GET /recipes?fields=id,updated_at` — get server inventory
2. Compare against local SwiftData:
   - **Server-only recipe** → `GET /recipes/{id}` → insert locally
   - **Local-only recipe** (no `serverId`) → `POST /recipes` → store `serverId`
   - **Both exist, server newer** → pull and overwrite local
   - **Both exist, local newer** (`needsSync=true`) → `PUT /recipes/{id}`
   - **Both changed** (conflict) → server wins, local copy saved as
     "[Name] (conflicted copy [date])" with `isConflictedCopy=true`
   - **Server missing, local has serverId** → soft-delete locally
   - **Local `locallyDeleted=true`** → `DELETE /recipes/{id}` on server
3. Set `lastSyncedAt = now`, `needsSync = false` on all synced recipes

**First-sync detection:**
- User is authenticated (has JWT)
- Server returned 0 recipes
- Local SwiftData has ≥ 1 recipe with `serverId == nil`
- Upload automatically — no confirmation dialog (see Scenario 8)

**Wire into app lifecycle (`RecipeAppApp.swift`):**
- Call `sync()` when scene enters `.active` (if authenticated)
- Pass `SyncService` as environment object to views

### Phase 4: UI Polish

**RecipeListView.swift:**
- Sync status indicator in toolbar (spinning arrow during sync, brief checkmark after)
- Conflict banner: "N conflicts resolved" with tap to filter conflicted copies
- Pull-to-refresh triggers sync
- Filter out `locallyDeleted == true` recipes
- Swipe-to-delete sets `locallyDeleted = true` + `deletedAt = now` instead of
  immediate `modelContext.delete()`

**SettingsView.swift:**
- "Force Full Sync" button — clears all `lastSyncedAt`, re-downloads everything
- "Recently Deleted" link → list of soft-deleted recipes with restore option
- Last sync timestamp display

**Error handling:**
| Error | UI | Behavior |
|-------|-----|----------|
| No network | Silent | Sync skipped, retry next launch |
| 401 Unauthorized | Banner + auto-logout | "Session expired — sign in again" |
| Conflict | Banner | "N conflicts resolved — check conflicted copies" |
| Write failure (create/update/delete) | Persistent warning banner | "Could not sync recipes — will retry" (see Scenario 9). Stays until next successful sync. |
| Read failure (pull) | Silent | Retry next sync |

### Phase 5: Maintenance Cron Job + Backup

A single script handles all periodic maintenance. Runs weekly via Cloud
Scheduler (or system cron on the server).

**New file: `scripts/maintenance.sh`**

Three tasks in one invocation:
1. **Purge expired soft-deletes** — hard-delete recipes where `deleted_at` > 30 days
2. **Backup** — `pg_dump` → gzip → upload to Cloud Storage bucket
   - Anomaly detection: compare record count + dump size against previous
     backup's JSON sidecar metadata; if >20% change, FAIL (do not overwrite)
   - Email alert on anomaly (via SendGrid/SMTP)
   - Retention: 4 rolling weekly backups (28-day lifecycle policy)
3. **Quota check** — query Neon/Cloud Run free-tier usage, log warning if
   approaching limits (e.g., >80% of storage or compute)

Flags: `--dry-run` (show plan without executing), `--skip-backup`,
`--skip-purge`, `--skip-quota`.

**Where does the cron job run?**

| Option | Free tier? | Auth model | Pros | Cons |
|--------|-----------|------------|------|------|
| **Cloud Scheduler → Cloud Run Job** | Yes (3 free jobs, 2M free invocations/mo) | Service account with Cloud SQL/Storage IAM roles. DB connection via `DATABASE_URL` env var (same as API server). No user auth needed — it's infra, not a user. | Native GCP, no server to maintain, logs in Cloud Logging | Needs a container image (can share the API image + entrypoint override) |
| **GitHub Actions scheduled workflow** | Yes (2000 min/mo free) | `DATABASE_URL` + `GCLOUD_SERVICE_KEY` as repo secrets. `pg_dump` via psql client in runner. | Already have GitHub, familiar CI, no new infra | Runner has no persistent state, needs to install tools each run, egress from GitHub to Neon adds latency |
| **Raspberry Pi cron** | Yes (already running) | SSH access already configured. `DATABASE_URL` as env var or in `.env` file. `gcloud` CLI or `gsutil` for Cloud Storage. | Zero cost, full control, already used for deployment | Pi must be online, no alerting if it's down, manual `gcloud` auth setup |

**Recommendation:** Cloud Run Job triggered by Cloud Scheduler. It's the
simplest option that stays within free tier, runs in the same environment as
the API, and inherits the same service account for DB access and Cloud Storage.
The maintenance script runs as a container entrypoint — no user-level auth
needed, just the service account's IAM permissions.

**Auth context:** The cron job connects directly to Postgres via `DATABASE_URL`
(same connection string the API server uses). It doesn't go through the API
endpoints, so it doesn't need JWT/API key auth. For Cloud Storage uploads,
the Cloud Run service account gets `storage.objectAdmin` on the backup bucket.
No additional credentials to manage.

**New file: `scripts/restore-db-backup.sh`**
- Downloads specified backup from Cloud Storage
- Confirms with user before restoring
- Restores via `psql`

### Phase 6: Canonical Schema + Schema Sync Test

**`schema/canonical.yaml`** — add `deleted_at` to Recipe:
```yaml
deleted_at:
  type: datetime_optional
  surfaces: [sql, sqlalchemy, pydantic_response]
```

Note: `deleted_at` is intentionally NOT on `swiftdata` or `testfixtures` surfaces.
The iOS sync fields (`serverId`, `needsSync`, etc.) are iOS-only — they don't
belong in the canonical schema since they're not shared across surfaces. The
canonical schema tracks the *recipe data model*, not sync metadata.

**`scripts/test_schema_sync.py`** — verify new field passes sync check.

---

## Testing Plan

### Server (automated — pytest)

| Test | Phase | Status |
|------|-------|--------|
| Soft delete hides from list | 1 | ✅ Passes |
| Soft delete returns 404 on GET | 1 | ✅ Passes |
| Deleted recipes admin list | 1 | ✅ Passes |
| Restore deleted recipe | 1 | ✅ Passes |
| Lightweight list returns id+updated_at only | 1 | ✅ Passes |
| Lightweight list excludes deleted | 1 | ✅ Passes |
| Soft delete blocks PUT update | 1 | ✅ Passes |
| All 60 existing server tests | 1 | ✅ Pass |

### iOS (manual — device/simulator testing)

| Test | Phase | How to verify |
|------|-------|---------------|
| SwiftData migration non-destructive | 2 | Install old build with recipes → update → recipes still there |
| APIClient hits Cloud Run, not localhost | 2 | Check network inspector in release build |
| Editing a recipe sets `needsSync = true` | 2 | Edit recipe, check SwiftData in debugger |
| First-sync upload prompt appears | 3 | Fresh login with local recipes, server empty |
| Upload all recipes → visible on web | 3 | Complete first sync → check web frontend |
| Edit on web → pull-to-refresh → change appears | 3 | Edit name on web, pull-to-refresh on iOS |
| Conflict creates copy | 3 | Edit same recipe on iOS (offline) + web → reconnect |
| Delete on web → iOS shows as deleted | 3 | Delete via web, sync on iOS, check "Recently Deleted" |
| Delete on iOS → web no longer shows | 3 | Delete on iOS, sync, check web |
| Sync spinner visible | 4 | Watch nav bar during sync |
| Conflict banner taps to review | 4 | Create conflict, tap banner |
| Error toast on server error | 4 | Disable network, trigger sync |
| Force Full Sync re-downloads everything | 4 | Tap in Settings |

### Schema sync (automated)

```bash
python scripts/test_schema_sync.py   # must pass after Phase 6
```

### Maintenance + Backup (manual)

| Test | Phase | How to verify |
|------|-------|---------------|
| `--dry-run` shows correct plan | 5 | Run script, inspect output |
| Purge deletes expired soft-deleted recipes | 5 | Insert recipe with old `deleted_at`, run purge, confirm gone |
| Real backup appears in Cloud Storage | 5 | Run script, check bucket |
| Anomaly detection: delete 50% records → FAILS | 5 | Delete rows, run backup, confirm failure |
| Quota check logs warning near limits | 5 | Check output for quota report |
| Restore from backup → all recipes intact | 5 | Restore, query DB |
| Cloud Run Job triggered by Scheduler | 5 | Check Cloud Scheduler history + Cloud Run Job logs |

---

## Risks & Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| 1 | **Sync bug mass-deletes recipes** | Low | Critical | Server soft-delete (30 days) + weekly backups + anomaly detection. Never hard-delete on first pass. |
| 2 | **SwiftData migration breaks existing data** | Low | High | All new fields are optional/defaulted — SwiftData handles this as a lightweight migration. Test on device with existing data before release. |
| 3 | **Conflict resolution confuses users** | Medium | Medium | Clear "[Name] (conflicted copy [date])" naming + banner notification. User can review and delete copy manually. |
| 4 | **Large imageData payloads slow sync** | Low | Medium | Base64 in JSON for now (images rare in current usage). Add separate image upload endpoint later if needed. |
| 5 | **CloudKit and server diverge over time** | Medium | Medium | CloudKit becomes read-only cache after sync is enabled; server is authoritative. CloudKit sync is disabled for synced recipes. |
| 6 | **First sync uploads duplicates** | Low | Low | Deduplicate by `name + createdAt` before uploading (belt-and-suspenders). |
| 7 | **Offline edits lost on crash** | Very Low | Medium | `needsSync` flag persists in SwiftData; survives app restart. Queue rebuilds on next `sync()`. |
| 8 | **Rate limiting blocks bulk first-sync** | Low | Medium | Sequential uploads with 30/min limit. 30 recipes = 1 minute. Add backoff if 429 received. |
| 9 | **Production Cloud Run URL changes** | Low | Low | URL is compile-time constant. Needs app update if it changes. Could move to remote config later. |

---

## Open Questions

(None remaining — all resolved. See Resolved Decisions below.)

---

## Resolved Decisions

1. **Cloud Run URL** — Implementation detail. The production URL is a
   compile-time constant in `APIClient.swift` with `#if DEBUG` toggle.

2. **CloudKit coexistence** — CloudKit continues running as-is. It operates
   on local SwiftData storage and handles background sync to iCloud, which is
   analogous to the offline/not-server-synced path. Server sync is a separate
   layer on top.

   **Edge case — CloudKit hasn't finished syncing when user logs in:**
   If the user signs in to Google Auth before CloudKit has finished pulling
   data from iCloud (e.g., new device, slow network), the first server sync
   may see fewer local recipes than expected. Mitigation:
   - First sync only uploads recipes where `serverId == nil` — it doesn't
     delete anything.
   - When CloudKit finishes later and new recipes appear locally (still with
     `serverId == nil`), the next `sync()` call picks them up and uploads them.
   - Net effect: first sync may be partial, but no data is lost. Subsequent
     syncs catch up.

3. **User-scoped recipes** — `user_id` FK will be added to the recipes table.
   All uploaded recipes are scoped to the authenticated user. Server endpoints
   filter by `user_id` so users only see their own recipes.

4. **Maintenance cron job** — A single lightweight cron job (Cloud Scheduler
   or system cron on the server) runs weekly (or monthly). It performs:
   - Hard-delete recipes where `deleted_at > 30 days`
   - `pg_dump` backup with anomaly detection (see Phase 5)
   - Check free-tier quota usage and log a warning if approaching limits
   This replaces the separate purge job and backup trigger from the original
   plan — one job, one schedule.

5. **Web frontend architecture** — The current frontend is already lightweight
   and appropriate for the use case. It's a React SPA (Vite + TypeScript) with:
   - 4 pages: recipe list, recipe detail, recipe editor, login
   - 5 components: Layout, AuthGuard, RecipeCard, IngredientRow, CSS modules
   - 3 API modules: client (fetch wrapper), recipes (CRUD), auth
   - Dependencies: React 19, TanStack Query, react-router-dom — no heavy UI
     framework
   - Built bundle: **297 KB** — very small

   **Hosting options (free tier):**

   | Option | Cost | How |
   |--------|------|-----|
   | **Serve from Cloud Run API** | Free (already running) | Mount `dist/` as static files via FastAPI `StaticFiles`. No separate hosting needed. |
   | **GitHub Pages** | Free | `vite build` → push `dist/` to `gh-pages` branch. Custom domain via CNAME. |
   | **Cloudflare Pages** | Free (unlimited bandwidth) | Connect repo, auto-build on push. Custom domain included. |

   **Recommendation:** Serve from Cloud Run. The API is already running there,
   the bundle is 297 KB, and it eliminates CORS entirely (same origin). Add
   one line to `main.py`:
   ```python
   app.mount("/", StaticFiles(directory="frontend/dist", html=True))
   ```
   The `VITE_API_URL` env var becomes `/api/v1` (relative path, same origin).
   No separate deployment pipeline, no extra service, no CORS config needed.

   **No changes needed for sync.** The web frontend already has full CRUD
   (`fetchRecipes`, `createRecipe`, `updateRecipe`, `deleteRecipe`, `patchRecipe`)
   using cookie-based auth. Once iOS pushes recipes to the server, they're
   immediately visible and editable on the web. Edits flow back to iOS on
   next sync.

6. **Image sync strategy** — Limit: **5 images per recipe, max 2 MB each.**
   - Images stored as binary (`image_data` column) on the server
   - Upload via a separate endpoint: `PUT /api/v1/recipes/{id}/images`
   - Download via: `GET /api/v1/recipes/{id}/images/{index}`
   - The main recipe JSON payload does NOT include image data — images sync
     separately after the recipe metadata syncs
   - iOS stores images in SwiftData `imageData` field (existing)
   - Server validates: reject if >5 images or any single image >2 MB
   - This is a future phase — image sync is not in scope for the initial
     sync implementation. Recipes sync without images first.

7. **Schema sync test** — The canonical schema (`canonical.yaml`) defines the
   **wire format** — the data that travels between iOS and server over the API.
   App-only fields (like `serverId`, `needsSync`) and server-only fields (like
   `deleted_at`) are fine as surface-specific additions, but anything in the
   API response/request schemas must exist on both sides.

   Concretely:
   - `RecipeResponse` (pydantic) fields = the wire format
   - Every field in `RecipeResponse` must have a corresponding field in
     `RecipeDTO` (Swift) and vice versa
   - `deleted_at` is in `RecipeResponse` but is NOT in `RecipeDTO` — this is
     acceptable because the iOS client doesn't need it (deletion is signaled
     by absence from the list endpoint, not by a field value)
   - The schema sync test already validates per-surface, so no changes needed
     to the test logic — just ensure `canonical.yaml` entries list the correct
     surfaces for each field

---

## File Change Summary

| File | Phase | Change | Status |
|------|-------|--------|--------|
| `server/models/recipe.py` | 1 | `deleted_at` column | ✅ Done |
| `server/routers/recipes.py` | 1 | Soft delete, lightweight list, restore | ✅ Done |
| `server/schemas/recipe.py` | 1 | `RecipeListItem`, `deleted_at` on response | ✅ Done |
| `database/init.sql` | 1 | `deleted_at` column | ✅ Done |
| `server/tests/test_recipes.py` | 1 | 7 new tests | ✅ Done |
| `RecipeApp/Models/Recipe.swift` | 2 | Sync metadata fields | ✅ Done |
| `RecipeApp/Services/APIClient.swift` | 2 | Full rewrite — CRUD, retry, DTOs | ✅ Done |
| `RecipeApp/Views/Recipes/RecipeEditView.swift` | 2 | `needsSync = true` on save | ⬜ TODO |
| `RecipeApp/Views/Recipes/RecipeListView.swift` | 2,4 | Hide deleted, sync UI | ⬜ TODO |
| `TestFixtures/Recipe.swift` | 2 | Sync fields on `RecipeModel` | ⬜ TODO |
| `RecipeApp/Services/SyncService.swift` | 3 | **New** — sync orchestration | ⬜ TODO |
| `RecipeApp/RecipeAppApp.swift` | 3 | Wire sync on foreground | ⬜ TODO |
| `RecipeApp/Views/SettingsView.swift` | 4 | Force sync, recently deleted | ⬜ TODO |
| `scripts/maintenance.sh` | 5 | **New** — purge + backup + quota check | ⬜ TODO |
| `scripts/restore-db-backup.sh` | 5 | **New** — restore script | ⬜ TODO |
| `schema/canonical.yaml` | 6 | `deleted_at` field | ⬜ TODO |

---

## Appendix: Architecture Review & Simplification Recommendations

### What we'd do differently if starting from scratch

After reviewing the full codebase with the sync plan in mind, several
architectural issues stand out. Fixing these before implementing the remaining
phases would reduce complexity and prevent bugs.

### Issue 1: Two Different Base URLs for the Same Server

**Problem:** `AuthService.swift` and `APIClient.swift` use different hardcoded
base URLs pointing to what appear to be different Cloud Run services:

```swift
// AuthService.swift
"https://recipe-api-972511622379.us-west1.run.app/api/v1/auth"

// APIClient.swift (new, from Phase 2)
"https://recipe-app-api-1018793882381.us-central1.run.app/api/v1"
```

Different project numbers (`972511622379` vs `1018793882381`), different regions
(`us-west1` vs `us-central1`), different service names. This will break sync
immediately — auth tokens from one service won't be valid on the other.

**Fix:** Extract a single `ServerConfig` that both services share:

```swift
enum ServerConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:8000/api/v1")!
    #else
    static let baseURL = URL(string: "https://recipe-api-972511622379.us-west1.run.app/api/v1")!
    #endif
}
```

Both `AuthService` and `APIClient` use `ServerConfig.baseURL`. One place to
change, one URL to verify.

**Steps:**
1. Create `RecipeApp/Services/ServerConfig.swift` with the enum above
2. Update `AuthService.init()` to use `ServerConfig.baseURL.appendingPathComponent("auth")`
3. Update `APIClient.init()` to use `ServerConfig.baseURL`
4. Verify the correct production URL (which of the two is correct?)

### Issue 2: AuthService and APIClient Build Their Own HTTP Requests Independently

**Problem:** Both `AuthService` and `APIClient` independently construct
`URLRequest` objects, add auth headers, handle HTTP status codes, and decode
JSON. This means:
- Auth header logic is duplicated (both call `KeychainService.loadToken()`)
- Error handling is inconsistent (AuthService doesn't retry; APIClient does)
- Token refresh is only in AuthService — if APIClient gets a 401, it throws
  `APIError.unauthorized` but doesn't attempt refresh

When SyncService is added, it will need to coordinate between both — calling
APIClient for data and AuthService for token refresh on 401. This is fragile.

**Fix:** Make `APIClient` the single HTTP layer. AuthService calls APIClient
for its requests instead of building its own. APIClient handles 401 → refresh
→ retry internally.

**Steps:**
1. Add `exchangeGoogleToken(idToken:)` and `fetchMe()` methods to APIClient
2. Add 401 → token refresh → retry logic in APIClient's `performRequest()`
3. Slim AuthService to just manage auth state (login flow, logout, current user)
   and delegate HTTP calls to APIClient
4. SyncService only depends on APIClient — no direct URL construction

### Issue 3: APIClient is an Actor, But SyncService Needs ModelContext

**Problem:** `APIClient` is an `actor`, which is good for thread safety. But
`SyncService` needs to:
1. Call `APIClient` methods (actor-isolated, needs `await`)
2. Read/write `ModelContext` (main actor only in SwiftData)
3. Update `@Observable` state for the UI (main actor)

Having SyncService juggle actor isolation between APIClient and the main actor
adds unnecessary complexity.

**Fix:** Make `SyncService` a `@MainActor @Observable` class. It calls
`APIClient` with `await` (crossing actor boundaries is fine), and it reads/writes
`ModelContext` directly since it's already on the main actor.

This is actually what the plan already describes — just confirming it's the
right pattern. No change needed, but worth noting that `APIClient` should
remain an actor (it owns `URLSession` state) and `SyncService` should NOT be
an actor (it needs `ModelContext`).

### Issue 4: RecipeDTO is Missing Fields Compared to the Wire Format

**Problem:** The `RecipeDTO` in the current (just-rewritten) `APIClient.swift`
includes most fields but is missing some that exist in the server's
`RecipeResponse`:
- `cuisine`, `course`, `tags`, `sourceURL`, `difficulty` — ✅ added in rewrite
- `isFavorite`, `isPublished` — ✅ added
- `createdAt`, `updatedAt` — ✅ added

However, the DTO fields used for encoding (POST/PUT) and decoding (GET response)
are the same struct. This is fine for now, but note that `id`, `createdAt`,
and `updatedAt` are optional in the DTO because they're nil on create but
present on response. This dual-purpose DTO works but could be cleaner.

**Recommendation:** Keep the single DTO for now. The optionality of `id`,
`createdAt`, `updatedAt` is acceptable. Split into `RecipeCreateDTO` and
`RecipeResponseDTO` only if the shapes diverge further.

### Issue 5: RecipeViewModel Is Barely Used

**Problem:** `RecipeViewModel` has two functions:
1. `searchText` and `sortOrder` state — but `RecipeListView` manages its own
   `@State` search/filter/sort instead of using the view model
2. `generateGroceryList()` — a utility method that doesn't need a view model

The view model isn't providing value. RecipeListView uses `@Query` directly
and manages all its own state. SyncService will introduce actual view-level
state (sync status, errors) that views need to observe.

**Recommendation:** Don't fix this now. When SyncService is implemented, its
`@Observable` properties will serve as the "view model" for sync state. The
existing RecipeViewModel can be left alone — it's harmless and used by the
grocery list generation feature.

### Issue 6: Delete in RecipeListView Hard-Deletes Immediately

**Problem:** `RecipeListView.deleteRecipes()` calls `modelContext.delete()`,
which hard-deletes the SwiftData record. With sync, this needs to become a
soft-delete (`locallyDeleted = true`) so the deletion can be pushed to the
server.

**This is already in the plan (Phase 4)** but worth calling out as a breaking
change — the delete behavior changes from immediate to deferred.

### Issue 7: No Shared Date Formatting

**Problem:** The server returns ISO8601 dates. The APIClient has custom date
decoding. AuthService uses default JSONDecoder (no date strategy). If dates
round-trip through sync, they need consistent encoding/decoding everywhere.

**Fix:** Already addressed in the APIClient rewrite (`JSONDecoder.apiDecoder`
and `JSONEncoder.apiEncoder`). Just ensure AuthService uses the same decoders
if it handles any date fields.

### Recommended Pre-Implementation Steps

Before continuing with Phase 2–4, do these in order:

| # | Change | Effort | Why |
|---|--------|--------|-----|
| **A** | Create `ServerConfig.swift` — single base URL | 15 min | Blocks everything. Can't sync if auth and API hit different servers. |
| **B** | Verify correct production Cloud Run URL | 5 min | Which of the two URLs is the real one? |
| **C** | Move HTTP calls from AuthService into APIClient | 1 hr | Single HTTP layer with retry + token refresh. SyncService only depends on APIClient. |
| **D** | Add 401 → refresh → retry in APIClient | 30 min | Required for sync — long-running sync sessions may hit token expiry. |

Steps A–D should be done before Phase 3 (SyncService). They can be done as
part of Phase 2 completion. Steps A and B are blockers — the rest are
quality-of-life improvements that prevent bugs during sync implementation.

### What We'd Skip

- **RecipeViewModel refactor** — not worth the churn. Leave it.
- **Split RecipeDTO into create/response** — premature. Single DTO works fine.
- **Actor → class conversion for APIClient** — actor is correct for URLSession.
  SyncService handles the actor boundary crossing with `await`.

---

## Appendix B: Testing Infrastructure Improvements

### Current Testing State

| Layer | Framework | Count | Coverage | Gaps |
|-------|-----------|-------|----------|------|
| Server (Python) | pytest + TestClient | 60 | Good — CRUD, auth, soft delete | No user-scoping tests, no concurrent write tests |
| SharedLogic (Swift) | swiftc test suites | 300 | Good — parsers, classifiers | No sync/network tests (expected) |
| iOS (XCTest) | Codemagic simulator | 3 suites | Minimal — model init, template, ML | No APIClient tests, no SyncService tests |
| Web frontend | None | 0 | None | No tests at all |
| Integration | None | 0 | None | No end-to-end sync tests |

### What Needs to Change for Reliable Sync

#### 1. Server: Add User-Scoped Tests

Once `user_id` is added to recipes, the test fixtures need a second user to
verify isolation:

```python
# conftest.py additions
@pytest.fixture
def second_user_headers(client) -> dict:
    """Auth for a different user — should NOT see first user's recipes."""
    ...
```

**Tests to add:**
- User A creates recipe → User B's list returns empty
- User A's recipe → User B gets 404 on GET/PUT/DELETE
- User A and B can each have a recipe named "Pasta" without conflict

#### 2. Server: Sync-Specific Endpoint Tests

Test the sync scenarios the iOS client will exercise:

- Lightweight list returns correct `updated_at` after PUT
- Soft-delete → recipe disappears from lightweight list
- Restore → recipe reappears in lightweight list
- Create → immediate GET returns same data (round-trip fidelity)
- PUT with changed ingredients → GET returns new ingredients, not old + new
- Concurrent updates (two PUTs to same recipe) → last write wins, no crash

#### 3. iOS: APIClient Unit Tests (Mock Server)

The APIClient can be tested without a real server using a custom `URLProtocol`.
This validates:

- Request construction: correct URL paths, HTTP methods, headers
- JSON encoding: snake_case CodingKeys produce valid server payloads
- JSON decoding: server responses (with dates, UUIDs, nested ingredients)
  decode correctly
- Retry logic: simulated 429/500 → retries with backoff → eventual success
- Non-retryable errors: 401 → throws immediately, no retry
- 404 → throws `APIError.notFound`

**How:** Add `RecipeAppTests/APIClientTests.swift`. Use `URLProtocol` subclass
to intercept requests and return canned responses. This runs on Codemagic
without a server.

#### 4. iOS: SyncService Unit Tests (Mock APIClient)

SyncService depends on APIClient and ModelContext. Test it with:
- A protocol-based `APIClientProtocol` so a mock can be injected
- An in-memory `ModelContainer` for SwiftData (no persistence)

**Scenarios to test:**
- First sync: 0 server recipes, N local → all uploaded, serverId set
- Pull new: server has recipe not in local → inserted locally
- Pull update: server newer → local overwritten
- Push update: local newer → PUT called
- Conflict: both changed → conflict copy created, server wins
- Delete local → DELETE called
- Delete server → local soft-deleted
- Network error → needsSync remains true, write failure count incremented
- 401 during sync → triggers re-auth

**How:** Add `RecipeAppTests/SyncServiceTests.swift`. Use in-memory
ModelContainer + mock APIClient. These are the most critical tests in the
entire sync system.

#### 5. Integration: Round-Trip Test

A single integration test that exercises the full path:

1. Start local FastAPI server (pytest fixture)
2. Create recipe via APIClient → verify server has it
3. Update recipe via server → pull via APIClient → verify local updated
4. Delete via APIClient → verify server soft-deleted

This can run as a pytest test that also exercises the Swift DTO encoding.
Alternatively, it can be a shell script that uses `curl` to simulate the iOS
client against a local server.

**Recommendation:** Start with `curl`-based integration test in
`scripts/test_sync_integration.sh`. It validates the wire format without
needing Swift compilation. Full iOS ↔ server integration testing can come
later.

#### 6. Schema Sync Test: Wire Format Validation

The existing `test_schema_sync.py` validates field presence across surfaces.
Extend it to also validate that:

- Every field in `RecipeResponse` (pydantic) has a matching `CodingKey` in
  `RecipeDTO` (Swift)
- Every field in `RecipeDTO` has a matching field in `RecipeCreate` (pydantic)
- Field types are compatible (e.g., `int` ↔ `Int`, `float` ↔ `Double`)

This catches drift between server and iOS wire formats before it becomes a
runtime bug.

#### Testing Priority Order

| Priority | What | Why |
|----------|------|-----|
| **P0** | Server user-scoping tests | Blocks Phase 1 addendum (user_id) |
| **P0** | SyncService unit tests | Core correctness of the sync algorithm |
| **P1** | APIClient unit tests | Catches encoding/decoding bugs before device testing |
| **P1** | Wire format schema validation | Catches drift automatically |
| **P2** | curl integration test | End-to-end confidence |
| **P3** | Web frontend tests | Low priority — viewer/editor, not data integrity |
