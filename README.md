# Recipe App

A full-stack recipe and grocery list iOS app with local-first architecture.

## Tech Stack

- **iOS Client**: SwiftUI + MVVM + SwiftData with CloudKit private database (on-device + iCloud sync)
- **Build System**: xcodegen (`RecipeApp.xcodeproj` generated on CI from `RecipeApp/project.yml`)
- **Web Editor**: React 19 + TypeScript + Vite (Google OAuth login, recipe CRUD)
- **Backend**: Python FastAPI + PostgreSQL on Neon (Google OAuth + JWT auth, API key for scripts)
- **Build Pipeline**: Windows dev -> GitHub -> Codemagic CI (xcodegen + App Store Connect API-key signing) -> TestFlight -> iPhone

## Features

### Recipes
- Create, edit, and delete recipes with ingredients, instructions, prep/cook time, and servings
- Import recipes from URLs via Share Extension (JSON-LD Schema.org parsing)
- Dual-unit normalization (e.g. "50 g / 3 1/2 tbsp" → keeps imperial)
- Ingredient text cleanup: double parens, leading commas, empty parens
- Search recipes by name, filter by cuisine/course/favorites
- Swipe to delete

### Grocery Lists
- Create grocery lists manually or generate from selected recipes
- Auto-categorization of items into store aisles (Produce, Dairy, Meat, etc.)
- Items organized by category with manual override via Edit
- Check/uncheck items with strikethrough
- Remove all checked items or uncheck all
- Ingredient consolidation when generating from multiple recipes

### Settings
- Opt-in improvement reporting: anonymous import normalization data sent
  to server to improve the import pipeline

## Project Structure

Full layout and rationale: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Unscheduled ideas and explicit not-plans: [`BACKLOG.md`](BACKLOG.md).

```
RecipeApp/          SwiftUI iOS app (MVVM + SwiftData)
SharedLogic/        Pure-Swift modules shipped into the iOS app (copied
                    into RecipeApp/RecipeApp/Parsers/ at CI build time)
TestFixtures/       Windows-only test suites exercising SharedLogic/
scripts/            build/test/lint + schema sync + layout-bench
server/             FastAPI backend (Neon PostgreSQL, Google OAuth, JWT)
frontend/           React SPA web editor (Vite + TypeScript)
schema/             Canonical data model definitions (canonical.yaml)
database/           PostgreSQL DDL and seed data
```

## Required Tools

Install these locally for full dev workflow (Mac-only tools run on Codemagic, not needed locally):

| Tool             | Required? | Install                                                          | Purpose                                            |
| ---------------- | --------- | ---------------------------------------------------------------- | -------------------------------------------------- |
| Swift toolchain  | yes       | https://www.swift.org/install/ (Swift 6.2+)                      | Compile + run pure-Swift `SharedLogic/` tests      |
| Python 3         | yes       | https://www.python.org/downloads/ (3.10+)                        | YAML/XML validation in lint, future backend work   |
| PyYAML           | yes       | `pip install pyyaml`                                             | Validates `project.yml` and `codemagic.yaml`       |
| `swift-format`   | yes       | Bundled with Swift toolchain on Windows; `brew install swift-format` on macOS | Lint Swift source code                |
| Git + Git Bash   | yes       | https://git-scm.com/download/win                                 | Version control, script host on Windows           |
| `gh` (GitHub CLI)| optional  | https://cli.github.com/                                          | Opening PRs / managing issues                      |
| `xcodegen`       | Mac only  | `brew install xcodegen`                                          | Generates `.xcodeproj` from `project.yml` on CI    |
| Xcode            | Mac only  | Mac App Store                                                    | Actual iOS build (runs on Codemagic)              |

**One-time setup after cloning:**

```bash
# Enable the repo's git hooks (pre-commit lint/test, pre-push full build)
git config core.hooksPath .githooks
```

## Development

### Canonical build entrypoint

**Always build/validate through `scripts/build.sh`.** Never duplicate flags or checks inline — if a new check is needed, add it to the script so it runs for everyone, every time.

```bash
./scripts/build.sh            # full: lint + tests + config validation + clean-tree check
./scripts/build.sh quick      # pre-commit mode: lint + tests only
./scripts/build.sh validate   # config validation only
```

### Individual scripts

