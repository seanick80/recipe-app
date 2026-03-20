# Recipe App — Staged Work Plan

## Overview

Full-stack recipe & grocery list iOS app with local-first architecture.
- **iOS client**: SwiftUI + MVVM + SwiftData (on-device persistence)
- **Backend**: Python FastAPI + PostgreSQL (for future sync)
- **Build pipeline**: Windows → GitHub → Codemagic → iPhone (OTA install)

---

## Phase 1: Local-Only iOS App (Recipe Storage + Grocery Lists)
**Status**: Boilerplate created

### Milestone 1A: Environment Setup
- [ ] Install Swift toolchain on Windows (swift.org/install, Swift 6.x)
- [ ] Verify `swiftc --version` works
- [ ] Install VS Code Swift extension (sswg.swift-lang) + C/C++ extension
- [ ] Create GitHub repo (`recipe-app`, private)
- [ ] `git init` and push initial boilerplate

### Milestone 1B: Pure Swift Model Validation (Windows)
- [ ] Compile and run `Models/TestModels.swift` on Windows with `swiftc`
- [ ] Validate Codable round-trips for Recipe and GroceryItem models
- [ ] Iterate on model design until tests pass cleanly

### Milestone 1C: SwiftUI Views — Recipes
- [ ] Recipe list with search and empty state
- [ ] Recipe detail view (ingredients, instructions, time/servings)
- [ ] Recipe create/edit form with ingredient rows
- [ ] Delete recipes with swipe

### Milestone 1D: SwiftUI Views — Grocery Lists
- [ ] Grocery list overview (list of lists with completion counts)
- [ ] Grocery list detail with categorized items
- [ ] Add item form with category picker
- [ ] Check/uncheck items, remove checked items
- [ ] Generate grocery list from selected recipes (consolidate ingredients)

### Milestone 1E: First Build & Install
- [ ] Enroll in Apple Developer Program ($99/year)
- [ ] Create Codemagic account (free tier, 500 min/mo)
- [ ] Connect GitHub repo to Codemagic
- [ ] Configure code signing (Apple ID + Team ID + UDID)
- [ ] Generate Xcode project (via Codemagic or Swift Package Manager)
- [ ] Trigger first build, install on iPhone via OTA link

---

## Phase 2: Backend Server + Database
**Depends on**: Phase 1 complete

### Milestone 2A: PostgreSQL Setup
- [ ] Install PostgreSQL locally
- [ ] Create `recipe_app` database
- [ ] Run `database/init.sql` schema
- [ ] Load `database/seed.sql` sample data

### Milestone 2B: FastAPI Server
- [ ] Set up Python venv, install requirements
- [ ] Verify `uvicorn main:app --reload` starts
- [ ] Test all CRUD endpoints with `pytest` (SQLite in-memory)
- [ ] Test against real PostgreSQL
- [ ] Verify API docs at `/docs` (Swagger UI)

### Milestone 2C: iOS ↔ Server Sync (Future)
- [ ] APIClient connects to local server
- [ ] Pull recipes from server into SwiftData
- [ ] Push local changes to server
- [ ] Conflict resolution strategy (last-write-wins to start)

---

## Phase 3: Meal Planning & Calendar
**Depends on**: Phase 1

### Milestone 3A: Meal Plan Model
- [ ] MealPlan SwiftData model (date + meal type + recipe reference)
- [ ] Weekly calendar view showing planned meals
- [ ] Drag/drop or tap to assign recipes to days

### Milestone 3B: Calendar Integration
- [ ] EventKit integration for local iOS calendar
- [ ] TBD: Google Calendar vs Apple Calendar (evaluate Gmail dependency)
- [ ] Show meal plan events in system calendar

---

## Phase 4: Pantry & Camera Features
**Depends on**: Phase 1

### Milestone 4A: Pantry Inventory
- [ ] PantryItem SwiftData model
- [ ] Pantry list view with categories and quantities
- [ ] Smart shopping: compare pantry to recipe ingredients, suggest what to buy

### Milestone 4B: Camera — Pantry Scan
- [ ] Camera view to photograph pantry/fridge
- [ ] (Future) Vision/ML integration to identify items from photos
- [ ] Manual tagging of items from photo

### Milestone 4C: Camera — Meal Photo
- [ ] Capture photo of cooked meal
- [ ] Attach photo to recipe as "cooked on" entry
- [ ] Photo gallery per recipe

---

## Phase 5: Spouse Voting & Sharing
**Depends on**: Phase 2 (needs server)

### Milestone 5A: Menu Voting
- [ ] Weekly menu proposal (top 3-5 recipe suggestions)
- [ ] Voting UI: thumbs up/down or rank ordering
- [ ] Both spouses see same proposals, votes sync via server
- [ ] Final menu based on combined votes

### Milestone 5B: Google Account Support
- [ ] Google Sign-In integration
- [ ] Link local data to authenticated account
- [ ] Sync data across devices via server

---

## Phase 6: Polish & Portfolio
**Depends on**: Phases 1-5 (incremental)

### Milestone 6A: UI Polish
- [ ] App icon and launch screen
- [ ] Dark mode support
- [ ] Haptic feedback on interactions
- [ ] Accessibility labels

### Milestone 6B: Interview Readiness (per PDF Section 8)
- [ ] Clean `Models/` folder with pure Swift (compilable on Windows)
- [ ] Swift-idiomatic patterns: structs, Codable, Hashable, guard/if-let
- [ ] Architecture comments explaining MVVM, data flow, state management
- [ ] Descriptive commit history
- [ ] README with screenshots and tech choices

### Milestone 6C: Optional Cloud Emulator
- [ ] Appetize.io or Browserstack for browser-based preview
- [ ] Shareable link for hiring managers

---

## Development Workflow (Day-to-Day)

Per the iOS dev guide (Sections 7):

1. Open project in VS Code
2. Use Claude Code to write/modify Swift and SwiftUI files
3. Review code — VS Code Swift extension highlights syntax errors
4. Test pure Swift logic locally: `swiftc Models/*.swift -o test.exe && ./test.exe`
5. Commit and push to GitHub
6. Codemagic auto-builds on push (5-15 min)
7. Install via OTA link on iPhone

## Current Focus

**Phase 1** — Get the local-only Recipe + Grocery app working and installed on device.
Start with Milestone 1A (environment setup) and 1B (model validation on Windows).
