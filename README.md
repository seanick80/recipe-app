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
Models/             Pure Swift models + tests (compilable on Windows)
server/             Python FastAPI backend
database/           PostgreSQL schema and seed data
```

## Development

### Pure Swift Model Tests (Windows)

```
cmd.exe /c "swiftc Models\Recipe.swift Models\GroceryItem.swift Models\TestModels.swift -o test.exe"
test.exe
```

Note: `swiftc` must be invoked via `cmd.exe` on Windows — Git Bash silently fails.

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