```bash
./scripts/lint.sh             # swift-format + YAML/XML validation + CRLF detection
./scripts/test.sh             # pure-Swift SharedLogic/ + TestFixtures/ tests + (future) pytest
```

### Git hooks

Once `core.hooksPath` is set to `.githooks`, the hooks run automatically:

- **pre-commit** — runs `build.sh quick` (lint + lightweight tests)
- **pre-push**   — runs `build.sh full` (everything including clean-tree check)

Hooks can be bypassed in emergencies with `git commit --no-verify` but avoid making that a habit.

### Backend Server

```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload --port 8000   # http://localhost:8000/api/
```

Server logs are written to `server/logs/server.log` and `server/logs/audit.log` (auth events).

### Web Frontend

```bash
cd frontend
npm install && npm run dev              # http://localhost:5173
```

### Database

```bash
createdb recipe_app
psql recipe_app < database/init.sql
psql recipe_app < database/seed.sql
```

### Schema Sync

All data models are defined once in `schema/canonical.yaml` and verified across 7 surfaces (SQL, SQLAlchemy, Pydantic, TypeScript, SwiftData, TestFixtures, static site):

```bash
python scripts/test_schema_sync.py      # fails if any surface drifts
```

## Privacy & Debug Logging

This repo is currently a **debug build**. The Scan tab includes an on-device
debug log (Scanner tab → Debug → Debug Log) that records every scan's
intermediate pipeline output so problems can be diagnosed after the fact.

The log **contains the OCR text extracted from every photo you scan** — i.e.
whatever text appears in the ingredient lists, shopping lists, or
handwritten margin notes you photograph. The log is stored only on device
(`Documents/debug.jsonl`) and is never uploaded anywhere automatically.
You choose when to export + share it via the in-app Share Log File button.

**Improvement reporting** (opt-in via Settings): When enabled, anonymous
data about recipe import normalizations (e.g. ingredient formatting fixes)
is sent to the server endpoint `POST /api/v1/telemetry/import-normalizations`.
Any imported recipes that fail to import or require normalization may be
logged for app improvement. No personal data or recipe content is shared —
only the text transformations applied during import. This should be
disclosed in the privacy policy before public/App Store release.

This debug logging feature will be removed before any public release.

## Status

Shipping to TestFlight. Every push to `master` is built on Codemagic
with a persistent iOS Distribution identity, uploaded to App Store
Connect, and available to internal testers — no UDID registration or
OTA side-loading needed. v0.2.0 is the first TestFlight release
(2026-04-16).

Scanner tab supports shopping-list OCR, recipe OCR (with section-header
routing), barcode scanning, and pantry photo capture (CoreML Food-101
classifier). Multi-device CloudKit sync works against the user's
private iCloud zone.

See [`BACKLOG.md`](BACKLOG.md) for what's next and what's explicitly
out of scope.

## Recipe Sharing (GitHub Pages)

Published recipes are served as static HTML at
**[recipes.ouryearofwander.com](https://recipes.ouryearofwander.com)**.

### How it works

1. Add a recipe JSON file to `data/published-recipes/` with `"published": true`
2. Push to `master`
3. GitHub Action runs `scripts/publish-recipes.py` to generate static HTML
4. Action deploys to the `gh-pages` branch automatically
5. Recipe is live at `recipes.ouryearofwander.com/seanick/<recipe-slug>`

### Publishing a recipe manually

```bash
# Generate the static site locally (outputs to build/gh-pages/)
python scripts/publish-recipes.py

# Preview: open build/gh-pages/seanick/<recipe-slug>/index.html in a browser
```

### Recipe JSON format

See `data/published-recipes/example-marathon-chicken-bake.json` for the
full schema. Key fields: `title`, `ingredients`, `instructions`,
`published` (boolean toggle), `publishedBy` (username for URL path).

### Architecture

- **DNS**: CNAME `recipes` → `seanick80.github.io` (via Squarespace)
- **Hosting**: GitHub Pages on `gh-pages` branch (free, HTTPS)
- **Generator**: Pure Python, no dependencies (`scripts/publish-recipes.py`)
- **CI**: GitHub Action triggers on changes to `data/published-recipes/`
- **Design doc**: [`docs/WEB_ARCHITECTURE_PROPOSAL.md`](docs/WEB_ARCHITECTURE_PROPOSAL.md)
