# Recipe App

A full-stack recipe and grocery list iOS app with local-first architecture.

## Tech Stack

- **iOS Client**: SwiftUI + MVVM + SwiftData with CloudKit private database (on-device + iCloud sync)
- **Build System**: xcodegen (`RecipeApp.xcodeproj` generated on CI from `RecipeApp/project.yml`)
- **Backend**: Python FastAPI + PostgreSQL (future sync for cross-household features; CloudKit handles single-user persistence today)
- **Build Pipeline**: Windows dev -> GitHub -> Codemagic CI (xcodegen + App Store Connect API-key signing) -> iPhone (OTA install)

## Features

### Recipes
- Create, edit, and delete recipes with ingredients, instructions, prep/cook time, and servings
- Search recipes by name
- Swipe to delete

### Grocery Lists
- Create grocery lists manually or generate from selected recipes
- Items organized by category (Produce, Dairy, Meat, etc.)
- Check/uncheck items with strikethrough
- Remove all checked items or uncheck all
- Ingredient consolidation when generating from multiple recipes

## Project Structure

```
RecipeApp/          SwiftUI iOS app (MVVM + SwiftData)
  RecipeApp/
    Models/         SwiftData models (Recipe, Ingredient, GroceryList, GroceryItem)
    Views/          SwiftUI views organized by feature
    ViewModels/     Observable view models
    Services/       API client and local storage (future use)
SharedLogic/        Pure-Swift modules shipped into the iOS app (copied into
                    RecipeApp/RecipeApp/Parsers/ at CI build time)
TestFixtures/       Windows-only mirrors of SwiftData types + Test*.swift
                    suites exercising SharedLogic/ code
server/             Python FastAPI backend
database/           PostgreSQL schema and seed data
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
uvicorn main:app --reload
```

### Database

```bash
createdb recipe_app
psql recipe_app < database/init.sql
psql recipe_app < database/seed.sql
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

This feature will be removed before any public/App Store release.

## Status

- [x] Phase 1A: Environment setup + GitHub repo
- [x] Phase 1B: Pure Swift model validation on Windows
- [x] Phase 1C: SwiftUI Recipe views (list, detail, edit)
- [x] Phase 1D: SwiftUI Grocery views (lists, items, generate from recipes)
- [~] Phase 1E: Apple Developer Program + Codemagic CI + CloudKit + first device build (in progress — awaiting UDID registration)
- [ ] Phase 2: Backend server + database
- [ ] Phase 3: Meal planning + calendar
- [ ] Phase 4: Pantry + camera features
- [ ] Phase 5: Spouse voting + sharing
