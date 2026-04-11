# Recipe App

## Project Structure
- `RecipeApp/` — SwiftUI iOS app (MVVM + SwiftData + CloudKit)
  - `project.yml` — xcodegen config (source of truth; `.xcodeproj` is generated and gitignored)
  - `RecipeApp/RecipeApp.entitlements` — CloudKit service + container identifier
- `Models/` — Pure Swift models compilable on Windows (for local testing)
- `server/` — Python FastAPI backend (future sync; not needed for single-user persistence)
- `database/` — SQL schema and seed data

## iOS App
- Architecture: MVVM with SwiftData for persistence
- **Persistence**: SwiftData backed by CloudKit private database (`iCloud.com.seanick80.recipeapp`).
  All `@Model` classes must keep CloudKit constraints: every stored property defaulted
  or optional, relationships optional with explicit `inverse:`, no `@Attribute(.unique)`.
- **Build system**: xcodegen. `RecipeApp.xcodeproj` is generated from `RecipeApp/project.yml`
  on the Codemagic Mac runner at build time — do NOT check the `.xcodeproj` into git.
- **Signing**: Codemagic automatic signing via App Store Connect API key
  (`recipe-app-appstore-key`) tied to Team `3JR8WTJUV6`.
- **Build pipeline**: Push to GitHub `master` → Codemagic installs xcodegen, runs
  `xcodegen generate`, then `xcode-project build-ipa` → signed IPA via email.
- Local testing: Pure Swift models in `Models/` can be compiled with `swiftc` on Windows.

## Identifiers (do not change casually)
- **Bundle ID**: `com.seanick80.recipeapp`
- **CloudKit container**: `iCloud.com.seanick80.recipeapp`
- **Apple Team ID**: `3JR8WTJUV6`
- **Codemagic integration name**: `recipe-app-appstore-key`

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

## Bug reporting workflow (Linear + GitHub)

When the user reports a bug — especially with `Bug:` prefix or phrases like
"I found a bug" / "there's a bug" / "when I do X, Y happens wrong" — follow
this workflow automatically without asking.

- **Linear team:** `Good Morning` (identifier `GM`, shared across all three sourcecode projects).
- **Label:** `recipeapp`
- **Title prefix:** `[RA]`
- **GitHub repo:** `seanick80/recipe-app` (default branch `master`)
- **MCP tool:** `mcp__linear__save_issue`

**Steps:**

1. Create Linear issue in the `Good Morning` team:
   - Title: `[RA] <short bug description>`
   - Description: repro steps, expected vs actual, error output
   - Label: `recipeapp`
2. Fix the bug.
3. Open PR via `gh pr create` against `seanick80/recipe-app`. The PR body MUST contain `Fixes GM-<N>` on its own line — this auto-closes the Linear issue on merge to `master`.
4. Report back with Linear issue URL and PR URL. Do NOT manually close the Linear issue.

**Do not** create Linear issues for feature requests or refactors — only bug reports. If the Linear MCP is unavailable, fall back to `gh issue create` and use `Fixes #<N>` instead.
