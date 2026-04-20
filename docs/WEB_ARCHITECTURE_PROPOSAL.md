# Recipe App — Web Architecture Proposal

**Date**: 2026-04-19
**Status**: Draft — pending review before implementation
**Scope**: Steps 1 (share links), 2 (web editor), 3 (sync), 5 (auth + multi-user)
**Constraint**: Must not impede any current on-device flow

---

## Table of contents

1. [Current state](#1-current-state)
2. [Users and use cases](#2-users-and-use-cases)
3. [Architecture overview](#3-architecture-overview)
4. [Step 1: Shareable recipe links](#4-step-1-shareable-recipe-links)
5. [Step 2: Web recipe editor](#5-step-2-web-recipe-editor)
6. [Step 3: Sync bridge](#6-step-3-sync-bridge)
7. [Step 5: Auth + multi-user](#7-step-5-auth--multi-user)
8. [Future-proofing: AI processing tier](#8-future-proofing-ai-processing-tier)
9. [Schema alignment](#9-schema-alignment)
10. [Hosting plan](#10-hosting-plan)
11. [Architecture diagram](#11-architecture-diagram)
12. [Lessons learned applied](#12-lessons-learned-applied)
13. [Open questions](#13-open-questions)
14. [Active bugs and features summary](#14-active-bugs-and-features-summary)

---

## 1. Current state

### What works today (on-device, no server)

- SwiftUI app with SwiftData persistence backed by CloudKit private DB
- Single-user: Nick's iCloud account owns all data
- Recipe CRUD, grocery lists, shopping templates, pantry scanning
- OCR pipeline (camera → VisionKit → pure Swift parsers) — fully on-device
- CoreML food classifier (nateraw/food ViT, 164MB) — on-device
- Build pipeline: Windows dev → GitHub push → Codemagic → TestFlight
- 541 tests across 11 pure-Swift suites + XCTests

### What exists but is not deployed

- `server/` — FastAPI skeleton with SQLAlchemy models, 5 endpoints, 5 tests
- `database/init.sql` — PostgreSQL schema (recipes, ingredients, grocery_lists,
  grocery_items)
- `database/seed.sql` — Sample data

### Schema drift between iOS and server

The iOS SwiftData models have evolved significantly beyond the server schema:

| Feature | iOS (SwiftData) | Server (SQLAlchemy) | Gap |
|---------|-----------------|---------------------|-----|
| Recipe fields | 16 stored + 1 computed | 10 stored | Missing: cuisine, course, tags, sourceURL, difficulty, isFavorite |
| Ingredient fields | 7 stored | 4 stored | Missing: category, displayOrder, notes |
| GroceryList | has archivedAt | no archivedAt | Missing: archive support |
| GroceryItem | has sourceRecipeName/Id | no source tracking | Missing: recipe traceability |
| ShoppingTemplate | full model | not in server | Entirely missing |
| TemplateItem | full model | not in server | Entirely missing |
| PantryItem | full model | not in server | Entirely missing |
| Category order | "Spices" added (12 categories) | not modeled | Missing |

**The server schema must be updated to match iOS before any sync work begins.**

---

## 2. Users and use cases

### Nick (primary user, iPhone + Windows desktop)

- Scans recipes from cookbooks (camera OCR) — **stays on-device**
- Scans handwritten shopping lists — **stays on-device**
- Wants to type recipes from a desktop keyboard — **needs web editor**
- Wants to share recipe links with friends — **needs shareable URLs**
- Wants AI-assisted pantry detection and recipe Q&A — **needs AI tier**

### Anna (wife, iPhone user)

- Shared shopping list with Nick — **needs multi-user**
- Recipe voting ("what should we cook this week?") — **needs multi-user**
- iPhone user, iCloud account — can use CloudKit sharing OR web auth

### Lizzii (sister-in-law, remote, may not have iPhone)

- Lives on the other side of the world
- NOT a shared shopping list user
- Made a personal cookbook, may make another
- Wants to help Nick update his recipe list remotely — **needs web editor**
- May not have an iPhone — **web-only access path required**

### Friends (read-only)

- Receive recipe links — **needs shareable URLs**
- No account needed — public read-only pages

---

## 3. Architecture overview

### Core principle: the iOS app remains the primary client

The on-device flow (CloudKit, OCR, CoreML) must never depend on the web
server. If the server is down, the iOS app works exactly as it does today.
The server is an **additive layer** — it adds capabilities (web editing,
sharing, AI processing) but is never in the critical path for on-device
features.

### Three-layer architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        CLIENTS                              │
│                                                             │
│   ┌──────────┐    ┌──────────┐    ┌───────────────────┐    │
│   │ iOS App  │    │ Web App  │    │ Public Recipe Page │    │
│   │ (SwiftUI)│    │ (React)  │    │ (Static HTML)     │    │
│   └────┬─────┘    └────┬─────┘    └───────────────────┘    │
│        │               │                                    │
│   CloudKit          REST API           GitHub Pages         │
│   (private)         (auth'd)           (no auth)            │
└────────┼───────────────┼────────────────────────────────────┘
         │               │
┌────────┼───────────────┼────────────────────────────────────┐
│        │          BACKEND                                   │
│        │               │                                    │
│        │         ┌─────┴──────┐                             │
│        │         │  FastAPI   │──── Google OAuth             │
│        │         │  (Cloud    │──── Sign in with Apple       │
│        │         │   Run)     │                              │
│        │         └─────┬──────┘                              │
│        │               │                                    │
│        │         ┌─────┴──────┐    ┌────────────────┐       │
│        │         │ PostgreSQL │    │  Job Queue     │       │
│        │         │ (Cloud SQL │    │  (Redis or     │       │
│        │         │  or Neon)  │    │   Postgres)    │       │
│        │         └────────────┘    └───────┬────────┘       │
│        │                                   │                │
│   ┌────┴─────────────┐            ┌────────┴────────┐       │
│   │  Sync Bridge     │            │  AI Workers     │       │
│   │  (CloudKit ↔ PG) │            │  (Pi 5 AI Hat   │       │
│   │  runs on Cloud   │            │   or Gemini)    │       │
│   │  Run as cron     │            │                 │       │
│   └──────────────────┘            └─────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Step 1: Shareable recipe links

### Goal

Nick shares a URL like `recipes.seanick80.com/marathon-chicken-bake` with
a friend. They see the recipe rendered beautifully in their browser. No
login required.

### Approach: Static site generation

The iOS app (or a web editor in Step 2) publishes recipes to a static site.
Each recipe becomes a standalone HTML file with:
- Embedded JSON-LD (`schema.org/Recipe`) for SEO and rich previews
- Open Graph meta tags for link previews in iMessage, WhatsApp, etc.
- Print-friendly CSS
- Mobile-responsive layout

### Hosting

**GitHub Pages** (free, custom domain via CNAME):
- Repo: `seanick80/recipes` (or a `gh-pages` branch on recipe-app)
- Deploy via GitHub Actions on push
- Custom domain: `recipes.seanick80.com` (or similar)

### How recipes get published

**Phase 1 (Step 1 only)**: Manual export from the iOS app.
- New "Share Recipe" action in RecipeDetailView
- Generates a static HTML file
- Uploads via GitHub API (personal access token stored in Keychain)
- Returns the public URL for sharing

**Phase 2 (after Step 2)**: Web editor has a "Publish" toggle per recipe.
- Publishing writes the HTML to the static site repo
- Unpublishing removes it

### What this does NOT do

- No login, no accounts, no backend
- No editing from the web (that's Step 2)
- No sync (that's Step 3)

### Effort: 1-2 sessions

---

## 5. Step 2: Web recipe editor

### Goal

Nick (or Lizzii) types a recipe on a laptop with a real keyboard. The
recipe is stored server-side and synced to Nick's iPhone (Step 3).

### Approach: React SPA + FastAPI backend

**Frontend**: React (reuse patterns from Good Morning dashboard)
- Recipe create/edit form with structured ingredient entry
- Shopping list viewer (read-only initially, editable in Step 5)
- Import from URL (reuse JSON-LD extraction logic)
- No framework bloat — Vite + React + TypeScript, no component library

**Backend**: FastAPI on Cloud Run (already scaffolded in `server/`)
- Bring SQLAlchemy models up to parity with iOS SwiftData schema
- RESTful API with proper validation (Pydantic schemas)
- No auth yet (Step 2 is single-user, protected by network/token)

### Server schema update required

Before any web editor work, the `server/` models must be updated:

```
Recipe: add cuisine, course, tags, sourceURL, difficulty, isFavorite
Ingredient: add category, displayOrder, notes
GroceryList: add archivedAt
GroceryItem: add sourceRecipeName, sourceRecipeId
NEW: ShoppingTemplate model
NEW: TemplateItem model
NEW: PantryItem model (for future use)
```

### Hosting: Cloud Run (free tier)

- Scales to zero when idle — $0/month for single-user volume
- Same GCP project as Good Morning (existing billing, existing Google Cloud
  account)
- PostgreSQL: **Neon free tier** (0.5 GB, scales to zero, no fixed cost)
  or **Cloud SQL** ($7-9/month if always-on). Neon recommended for Step 2
  to keep costs at $0. Migrate to Cloud SQL only if Neon limits become a
  bottleneck.

### API design

Prefix: `/api/v1/`

| Resource | Endpoints |
|----------|-----------|
| Recipes | GET, POST, PUT, PATCH, DELETE `/recipes/{id}` |
| Ingredients | Nested under recipes (cascade) |
| Grocery Lists | GET, POST, PUT, DELETE `/grocery-lists/{id}` |
| Grocery Items | CRUD nested under lists, PATCH toggle |
| Templates | GET, POST, PUT, DELETE `/templates/{id}` |
| Template Items | Nested under templates |
| Pantry Items | GET, POST, PUT, DELETE `/pantry/{id}` (future) |
| Publish | POST `/recipes/{id}/publish`, DELETE `/recipes/{id}/publish` |

### Auth for Step 2 (temporary, pre-Step 5)

Single-user protection until real auth is built:
- API key in `Authorization` header (stored in environment variable)
- No user model yet — all data belongs to "the one user"
- The API key is rotated if compromised; no sessions, no cookies

### Effort: 2-3 sessions

---

## 6. Step 3: Sync bridge

### Goal

Recipes and grocery lists stay in sync between the iOS app (CloudKit) and
the web editor (PostgreSQL). Changes on either side propagate to the other.

### The hard problem

CloudKit and PostgreSQL are independent databases with different data models,
different ID schemes (CloudKit record names vs. UUIDs), and no built-in
bridge. This is the most architecturally significant piece.

### Approach: Server-initiated pull + iOS-initiated push

```
iOS App                    Cloud Run                  PostgreSQL
   │                          │                          │
   ├──── CloudKit ────────────┤                          │
   │     (private DB)         │                          │
   │                          │                          │
   │  ┌───────────────────────┤                          │
   │  │ Sync Bridge (cron)    │                          │
   │  │ 1. CKFetchChanges    ├──── write ──────────────►│
   │  │ 2. Diff & merge      │                          │
   │  │ 3. CKModifyRecords   │◄──── read ──────────────┤
   │  └───────────────────────┤                          │
   │                          │                          │
   │  (Web edits go to PG    │                          │
   │   first, sync bridge    │                          │
   │   pushes to CloudKit)   │                          │
```

### Sync strategy: last-write-wins with conflict log

- Each record has an `updatedAt` timestamp on both sides
- Sync bridge runs every 5 minutes (Cloud Run cron job or Cloud Scheduler)
- On conflict (both sides modified since last sync): last-write-wins, but
  the losing version is logged to a `sync_conflicts` table for manual review
- Deletes are soft (set `deletedAt`, purge after 30 days) to prevent
  sync-delete races

### CloudKit server-to-server API

Apple provides a [CloudKit Web Services API](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/)
that allows server-side code to read/write CloudKit records using a
server-to-server key. This is how the sync bridge accesses Nick's private
CloudKit database without the iOS app being involved.

**Setup required**:
- Generate a server-to-server key in the CloudKit Dashboard
- Store the key in Cloud Run environment (or Secret Manager)
- The sync bridge authenticates as the app, accesses the private DB

### Sync field mapping

| iOS (CloudKit record) | PostgreSQL column | Notes |
|-----------------------|-------------------|-------|
| `CD_id` (CKRecord.recordName) | `cloudkit_record_name` (new column) | Immutable link between systems |
| `CD_updatedAt` | `updated_at` | Conflict detection |
| All other fields | Snake_case equivalents | Direct mapping |

### What syncs

| Model | Sync? | Direction | Notes |
|-------|-------|-----------|-------|
| Recipe | Yes | Bidirectional | Core use case |
| Ingredient | Yes | Bidirectional | Cascade with Recipe |
| GroceryList | Yes | Bidirectional | Shared shopping (Step 5) |
| GroceryItem | Yes | Bidirectional | Cascade with GroceryList |
| ShoppingTemplate | Yes | Bidirectional | Nick's templates |
| TemplateItem | Yes | Bidirectional | Cascade with Template |
| PantryItem | No (initially) | — | Low priority, on-device only for now |

### Risk: CloudKit Web Services complexity

The CloudKit server-to-server API is functional but not well-documented for
SwiftData-backed stores. The record field names when using SwiftData are
auto-generated (prefixed with `CD_`). This needs empirical testing:

1. Deploy the iOS app to TestFlight
2. Create some recipes
3. Use the CloudKit Dashboard to inspect the actual record structure
4. Map those field names to PostgreSQL columns

**This is the riskiest part of the entire proposal.** If CloudKit's
server-to-server API proves too painful, the fallback is:
- The iOS app itself does the sync (push to/pull from the REST API)
- This is simpler but requires the app to be online and active
- A background task (`BGAppRefreshTask`) can do periodic sync

### Effort: 3-4 sessions (including CloudKit investigation)

---

## 7. Step 5: Auth + multi-user

### Goal

Anna has her own account. She sees shared shopping lists with Nick. Lizzii
has her own account and can edit recipes on the web.

### Auth providers

Per App Store Review Guideline 4.8: if you offer Google Sign-In, you must
also offer Sign in with Apple.

| Provider | Why |
|----------|-----|
| **Sign in with Apple** | Required if Google is offered. Anna uses iPhone, so this is natural. |
| **Google Sign-In** | Lizzii may not have an Apple device. Also reuses Nick's existing Google Cloud account (same OAuth client as Good Morning). |

### User model

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL DEFAULT '',
    auth_provider TEXT NOT NULL,  -- 'apple' or 'google'
    auth_subject TEXT NOT NULL,   -- provider's unique user ID
    cloudkit_user_id TEXT,        -- if linked to an iCloud account
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX idx_users_auth ON users(auth_provider, auth_subject);
```

### Ownership model

```sql
-- Every recipe/list has an owner
ALTER TABLE recipes ADD COLUMN owner_id UUID REFERENCES users(id);

-- Sharing is explicit: owner grants access
CREATE TABLE shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type TEXT NOT NULL,  -- 'grocery_list', 'recipe_collection'
    resource_id UUID NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id),
    shared_with_id UUID NOT NULL REFERENCES users(id),
    permission TEXT NOT NULL DEFAULT 'read',  -- 'read', 'write', 'admin'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Shared shopping lists (Nick + Anna)

- Nick creates a grocery list
- Nick shares it with Anna (by email or in-app invite)
- Both see the list; both can add/check items
- Real-time not required — polling every 30s is fine for a shopping list
- If both are on iPhone: CloudKit sharing (CKShare) works natively
- If one is on web: the sync bridge handles it via PostgreSQL

### Recipe voting (Nick + Anna)

```sql
CREATE TABLE meal_proposals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES recipes(id),
    proposed_by UUID NOT NULL REFERENCES users(id),
    proposed_for DATE NOT NULL,  -- "dinner on Tuesday"
    status TEXT DEFAULT 'proposed',  -- proposed, accepted, rejected
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    proposal_id UUID NOT NULL REFERENCES meal_proposals(id),
    user_id UUID NOT NULL REFERENCES users(id),
    vote TEXT NOT NULL,  -- 'yes', 'no', 'maybe'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(proposal_id, user_id)
);
```

### Effort: 2-3 sessions

---

## 8. Future-proofing: AI processing tier

### Raspberry Pi 5 with AI Hat

Nick has a Raspberry Pi 5 (currently running the Good Morning Dashboard).
An AI Hat would add a neural processing unit capable of running inference
on small models locally.

### Job queue architecture

```
Web App / iOS App
     │
     ▼
  FastAPI
     │
     ▼ enqueue job
  ┌──────────────┐
  │  Job Queue   │  (PostgreSQL-backed, e.g., pgqueue or Celery+Redis)
  │              │
  │  job_type:   │
  │  - pantry_scan
  │  - recipe_ocr │
  │  - recipe_qa  │
  └──────┬───────┘
         │
    ┌────┴────────────────────┐
    │                         │
    ▼                         ▼
┌──────────┐          ┌──────────────┐
│ Pi 5     │          │ Cloud API    │
│ AI Hat   │          │ (Gemini /    │
│ Worker   │          │  Claude)     │
│          │          │              │
│ Polls    │          │ Fallback     │
│ queue    │          │ if Pi is     │
│ every    │          │ slow/down    │
│ 30s      │          │              │
└──────────┘          └──────────────┘
```

### How it works

1. Client submits a job (e.g., "scan this pantry photo")
2. FastAPI writes a row to a `jobs` table:
   ```sql
   CREATE TABLE jobs (
       id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
       job_type TEXT NOT NULL,
       payload JSONB NOT NULL,      -- input data (image URL, text, etc.)
       status TEXT DEFAULT 'pending', -- pending, processing, done, failed
       result JSONB,                 -- output when done
       worker TEXT,                  -- 'pi5' or 'gemini' or 'claude'
       created_at TIMESTAMPTZ DEFAULT NOW(),
       started_at TIMESTAMPTZ,
       completed_at TIMESTAMPTZ,
       owner_id UUID REFERENCES users(id)
   );
   ```
3. Pi 5 worker polls the `jobs` table every 30 seconds
4. Picks up a job, runs inference, writes result back
5. Client polls `GET /jobs/{id}` for status (or uses SSE for push)

### Swappable workers

The job queue is worker-agnostic. The Pi 5 AI Hat is just one worker
implementation. To scale up or replace with a cloud API:
- Deploy a second worker that calls Gemini/Claude instead of local inference
- Set a `preferred_worker` field or routing rules per job type
- Pi handles batch/background jobs; cloud handles real-time requests
- No architecture change needed — just a new worker process

### Job types mapped to backlog features

| Job type | Backlog item | Pi 5 feasible? | Cloud fallback |
|----------|-------------|----------------|----------------|
| `pantry_scan` | Improved pantry detection | Yes (small vision model) | Gemini 2.5 Pro |
| `recipe_ocr` | Cloud OCR fallback | Maybe (depends on model) | Gemini Flash-Lite |
| `recipe_qa` | "What temp does this bake at?" | Yes (small LLM) | Gemini Flash-Lite |
| `ingredient_match` | Pantry → recipe matching | Yes (embedding similarity) | Gemini Flash-Lite |
| `receipt_parse` | Receipt scanning/price tracking | Yes (OCR + parsing) | Gemini Flash-Lite |

### Cost

- Pi 5 AI Hat: ~$25-70 one-time hardware cost, $0/month ongoing
- Cloud fallback (if Pi is insufficient): $5-20/month per DESIGN_DECISIONS.md
- Job queue: PostgreSQL-backed (no Redis needed for low volume), $0 extra

---

## 9. Schema alignment

### PostgreSQL schema (target state)

The server schema must match iOS SwiftData exactly. Here is the target:

```sql
-- Users (Step 5)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL DEFAULT '',
    auth_provider TEXT NOT NULL,
    auth_subject TEXT NOT NULL,
    cloudkit_user_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login_at TIMESTAMPTZ
);

-- Recipes (aligned with iOS Recipe model)
CREATE TABLE recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    instructions TEXT NOT NULL DEFAULT '',
    prep_time_minutes INT NOT NULL DEFAULT 0,
    cook_time_minutes INT NOT NULL DEFAULT 0,
    servings INT NOT NULL DEFAULT 1,
    cuisine TEXT NOT NULL DEFAULT '',
    course TEXT NOT NULL DEFAULT '',
    tags TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    difficulty TEXT NOT NULL DEFAULT '',
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    image_data BYTEA,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Sync fields
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ,
    -- Ownership (Step 5)
    owner_id UUID REFERENCES users(id)
);

-- Ingredients (aligned with iOS Ingredient model)
CREATE TABLE ingredients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    quantity DOUBLE PRECISION NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'Other',
    display_order INT NOT NULL DEFAULT 0,
    notes TEXT NOT NULL DEFAULT '',
    recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ
);

-- Grocery Lists (aligned with iOS GroceryList model)
CREATE TABLE grocery_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at TIMESTAMPTZ,
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ,
    owner_id UUID REFERENCES users(id)
);

-- Grocery Items (aligned with iOS GroceryItem model)
CREATE TABLE grocery_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    quantity DOUBLE PRECISION NOT NULL DEFAULT 1,
    unit TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'Other',
    is_checked BOOLEAN NOT NULL DEFAULT FALSE,
    source_recipe_name TEXT NOT NULL DEFAULT '',
    source_recipe_id TEXT NOT NULL DEFAULT '',
    grocery_list_id UUID NOT NULL REFERENCES grocery_lists(id) ON DELETE CASCADE,
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ
);

-- Shopping Templates (new — not in current server)
CREATE TABLE shopping_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    sort_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ,
    owner_id UUID REFERENCES users(id)
);

-- Template Items (new — not in current server)
CREATE TABLE template_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    quantity DOUBLE PRECISION NOT NULL DEFAULT 1,
    unit TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'Other',
    sort_order INT NOT NULL DEFAULT 0,
    template_id UUID NOT NULL REFERENCES shopping_templates(id) ON DELETE CASCADE,
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ
);

-- Pantry Items (new — for future use)
CREATE TABLE pantry_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL DEFAULT '',
    category TEXT NOT NULL DEFAULT 'Other',
    quantity INT NOT NULL DEFAULT 1,
    unit TEXT NOT NULL DEFAULT '',
    confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
    detection_source TEXT NOT NULL DEFAULT '',
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expiry_date TIMESTAMPTZ,
    notes TEXT NOT NULL DEFAULT '',
    cloudkit_record_name TEXT UNIQUE,
    sync_version INT NOT NULL DEFAULT 0,
    deleted_at TIMESTAMPTZ,
    owner_id UUID REFERENCES users(id)
);

-- Indexes
CREATE INDEX idx_ingredients_recipe ON ingredients(recipe_id);
CREATE INDEX idx_grocery_items_list ON grocery_items(grocery_list_id);
CREATE INDEX idx_template_items_template ON template_items(template_id);
CREATE INDEX idx_recipes_owner ON recipes(owner_id);
CREATE INDEX idx_grocery_lists_owner ON grocery_lists(owner_id);
CREATE INDEX idx_recipes_cloudkit ON recipes(cloudkit_record_name);
```

---

## 10. Hosting plan

### Free tier target (Steps 1-3)

| Component | Host | Cost | Notes |
|-----------|------|------|-------|
| Static recipe pages | GitHub Pages | $0 | Custom domain, HTTPS |
| FastAPI backend | Cloud Run | $0 | Scales to zero; 2M req/mo free |
| PostgreSQL | Neon free tier | $0 | 0.5 GB, scales to zero |
| React web app | Cloud Run (static) or Cloudflare Pages | $0 | Static SPA |
| CI/CD | GitHub Actions | $0 | 2000 min/mo free |

**Total: $0/month** for single-user volume.

### When costs appear

| Trigger | Service | Est. cost |
|---------|---------|-----------|
| Neon exceeds 0.5 GB | Upgrade Neon or move to Cloud SQL | $0-9/mo |
| AI job processing (cloud) | Gemini API | $5-20/mo |
| High traffic on static site | Unlikely to exceed free tier | $0 |
| Multiple active users | Cloud Run compute | Still $0 at <2M req/mo |

### PostgreSQL: why Neon over Cloud SQL

- **Neon**: Serverless Postgres, scales to zero, 0.5 GB free tier. Perfect
  for a single-household app where the DB is idle 99% of the time.
- **Cloud SQL**: Always-on, minimum $7/month even when idle. Better for
  production workloads but overkill for Steps 1-3.
- **Migration path**: When/if Neon's free tier is outgrown, migrate to
  Cloud SQL with `pg_dump`/`pg_restore`. No code changes — just a
  connection string swap.

---

## 11. Architecture diagram

```
                    ┌─────────────────────────────────────────────┐
                    │              USER DEVICES                   │
                    │                                             │
                    │   Nick's iPhone        Anna's iPhone        │
                    │   ┌──────────┐        ┌──────────┐         │
                    │   │ iOS App  │        │ iOS App  │         │
                    │   │ SwiftData│        │ SwiftData│         │
                    │   │ CloudKit │        │ CloudKit │         │
                    │   │ CoreML   │        │ (shared  │         │
                    │   │ VisionKit│        │  zone)   │         │
                    │   └────┬─────┘        └────┬─────┘         │
                    │        │                   │                │
                    └────────┼───────────────────┼────────────────┘
                             │                   │
      ┌──────────────────────┼───────────────────┼──────────────────────┐
      │                      │      APPLE        │                      │
      │              ┌───────┴───────────────────┴────────┐             │
      │              │     CloudKit Private DB             │             │
      │              │     (Nick's iCloud account)         │             │
      │              │     + Shared Zone (Anna)            │             │
      │              └───────────────┬─────────────────────┘             │
      └──────────────────────────────┼──────────────────────────────────┘
                                     │
                            CloudKit Web Services API
                            (server-to-server key)
                                     │
      ┌──────────────────────────────┼──────────────────────────────────┐
      │                     BACKEND  │  (Cloud Run, free tier)          │
      │                              │                                  │
      │              ┌───────────────┴───────────────┐                  │
      │              │         Sync Bridge           │                  │
      │              │  (CloudKit ↔ PostgreSQL)      │                  │
      │              │  Runs every 5 min via         │                  │
      │              │  Cloud Scheduler              │                  │
      │              └───────────────┬───────────────┘                  │
      │                              │                                  │
      │              ┌───────────────┴───────────────┐                  │
      │              │         FastAPI               │                  │
      │              │  /api/v1/recipes              │                  │
      │              │  /api/v1/grocery-lists        │                  │
      │              │  /api/v1/templates            │                  │
      │              │  /api/v1/jobs                 │                  │
      │              │  /api/v1/auth                 │                  │
      │              │  /api/v1/shares               │                  │
      │              └──────┬──────────┬─────────────┘                  │
      │                     │          │                                │
      │              ┌──────┴──┐  ┌────┴──────────┐                     │
      │              │Neon PG  │  │ Jobs Table    │                     │
      │              │(free)   │  │ (in same PG)  │                     │
      │              └─────────┘  └────┬──────────┘                     │
      │                                │                                │
      └────────────────────────────────┼────────────────────────────────┘
                                       │
                              Job polling (30s)
                                       │
      ┌────────────────────────────────┼────────────────────────────────┐
      │              AI WORKERS        │                                │
      │                                │                                │
      │    ┌───────────────────────────┴─────────┐                      │
      │    │                                     │                      │
      │    ▼                                     ▼                      │
      │  ┌──────────────┐              ┌──────────────────┐             │
      │  │ Pi 5 AI Hat  │              │ Cloud API        │             │
      │  │ (local LAN)  │              │ (Gemini/Claude)  │             │
      │  │              │              │                  │             │
      │  │ • Pantry     │              │ • Fallback for   │             │
      │  │   detection  │              │   Pi failures    │             │
      │  │ • Recipe Q&A │              │ • Real-time      │             │
      │  │ • OCR assist │              │   requests       │             │
      │  │ • Batch jobs │              │ • Complex scenes │             │
      │  └──────────────┘              └──────────────────┘             │
      │                                                                │
      └────────────────────────────────────────────────────────────────┘

      ┌────────────────────────────────────────────────────────────────┐
      │              WEB CLIENTS                                       │
      │                                                                │
      │    Nick's laptop          Lizzii's laptop      Friends         │
      │   ┌──────────────┐      ┌──────────────┐    ┌─────────────┐   │
      │   │ Web Editor   │      │ Web Editor   │    │ Public Page  │   │
      │   │ (React SPA)  │      │ (React SPA)  │    │ (static     │   │
      │   │              │      │              │    │  HTML on     │   │
      │   │ Auth: Google │      │ Auth: Google │    │  GitHub      │   │
      │   │ or Apple     │      │              │    │  Pages)      │   │
      │   └──────┬───────┘      └──────┬───────┘    └─────────────┘   │
      │          │                     │                   │           │
      │          └─────────┬───────────┘                   │           │
      │                    │                               │           │
      │              FastAPI REST API              No auth required    │
      │                                                                │
      └────────────────────────────────────────────────────────────────┘
```

### Data flow summary

```
On-device flows (unchanged):
  Camera → VisionKit OCR → SharedLogic parsers → SwiftData → CloudKit
  Camera → CoreML classifier → SwiftData → CloudKit
  These NEVER touch the web server.

Web editor flow:
  Browser → React SPA → FastAPI → PostgreSQL
  Sync bridge → CloudKit (appears on iPhone within 5 min)

Shared shopping flow:
  Anna adds "Milk" on her iPhone → CloudKit shared zone
  → Nick's iPhone sees it instantly (CloudKit push)
  → Sync bridge writes to PostgreSQL (within 5 min)
  → Web view updates on next poll

AI processing flow:
  User requests scan/Q&A → FastAPI → jobs table
  Pi 5 worker picks up job → runs inference → writes result
  Client polls for result → displays answer

Recipe sharing flow:
  Nick taps "Share" → static HTML generated → GitHub Pages
  Friend opens URL → reads recipe in browser (no account needed)
```

---

## 12. Lessons learned applied

### From recipe app development

| Lesson | How it's applied |
|--------|-----------------|
| **Persistent signing identities** — never regenerate on every build | Server secrets (API keys, DB credentials) are stored once in Cloud Run environment, never rotated automatically |
| **Don't guess at CI fixes** — add diagnostics first | Sync bridge logs every operation to a `sync_log` table; debug before fixing |
| **Batch pushes to conserve build minutes** | Cloud Run deploys are batched; GitHub Actions CI runs on PR merge only |
| **Schema drift is real** — iOS evolved past the server | Step 2 begins with a schema alignment task; Alembic migrations track all changes |
| **Test on real data** — mocks hide real bugs | Sync bridge tests use a real Neon database, not SQLite in-memory |
| **Content-based classification beats structural analysis** | Web recipe importer reuses the same JSON-LD extraction, not custom HTML parsing |
| **Compound overrides are fragile** — "powder" caught everything | API validation uses explicit allowlists, not broad pattern matches |

### From Good Morning dashboard

| Lesson | How it's applied |
|--------|-----------------|
| **Django + React is proven** | Same stack pattern: Python backend + React frontend |
| **Pi deployment works** | Pi 5 worker reuses the same deploy pattern (scp + swap) |
| **PostgreSQL on Pi works** | Pi already runs PG 15; worker can use local PG or connect to Neon |
| **Background jobs (APScheduler) work** | Job queue uses the same polling pattern |

### Architecture principles

| Principle | Implementation |
|-----------|---------------|
| **No single point of failure** | iOS app works without server; server works without Pi |
| **Additive, not replacing** | Web features add to iOS; they never replace on-device flows |
| **Schema as source of truth** | iOS SwiftData models are canonical; server mirrors them |
| **Soft deletes everywhere** | `deleted_at` on all synced tables; purge after 30 days |
| **Observability** | Sync log table, job status table, structured logging |
| **Cost ceiling** | Free tier everything; paid features behind experiment flags |

---

## 13. Open questions

### Must resolve before implementation

1. **CloudKit server-to-server API**: Can we reliably read/write SwiftData-
   backed CloudKit records from Python? The `CD_` field name prefix and
   SwiftData's internal record structure need empirical testing. If this
   doesn't work, fallback is iOS-initiated sync via the REST API.

2. **Neon free tier limits**: 0.5 GB storage, 100 hours compute/month.
   Is this enough for recipe data + images? Recipe images (JPEG, ~200KB
   each) could fill 0.5 GB with ~2,500 recipes. If image storage is a
   concern, store images in Cloud Storage (5 GB free) and keep only URLs
   in PostgreSQL.

3. **CloudKit shared zones vs. web-based sharing**: For Nick + Anna (both
   iPhone), CloudKit CKShare is simpler. But if web access is also needed,
   the PostgreSQL `shares` table is the single source of truth. Should we
   use both, or pick one?

### Can defer

4. **Real-time updates**: Polling is fine for v1. WebSockets or SSE can
   be added later if the 30-second delay on shopping list updates is
   annoying during a shared shopping trip.

5. **Offline web editor**: The React SPA could use a service worker for
   offline support. Not needed for v1.

6. **Recipe versioning**: Track edit history for recipes? Useful if Lizzii
   and Nick both edit the same recipe. Defer to after Step 5.

---

## 14. Active bugs and features summary

### Open backlog (Linear)

| ID | Title | Relevant to web? |
|----|-------|-------------------|
| **GM-2** | `--dry-run` for destructive scripts | No — tooling only |
| **GM-3** | Web interface + multi-user + Google auth | **Yes — this proposal** |

### Closed issues (for reference — all Done)

GM-4 through GM-19: all completed as of 2026-04-19. Key ones that
inform web architecture:

- **GM-9** (Import from URL): JSON-LD extraction works on-device; can be
  reused server-side for web recipe import
- **GM-16** (Grocery categorizer): Spices category + priority system
  implemented; the categorizer runs in SharedLogic (pure Swift) and would
  need a Python port for server-side categorization
- **GM-13** (Headerless cookbook scanning): Content-based section detection;
  informs how server-side OCR processing should work

### BACKLOG.md items relevant to web

| Item | Web dependency | Step |
|------|---------------|------|
| Backend sync server | Core of Steps 2-3 | 2-3 |
| Shared shopping lists | Requires auth + multi-user | 5 |
| Recipe voting / meal ideas | Requires shared + voting model | 5+ |
| Meal planning + calendar | Web editor feature | 2+ |
| Recipe ↔ pantry integration | AI tier could enhance matching | 8 |
| Cloud vision fallback | Job queue + AI workers | 8 |
| Receipt scanning / price tracking | Job queue + OCR | 8 |
| Post-OCR text correction | Could use AI worker for hard cases | 8 |

### Features that stay on-device (no web needed)

- Camera OCR pipeline (VisionKit + SharedLogic parsers)
- CoreML food classification
- Barcode scanning + Open Food Facts
- GroceryCategorizer keyword matching
- Shopping template stamping
- All current UI flows

---

## Appendix: Implementation order

```
Step 1: Shareable recipe links ──────────── 1-2 sessions, $0/mo
  └─ Static HTML generation
  └─ GitHub Pages deploy
  └─ Share action in iOS app

Step 2: Web recipe editor ───────────────── 2-3 sessions, $0/mo
  └─ Align server schema with iOS
  └─ FastAPI endpoints (full CRUD)
  └─ React SPA (recipe form)
  └─ Neon PostgreSQL (free tier)
  └─ Cloud Run deploy
  └─ Temporary API key auth

Step 3: Sync bridge ─────────────────────── 3-4 sessions, $0/mo
  └─ CloudKit server-to-server investigation
  └─ Bidirectional sync logic
  └─ Conflict resolution (last-write-wins + log)
  └─ Cloud Scheduler (5-min cron)

Step 5: Auth + multi-user ───────────────── 2-3 sessions, $0/mo
  └─ Google OAuth + Sign in with Apple
  └─ User model + ownership
  └─ Shared shopping lists
  └─ Recipe voting

Step 4/6+: AI processing tier ───────────── 1-2 sessions, $0-20/mo
  └─ Job queue table in PostgreSQL
  └─ Pi 5 AI Hat worker
  └─ Cloud API fallback (behind flag)
  └─ Pantry detection, recipe Q&A, etc.
```

Total estimated effort: 10-14 sessions across all steps.
Total monthly cost at completion: $0 (free tier) to $20 (with AI flag on).

---

## Appendix: Step 1 implementation log

### Completed 2026-04-19

**DNS**: CNAME record added in Squarespace:
- Type: CNAME, Name: `recipes`, Data: `seanick80.github.io`
- Maps `recipes.ouryearofwander.com` → GitHub Pages

**GitHub Pages**: `gh-pages` branch created (orphan) on `seanick80/recipe-app`.
Settings → Pages → Deploy from branch `gh-pages` / root.
HTTPS enforced (GitHub provisions Let's Encrypt cert automatically).

**Static site generator**: `scripts/publish-recipes.py`
- Reads recipe JSON files from `data/published-recipes/*.json`
- Generates standalone HTML pages with:
  - Embedded JSON-LD (`schema.org/Recipe`) for SEO + rich link previews
  - Open Graph meta tags for iMessage/WhatsApp/social link previews
  - Dark mode support (prefers-color-scheme)
  - Print-friendly CSS
  - Mobile-responsive layout
  - Unicode fraction rendering (1.5 → "1 ½")
- URL structure: `/{username}/{slug}/` (e.g., `/seanick/marathon-chicken-bake/`)
- Outputs to `build/gh-pages/` (gitignored)
- Per-recipe `"published": true` toggle — only published recipes generate pages

**GitHub Action**: `.github/workflows/publish-recipes.yml`
- Triggers on push to master when `data/published-recipes/` or the generator
  script changes
- Also supports manual trigger (`workflow_dispatch`)
- Uses `peaceiris/actions-gh-pages@v4` to deploy generated HTML to `gh-pages`

**Recipe JSON format** (in `data/published-recipes/`):
```json
{
  "title": "Recipe Name",
  "summary": "Short description",
  "servings": 4,
  "prepTimeMinutes": 20,
  "cookTimeMinutes": 45,
  "cuisine": "Italian",
  "course": "Main",
  "difficulty": "Easy",
  "sourceURL": "",
  "ingredients": [
    {"name": "Chicken", "quantity": 1.5, "unit": "kg"}
  ],
  "instructions": [
    "Step 1 text.",
    "Step 2 text."
  ],
  "published": true,
  "publishedBy": "seanick"
}
```

**Remaining Step 1 work**:
- Verify DNS propagation and HTTPS
- Remove example recipe JSON, add real recipes
- Add iOS "Share Recipe" action that generates the public URL
  (recipe data is already on-device; sharing = copy URL to clipboard
  with the slug format, assuming the recipe has been published via
  a JSON export mechanism TBD)
- Consider: script/action to export recipe from iOS SwiftData → JSON
  file in `data/published-recipes/` (may need GitHub API or manual copy)
