# Web Architecture — Implementation Log

## Status: Step 2 in progress (2026-04-20)

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

## In Progress

### Step 2e: React SPA (NEXT)
- Scaffold: Vite + React + TypeScript
- Reuse patterns from Good Morning dashboard:
  - CSS Modules for styling
  - React Query for data fetching
  - apiFetch wrapper for API calls
- Add React Router (Good Morning is single-page; recipe app needs routes)

#### Pages to build:
1. **Recipe list** (public) — search, filter by cuisine/course
2. **Recipe detail** (public) — read-only view, same design as static pages
3. **Recipe editor** (authenticated) — create/edit form with ingredient rows
4. **Login** — Google OAuth button, redirect flow
5. **Admin** (admin only) — invite users, manage allowlist

#### Auth flow in React:
1. Check `/api/v1/auth/me` on load
2. If not authenticated, show "Sign in with Google" → `/api/v1/auth/login`
3. After OAuth redirect, JWT cookie is set automatically
4. React Query refetch shows authenticated state
5. Editor pages gated behind auth check

#### API client needs:
- Typed fetch wrappers for all recipe/grocery/auth endpoints
- JWT cookie sent automatically (httpOnly, same-site)
- No CSRF needed (JWT in cookie, not session-based)

## Not Started

### Step 2f: Deploy FastAPI
- Options: Cloud Run (free tier), Render (free tier), Railway ($5 credit)
- Need to configure production OAuth redirect URI
- Need to set env vars on hosting platform

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
- Production callback URL TBD after deployment
