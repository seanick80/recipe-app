# Recipe App

## Project Structure
- `RecipeApp/` — SwiftUI iOS app (MVVM + SwiftData + CloudKit)
  - `project.yml` — xcodegen config (source of truth; `.xcodeproj` is generated and gitignored)
  - `RecipeApp/RecipeApp.entitlements` — CloudKit service + container identifier
- `SharedLogic/` — Pure-Swift modules shipped into the iOS app (parsers,
  classifiers, quality gate, debug log). Copied into
  `RecipeApp/RecipeApp/Parsers/` at CI build time by codemagic.yaml. Must
  compile with `swiftc` on Windows (no Apple frameworks).
- `TestFixtures/` — Windows-only test mirrors of the SwiftData `@Model` types
  (`Recipe.swift`, `GroceryItem.swift`, `ShoppingTemplate.swift`) plus all
  `Test*.swift` suites. Never copied into the iOS bundle.
- `scripts/layout-bench/` — Local document layout analysis benchmark (Python/PyTorch, Windows)
- `data/layout-bench/` — Test images + ground truth for layout bench (images gitignored)
- `schema/` — Canonical schema definition (`canonical.yaml`) and sync test
- `server/` — Python FastAPI backend (PostgreSQL on Neon, Google OAuth, JWT auth)
- `frontend/` — React SPA (Vite + TypeScript) for web recipe editor
- `scripts/pantry-bench/` — YOLO pantry-detection evaluation harness (Python/ultralytics)
- `data/pantry_images/` — 9 test pantry photos for detection benchmarking
- `data/pantry-bench/results/` — Benchmark output (report.json + annotated images)
- `database/` — SQL schema and seed data

## iOS App
- Architecture: MVVM with SwiftData for persistence
- **Persistence**: SwiftData backed by CloudKit private database (`iCloud.com.seanick80.recipeapp`).
  All `@Model` classes must keep CloudKit constraints: every stored property defaulted
  or optional, relationships optional with explicit `inverse:`, no `@Attribute(.unique)`.
- **Build system**: xcodegen. `RecipeApp.xcodeproj` is generated from `RecipeApp/project.yml`
  on the Codemagic Mac runner at build time — do NOT check the `.xcodeproj` into git.
- **Signing**: Explicit manual signing with a persistent iOS Distribution `.p12`
  + matching App Store provisioning profile, both pre-uploaded to Codemagic
  (`ios_distribution_cert` / `ios_distribution_profile`) and referenced from
  `environment.ios_signing` in `codemagic.yaml`. App Store Connect API key
  `recipe-app-appstore-key` (Team `3JR8WTJUV6`) authorizes signing + publish.
- **Build pipeline**: Push to GitHub `master` → Codemagic installs xcodegen →
  `xcodegen generate` → `agvtool new-version -all $((BUILD_NUMBER + 100))`
  (bumps `CFBundleVersion` above any prior TestFlight upload) →
  `xcode-project use-profiles` → `xcode-project build-ipa` →
  `app-store-connect publish --testflight` (release notes harvested from
  recent `feat:`/`fix:` commits). Internal testers get the build via the
  normal TestFlight app.
- Local testing: Pure Swift modules in `SharedLogic/` + `TestFixtures/` can be compiled with `swiftc` on Windows.

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
- Run `swift-format format -i -r --configuration .swift-format SharedLogic TestFixtures RecipeApp/RecipeApp`
  to autofix; `./scripts/lint.sh` runs `--mode lint` in CI.

## Secrets policy

Safe to commit (all are effectively public): Team ID, bundle ID, CloudKit
container identifier, Codemagic integration name.

NEVER commit: `.p8` files, `.p12` files, private keys, mobileprovision
files, Apple ID passwords, CloudKit server-to-server tokens, Issuer ID +
Key ID pairs for App Store Connect API keys. If any of these are ever
added by mistake, stop and ask — do not just `git rm` because they may
already be in the remote history.

## Authentication

The app uses Google OAuth + JWT for authentication across all clients.

