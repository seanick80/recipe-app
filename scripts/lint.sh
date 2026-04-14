#!/usr/bin/env bash
# scripts/lint.sh — static checks for the Recipe App repo.
#
# Runs:
#   1. swift-format --mode lint on Swift sources   (if swift-format available)
#   2. YAML validation on project.yml, codemagic.yaml
#   3. XML validation on entitlements plist
#   4. CRLF line-ending detection on tracked text files
#
# Exit code: 0 on clean, non-zero on any failure.
# Intended to be fast enough for a pre-commit hook.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

info() { printf '  [lint] %s\n' "$*"; }
warn() { printf '  [lint] WARN: %s\n' "$*" >&2; }
err()  { printf '  [lint] FAIL: %s\n' "$*" >&2; FAIL=1; }

echo "==> Linting Recipe App"

# ---------------------------------------------------------------------------
# 1. Swift formatting — optional, skipped cleanly on Windows if missing.
# ---------------------------------------------------------------------------
if command -v swift-format >/dev/null 2>&1; then
    info "swift-format lint on Swift sources"
    if ! swift-format lint --recursive --strict \
            Models RecipeApp/RecipeApp 2>/dev/null; then
        err "swift-format found issues (run: swift-format format -i -r Models RecipeApp/RecipeApp)"
    fi
elif swift format --version >/dev/null 2>&1; then
    info "swift format lint on Swift sources"
    if ! swift format lint --recursive --strict \
            Models RecipeApp/RecipeApp 2>/dev/null; then
        err "swift format found issues"
    fi
else
    warn "swift-format not installed — skipping Swift formatting check"
    warn "  install on macOS: brew install swift-format"
    warn "  install on Windows: not yet supported; enforced on Codemagic"
fi

# ---------------------------------------------------------------------------
# 2. YAML validation
# ---------------------------------------------------------------------------
YAML_FILES=(RecipeApp/project.yml codemagic.yaml)
for f in "${YAML_FILES[@]}"; do
    if [[ -f "$f" ]]; then
        info "validating YAML: $f"
        if ! python -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$f" 2>/dev/null; then
            err "$f is not valid YAML"
        fi
    else
        warn "$f not found (skipped)"
    fi
done

# ---------------------------------------------------------------------------
# 3. Entitlements plist XML validation
# ---------------------------------------------------------------------------
ENTITLEMENTS="RecipeApp/RecipeApp/RecipeApp.entitlements"
if [[ -f "$ENTITLEMENTS" ]]; then
    info "validating entitlements XML: $ENTITLEMENTS"
    if ! python -c "import sys, xml.etree.ElementTree as ET; ET.parse(sys.argv[1])" "$ENTITLEMENTS" 2>/dev/null; then
        err "$ENTITLEMENTS is not valid XML"
    fi
fi

# ---------------------------------------------------------------------------
# 4. CRLF detection on tracked text files
# ---------------------------------------------------------------------------
info "checking for CRLF line endings in tracked text files"
# Check the index column ($1 = i/...) not the working-tree column ($2 = w/...).
# On Windows with core.autocrlf=true the working copy is CRLF by design,
# but the index (what gets committed) must be LF.
CRLF_FILES=$(git ls-files --eol 2>/dev/null | awk '$1 ~ /crlf/ && $3 !~ /^-text$/ { print $4 }' || true)
if [[ -n "$CRLF_FILES" ]]; then
    err "files stored with CRLF (run: git add --renormalize .):"
    printf '    %s\n' $CRLF_FILES >&2
fi

# ---------------------------------------------------------------------------
if [[ $FAIL -eq 0 ]]; then
    echo "==> Lint passed"
    exit 0
else
    echo "==> Lint FAILED" >&2
    exit 1
fi
