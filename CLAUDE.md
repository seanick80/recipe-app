# Recipe App

## Project Structure
- `RecipeApp/` — SwiftUI iOS app (MVVM + SwiftData, local-first)
- `Models/` — Pure Swift models compilable on Windows (for local testing)
- `server/` — Python FastAPI backend with PostgreSQL
- `database/` — SQL schema and seed data

## iOS App
- Architecture: MVVM with SwiftData for persistence
- Build: Push to GitHub -> Codemagic builds on cloud Mac -> OTA install to iPhone
- Local testing: Pure Swift models in `Models/` can be compiled with `swiftc` on Windows

## Backend Server
```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload
```

## Database
```bash
# Create PostgreSQL database
createdb recipe_app
psql recipe_app < database/init.sql
psql recipe_app < database/seed.sql
```

## Testing
```bash
# Swift models (Windows)
swiftc Models/Recipe.swift Models/GroceryItem.swift Models/TestModels.swift -o test.exe && ./test.exe

# Python server
cd server && pytest
```