### Server Auth (FastAPI)
- **Web flow**: `/api/v1/auth/login` → Google OAuth → session cookie (`session_token`)
- **Mobile flow (native)**: iOS sends Google ID token → `POST /api/v1/auth/mobile/google` → server verifies via `google-auth` library → returns JWT
- **Mobile flow (legacy)**: `/api/v1/auth/mobile/login` → ASWebAuthenticationSession OAuth → redirect to `recipeapp://auth?token=<jwt>` (deprecated, kept for backwards compat)
- **Token refresh**: `POST /api/v1/auth/refresh` — accepts Bearer or cookie, 24h grace period for expired tokens
- **Auth priority** in `get_current_user`: Bearer header → cookie → API key
- JWT: HS256, 7-day expiry, claims: `sub` (email), `name`, `role`
- Allowlist-based: only users in `AllowedUser` table can authenticate
- Server accepts tokens from both iOS client ID and web client ID

### iOS Auth Client
- **OAuth**: Google Sign-In iOS SDK (`GoogleSignIn-iOS` SPM package). Native Google sign-in sheet → ID token → `POST /auth/mobile/google` → JWT
- **iOS Client ID**: `972511622379-mak8qoj1corsaria7f2k8ainq715al7u.apps.googleusercontent.com`
- **Token storage**: Keychain (`KeychainService.swift`) with `kSecAttrAccessibleAfterFirstUnlock`
- **API calls**: `APIClient` attaches `Authorization: Bearer <token>` to all requests
- **Session restore**: On launch, validates stored token via `/auth/me`; refreshes if 401
- **UI gate**: App shows `LoginView` until authenticated, then `ContentView`
- **Skip login**: "Continue without signing in" allows local-only use without auth
- **Settings**: Account info (name, email, role) + sign out in `SettingsView`
- **URL schemes**: `recipeapp://` (app links) + reversed iOS client ID (Google Sign-In redirect) in `Info.plist`
- **URL handling**: `RecipeAppApp.onOpenURL` forwards to `GIDSignIn.sharedInstance.handle()`

### Auth Endpoints
| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/auth/login` | GET | Web OAuth redirect |
| `/api/v1/auth/callback` | GET | Web OAuth callback |
| `/api/v1/auth/mobile/google` | POST | Native iOS token exchange |
| `/api/v1/auth/mobile/login` | GET | Legacy mobile OAuth redirect |
| `/api/v1/auth/mobile/callback` | GET | Legacy mobile OAuth callback |
| `/api/v1/auth/me` | GET | Current user info |
| `/api/v1/auth/refresh` | POST | Token refresh |
| `/api/v1/auth/logout` | POST | Clear session (web) |
| `/api/v1/auth/invite` | POST | Invite user (admin) |
| `/api/v1/auth/users` | GET | List users (admin) |
| `/api/v1/auth/users/{id}` | DELETE | Remove user (admin) |

## Backend Server
```bash
cd server
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```
- Neon PostgreSQL (free tier, SSL enforced)
- Google OAuth + JWT auth (allowlist-based, Bearer + cookie + API key)
- Server logs: `server/logs/server.log`, `server/logs/audit.log`

## Frontend (Web)
```bash
cd frontend
npm install && npm run dev   # http://localhost:5173
```

## Database
```bash
# Create PostgreSQL database
createdb recipe_app
psql recipe_app < database/init.sql
psql recipe_app < database/seed.sql
```

## Schema Sync
All data models (6 models × 7 surfaces) are defined in `schema/canonical.yaml`.
```bash
python scripts/test_schema_sync.py   # verify all surfaces match canonical
```
When adding a field: update `canonical.yaml` first, then propagate to each surface.

## Testing
```bash
# All tests (Windows) — 300 tests across 15 Swift suites + 49 server tests
./scripts/test.sh

# Full build validation (lint + tests + config)
./scripts/build.sh

# Python server
cd server && pytest
```

Pure Swift test suites in `TestFixtures/` (exercising `SharedLogic/` code):
Recipe (13), Shopping (16), ListParser (59), OCR (20), Detection (13),
Barcode (11), Pantry (10), GroceryCategorizer (31), ZoneClassifier (12),
QualityGate (24), DebugLog (10), PrepNoteStripper (14),
ContentDetector (4), FuzzyMatcher (11), RecipeSchemaParser (52).

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
