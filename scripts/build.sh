#!/usr/bin/env bash
# scripts/build.sh — canonical build/validate entrypoint for the Recipe App.
#
# This is THE single source of truth for what "a build" means for this repo.
# Any flag, check, or sequencing that matters belongs here — never inline in
# CI yaml, ad-hoc commands, or individual dev environments.
#
# Modes:
#   ./scripts/build.sh            — full: lint + test + config validation + clean-tree check
#   ./scripts/build.sh quick      — lint + test only (skips clean-tree check; for pre-commit)
#   ./scripts/build.sh validate   — config validation only (no lint, no tests)
#
# Exit code: 0 on success, non-zero on any failure.
#
# On Windows this CANNOT actually build the IPA (requires a Mac with Xcode).
# The real build happens on Codemagic. This script validates everything the
# Mac runner will need so surprises don't show up post-push.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-full}"
FAIL=0

info() { printf '[build] %s\n' "$*"; }
err()  { printf '[build] FAIL: %s\n' "$*" >&2; FAIL=1; }

echo "==================================================================="
echo "  Recipe App build — mode: $MODE"
echo "==================================================================="

# ---------------------------------------------------------------------------
# Step 1: Lint
# ---------------------------------------------------------------------------
if [[ "$MODE" != "validate" ]]; then
    if ! "$REPO_ROOT/scripts/lint.sh"; then
        err "lint failed"
    fi
fi

# ---------------------------------------------------------------------------
# Step 2: Tests
# ---------------------------------------------------------------------------
if [[ "$MODE" != "validate" ]]; then
    if ! "$REPO_ROOT/scripts/test.sh"; then
        err "tests failed"
    fi
fi

# ---------------------------------------------------------------------------
# Step 3: Config validation (all modes)
# ---------------------------------------------------------------------------
info "validating xcodegen project.yml has required fields"
if [[ ! -f "RecipeApp/project.yml" ]]; then
    err "RecipeApp/project.yml missing"
else
    REQUIRED_KEYS=(
        "PRODUCT_BUNDLE_IDENTIFIER: com.seanick80.recipeapp"
        "DEVELOPMENT_TEAM: 3JR8WTJUV6"
        "CODE_SIGN_ENTITLEMENTS: RecipeApp/RecipeApp.entitlements"
        # Universal iOS bundles must declare iPad orientations or altool
        # rejects the TestFlight upload with a 409 validation error.
        # See project.yml comment for the iPhone-only alternative.
        "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad"
        # CameraViewModel uses CMMotionManager; without this string iOS
        # terminates the app the first time motion updates start.
        "INFOPLIST_KEY_NSMotionUsageDescription"
        # Avoids the per-build Export Compliance prompt in App Store Connect.
        "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"
    )
    for key in "${REQUIRED_KEYS[@]}"; do
        if ! grep -Fq "$key" RecipeApp/project.yml; then
            err "project.yml missing required setting: $key"
        fi
    done
fi

info "validating entitlements references correct CloudKit container"
if ! grep -Fq "iCloud.com.seanick80.recipeapp" RecipeApp/RecipeApp/RecipeApp.entitlements; then
    err "entitlements file missing CloudKit container iCloud.com.seanick80.recipeapp"
fi

info "validating RecipeAppApp.swift wires CloudKit database"
if ! grep -Fq 'cloudKitDatabase: .private("iCloud.com.seanick80.recipeapp")' RecipeApp/RecipeApp/RecipeAppApp.swift; then
    err "RecipeAppApp.swift ModelConfiguration is missing cloudKitDatabase"
fi

info "validating codemagic.yaml uses ASC API key integration"
if ! grep -Fq "app_store_connect: recipe-app-appstore-key" codemagic.yaml; then
    err "codemagic.yaml missing app_store_connect integration"
fi
if grep -Fq "CODE_SIGNING_ALLOWED=NO" codemagic.yaml; then
    err "codemagic.yaml still has CODE_SIGNING_ALLOWED=NO (remove for device builds)"
fi
# Signing uses explicit pre-uploaded identities under environment.ios_signing:
# the persistent IOS_DISTRIBUTION .p12 (reference: ios_distribution_cert)
# and the matching App Store provisioning profile (reference:
# ios_distribution_profile). Both are uploaded once to Codemagic's
# Code Signing Identities / Provisioning Profiles stores and reused
# across builds. Distribution (not Development) is required because
# TestFlight rejects dev-signed IPAs at altool upload time.
#
# Per-build `certificates create` is forbidden: creating a new cert
# every build burns a slot in Apple's cert cap and orphans the old
# private key on the ephemeral runner. See
# ~/.claude/.../memory/feedback_ci_signing.md for the reasoning.
if ! grep -Fq "ios_signing:" codemagic.yaml; then
    err "codemagic.yaml missing environment.ios_signing block"
fi
if ! grep -Fq "ios_distribution_cert" codemagic.yaml; then
    err "codemagic.yaml must reference stored signing identity 'ios_distribution_cert' under environment.ios_signing.certificates"
fi
if ! grep -Fq "ios_distribution_profile" codemagic.yaml; then
    err "codemagic.yaml must reference stored provisioning profile 'ios_distribution_profile' under environment.ios_signing.provisioning_profiles"
fi
# Regression guard: don't let a future edit accidentally re-introduce
# Development signing (which would break TestFlight publish again).
if grep -Eq '^\s*-\s*ios_development_(cert|profile)\s*$' codemagic.yaml; then
    err "codemagic.yaml references ios_development_cert / ios_development_profile in a signing list — Distribution-only for TestFlight builds"
