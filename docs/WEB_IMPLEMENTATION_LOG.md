# Web Architecture — Implementation Log

## Status: Step 2f done, Step 3 next (2026-04-21)

## Completed

### Step 1: Shareable Recipe Links (DONE)
- GitHub Pages deployed at `recipes.ouryearofwander.com`
- DNS: CNAME record in Wix (nameservers are Wix, not Squarespace)
- Static page generator: `scripts/publish-recipes.py`
- Auto-deploy: `.github/workflows/publish-recipes.yml`
- Example recipe live: Marathon Chicken Bake
- HTTPS enabled

### Step 2a: Server Schema Alignment (DONE)
- All SQLAlchemy models aligned with iOS SwiftData
- Recipe: +cuisine, course, tags, difficulty, source_url, is_favorite, is_published
- Ingredient: quantity Float (was String), +category, display_order, notes
- Grocery: +archive support, source recipe tracking
- Shopping templates: full CRUD
- 23 server tests passing

### Step 2b: Neon PostgreSQL (DONE)
- Free tier provisioned: `ep-wild-forest-akzmdyu2.c-3.us-west-2.aws.neon.tech`
- Connection string in `server/.env` and `secrets/neon.env`
- All 7 tables created, schema matches SQLAlchemy models
- SSL enforced via `sslmode=require`
- Smoke test: full CRUD verified against live Neon

### Step 2c: API Security Hardening (DONE)
- API key auth on mutation endpoints (X-API-Key header)
- Rate limiting: 30/min mutations, 120/min reads (slowapi)
- Input validation: Field constraints on all schemas
- Typed PATCH models (no more raw dict)
- Global exception handler
- CORS tightened (explicit methods/headers)
- 25 tests passing

### Step 2d: Google OAuth + JWT Auth (DONE)
- Google OAuth login flow: login → Google → callback → JWT cookie
- Same GCP project as Good Morning dashboard (972511622379)
- New OAuth client ID for recipe app
- Dual auth: JWT cookie (browser) + API key (scripts)
- AllowedUser model with roles: admin, editor, viewer
- Email allowlist with invite mechanism
- Nick seeded as admin (seanickharlson@gmail.com)
- Auth endpoints: login, callback, me, logout, invite, list users, delete user
- 35 tests passing (8 auth + 15 recipe + 12 grocery)

### Codemagic Build Filter (DONE)
- `when.changeset.includes` filters: only RecipeApp/, SharedLogic/, codemagic.yaml
- `cancel_previous_builds: true` saves free-tier minutes
- Server-only changes no longer trigger iOS builds

### Step 2e: React SPA (DONE)
- Vite + React 19 + TypeScript + CSS Modules
- Pages: recipe list, recipe detail, recipe editor, login
- Google OAuth sign-in via JWT cookie
- Typed fetch wrappers for recipe/auth endpoints
- Tested end-to-end: OAuth login → create recipe → view recipe

### Server Logging (DONE)
- `server/logs/server.log` — all INFO+ messages (uvicorn access, errors, audit)
- `server/logs/audit.log` — auth/security events only (login, denied, rate limit)
- RotatingFileHandler (5 MB, 3–5 backups)
- dictConfig-based so uvicorn doesn't clobber handlers

### Schema Sync Test (DONE)
- `schema/canonical.yaml` — single source of truth for 6 models across 7 surfaces
- `scripts/test_schema_sync.py` — parses SQL, SQLAlchemy, Pydantic, TypeScript, SwiftData, TestFixtures, static site
- Fixed drift: iOS Recipe +isPublished, TestFixtures IngredientModel +category, GroceryListModel +archivedAt
- Wired into `scripts/build.sh`

### Step 2f: Deploy FastAPI (DONE)
- Deployed to Google Cloud Run: `https://recipe-api-972511622379.us-west1.run.app`
- Project: `good-morning-dashboard-491709`, region `us-west1`
- Billing: `NicksMain` account (`0158E3-E1666C-7EB9CA`)
- min-instances=0 (scales to zero), max-instances=1, 256Mi memory
- Env vars set: DATABASE_URL, API_KEY, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, JWT_SECRET, OAUTH_REDIRECT_URI, FRONTEND_URL
- Health check verified: `/health` returns 200
- API tested: recipes endpoint returns live data from Neon
- Dockerfile + .dockerignore added to `server/`
- Frontend `client.ts` updated: `VITE_API_URL` env var for production base URL
- gcloud CLI installed locally (`/c/Program Files (x86)/Google/Cloud SDK/`)

**GCP Console action required:** Add production OAuth redirect URI:
`https://recipe-api-972511622379.us-west1.run.app/api/v1/auth/callback`

## Not Started

### Step 3: Sync Bridge
- CloudKit server-to-server API
- Bidirectional sync: iOS ↔ PostgreSQL
- Conflict resolution strategy TBD

### Step 5: Multi-user
- Anna: shared shopping lists, recipe voting
- Lizzii: web editor access (invite mechanism ready)
- Sign in with Apple for iOS users

## Secrets Reference

| Secret | Location | Purpose |
|--------|----------|---------|
| Neon connection string | `secrets/neon.env`, `server/.env` | PostgreSQL database |
| API key | `secrets/api_key.txt`, `server/.env` | Machine-to-machine auth |
| Google OAuth client ID | `secrets/google_oauth.env`, `server/.env` | OAuth login |
| Google OAuth client secret | `secrets/google_oauth.env`, `server/.env` | OAuth login |
| JWT secret | `server/.env` | Session tokens |

## GCP Console Action Required

Before testing OAuth end-to-end, add this redirect URI in the GCP Console
(APIs & Services → Credentials → OAuth 2.0 Client ID for recipe app):
- `http://localhost:8000/api/v1/auth/callback` (dev)
- `https://recipe-api-972511622379.us-west1.run.app/api/v1/auth/callback` (production)
