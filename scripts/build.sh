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
# Signing uses Codemagic managed signing: environment.ios_signing with
# distribution_type + bundle_identifier. Codemagic pulls our persistent
# .p12 (reference: ios_development_cert) from its Code Signing Identities
# store and fetches/creates a matching provisioning profile via the ASC
# API integration before scripts run. Certificates-only ios_signing
# shapes are rejected by Codemagic's schema validator.
#
# Per-build `certificates create` is forbidden: creating a new cert
# every build burns a slot in Apple's 1-cert-per-type limit and orphans
# the old private key on the ephemeral runner. See
# ~/.claude/.../memory/feedback_ci_signing.md for the reasoning.
if ! grep -Fq "ios_signing:" codemagic.yaml; then
    err "codemagic.yaml missing environment.ios_signing block"
fi
if ! grep -Fq "ios_development_cert" codemagic.yaml; then
    err "codemagic.yaml must reference stored signing identity 'ios_development_cert' under environment.ios_signing.certificates"
fi
if ! grep -Fq "ios_development_profile" codemagic.yaml; then
    err "codemagic.yaml must reference stored provisioning profile 'ios_development_profile' under environment.ios_signing.provisioning_profiles"
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

info "verifying .xcodeproj is NOT tracked (must be generated by xcodegen)"
if git ls-files --error-unmatch RecipeApp/RecipeApp.xcodeproj 2>/dev/null; then
    err ".xcodeproj is tracked in git — it must be generated by xcodegen, not committed"
fi

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