fi
if ! grep -Fq "provisioning_profiles:" codemagic.yaml; then
    err "codemagic.yaml missing environment.ios_signing.provisioning_profiles list"
fi
if grep -Fq "certificates create" codemagic.yaml; then
    err "codemagic.yaml must NOT run 'app-store-connect certificates create' — signing uses the persistent .p12 in Codemagic's store"
fi
if grep -Fq "openssl genrsa" codemagic.yaml; then
    err "codemagic.yaml must NOT generate an RSA key at build time — the persistent .p12 already contains the key"
fi
if grep -Eq '\-\-certificate-key' codemagic.yaml; then
    err "codemagic.yaml must NOT pass --certificate-key — no ephemeral key generation"
fi
if grep -Fq "certificates delete" codemagic.yaml; then
    err "codemagic.yaml must NOT revoke certificates as a routine build step"
fi
if ! grep -Fq "triggering:" codemagic.yaml; then
    err "codemagic.yaml missing triggering: section — without it the GitHub webhook will not auto-build"
fi

# The Build step cd's into RecipeApp/ before running `xcode-project build-ipa`,
# so the IPA output path is RecipeApp/build/ios/ipa/ relative to CM_BUILD_DIR,
# not build/ios/ipa/. Using the wrong glob causes Codemagic to report the build
# as successful but publish only the xcodebuild log with no IPA attached.
if ! grep -Fq "RecipeApp/build/ios/ipa/*.ipa" codemagic.yaml; then
    err "codemagic.yaml artifact glob must be 'RecipeApp/build/ios/ipa/*.ipa' — the Build step cd's into RecipeApp/ first, so the IPA path is relative to that subdir"
fi

info "validating app-extension plist config (static, no xcodegen needed)"
if ! python "$REPO_ROOT/scripts/validate-extension-plist.py"; then
    err "extension plist validation failed — see errors above"
fi

info "verifying .xcodeproj is NOT tracked (must be generated by xcodegen)"
if git ls-files --error-unmatch RecipeApp/RecipeApp.xcodeproj 2>/dev/null; then
    err ".xcodeproj is tracked in git — it must be generated by xcodegen, not committed"
fi

info "verifying SharedLogic/ files referenced by iOS sources are in codemagic.yaml copy list"
# The iOS app compiles on Codemagic, which has no view of the root SharedLogic/
# directory unless codemagic.yaml's "Copy shared parser modules" step
# explicitly `cp`'s the file into RecipeApp/RecipeApp/Parsers/ first.
# Forgetting to add a new SharedLogic/*.swift here produces a "cannot find type
# X in scope" error that only surfaces on CI — so validate locally.
check_sharedlogic_in_codemagic() {
    local missing="" f base syms referenced sym
    for f in SharedLogic/*.swift; do
        base="$(basename "$f" .swift)"
        # Match any top-level declaration at column 0, tolerating modifiers
        # like `public`, `internal`, `final`, `@MainActor`, `@Observable`, etc.
        # E.g. both `func encode(...)` and `final class DebugLog {` match.
        syms=$(grep -Eh '^([@a-zA-Z][a-zA-Z]* +)*(func|struct|class|enum|protocol|typealias) +[A-Za-z_][A-Za-z0-9_]*' "$f" 2>/dev/null \
            | sed -E 's/.*(func|struct|class|enum|protocol|typealias) +([A-Za-z_][A-Za-z0-9_]*).*/\2/' \
            | sort -u || true)
        [[ -z "$syms" ]] && continue
        referenced=0
        for sym in $syms; do
            if grep -rq --include='*.swift' "\\b${sym}\\b" RecipeApp/RecipeApp 2>/dev/null; then
                referenced=1
                break
            fi
        done
        if [[ $referenced -eq 1 ]] && ! grep -Fq "SharedLogic/${base}.swift" codemagic.yaml; then
            missing="${missing}${base}.swift "
        fi
    done
    if [[ -n "$missing" ]]; then
        err "codemagic.yaml is missing these SharedLogic/ files from its 'Copy shared parser modules' step (iOS sources reference their symbols): ${missing}"
    fi
}
check_sharedlogic_in_codemagic

info "verifying AppIcon asset set exists (Xcode archive requires it)"
APPICON_DIR="RecipeApp/RecipeApp/Assets.xcassets/AppIcon.appiconset"
if [[ ! -f "$APPICON_DIR/Contents.json" ]]; then
    err "$APPICON_DIR/Contents.json missing — actool will fail the archive with 'no matching icon set named AppIcon'"
fi
if ! ls "$APPICON_DIR"/*.png >/dev/null 2>&1; then
    err "$APPICON_DIR contains no PNG — run scripts/generate-appicon.py to regenerate the placeholder"
fi

# ---------------------------------------------------------------------------
# Step 4: Clean working tree (full mode only)
# ---------------------------------------------------------------------------
if [[ "$MODE" == "full" ]]; then
    info "checking working tree is clean"
    if [[ -n "$(git status --porcelain)" ]]; then
        err "working tree has uncommitted changes — commit or stash before pushing"
        git status --short >&2
    fi
fi

# ---------------------------------------------------------------------------
echo "==================================================================="
if [[ $FAIL -eq 0 ]]; then
    echo "  BUILD OK (mode: $MODE)"
    echo "==================================================================="
    exit 0
else
    echo "  BUILD FAILED (mode: $MODE)" >&2
    echo "===================================================================" >&2
    exit 1
fi
