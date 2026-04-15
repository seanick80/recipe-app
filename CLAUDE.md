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

## Identifiers (do not change casually; all safe to commit)
- **Bundle ID**: `com.seanick80.recipeapp`
- **CloudKit container**: `iCloud.com.seanick80.recipeapp`
- **Apple Team ID**: `3JR8WTJUV6`
- **Codemagic integration name**: `recipe-app-appstore-key`

## Build & validation conventions

**All build/validation goes through `scripts/build.sh`.** Never add one-off
flags, checks, or build steps inline to commits or CI — add them to the
script so they run for every developer and every push. Reasons:

- Single source of truth for "what a build means here"
- CI (Codemagic) and local `git push` both enforce the same checks
- Prevents the classic "it passes on my machine, fails in prod" drift

Modes:
- `./scripts/build.sh`          → full: lint + tests + config validation + clean tree
- `./scripts/build.sh quick`    → pre-commit: lint + tests only
- `./scripts/build.sh validate` → config validation only

Supporting scripts: `scripts/lint.sh`, `scripts/test.sh`.

Git hooks in `.githooks/` are auto-installed per-clone with
`git config core.hooksPath .githooks`. They enforce:
- pre-commit: `build.sh quick`
- pre-push:   `build.sh full`

## Line endings and encoding (MANDATORY)

- All text files in this repo are **LF only**, enforced via `.gitattributes`
  and `.editorconfig`.
- When writing ANY file in this project, Claude MUST use LF line endings.
  The Write tool respects literal newline characters — do not emit `\r\n`.
- If you touch a file and see a CRLF warning from git, run
  `git add --renormalize .` and investigate why it wasn't caught by
  `.gitattributes` (likely a new extension that needs adding there).

## Swift formatting

- `.swift-format` in the repo root is the canonical formatter config
  (4-space indent, 120-col lines, ordered imports).
- Run `swift-format format -i -r --configuration .swift-format Models RecipeApp/RecipeApp`
  to autofix; `./scripts/lint.sh` runs `--mode lint` in CI.

## Secrets policy

Safe to commit (all are effectively public): Team ID, bundle ID, CloudKit
container identifier, Codemagic integration name.

NEVER commit: `.p8` files, `.p12` files, private keys, mobileprovision
files, Apple ID passwords, CloudKit server-to-server tokens, Issuer ID +
Key ID pairs for App Store Connect API keys. If any of these are ever
added by mistake, stop and ask — do not just `git rm` because they may
already be in the remote history.

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
# All tests (Windows) — 388 tests across 8 suites
./scripts/test.sh

# Full build validation (lint + tests + config)
./scripts/build.sh

# Python server
cd server && pytest
```

Pure Swift test suites in `Models/`: Recipe (42), Shopping (63), ListParser (57),
OCR (45), Detection (26), Barcode (22), Pantry (34), GroceryCategorizer (99).

XCTests in `RecipeAppTests/` run on Codemagic simulator before archive:
- `RecipeModelTests.swift` — SwiftData model init + toggle
- `ShoppingTemplateTests.swift` — SwiftData template + archive + category
- `MLModelTests.swift` — validates FoodClassifier.mlpackage presence + size bounds;
  uses `XCTSkipUnless` so the suite gracefully skips when the model is not in the
  bundle (e.g. a build without LFS), and auto-activates once the model is committed.

**Git LFS**: The CoreML model (`RecipeApp/RecipeApp/MLModels/FoodClassifier.mlpackage`)
is stored in Git LFS. After a fresh clone, run `git lfs install && git lfs pull`
to download the model binary before building.

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
