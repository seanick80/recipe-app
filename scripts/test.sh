#!/usr/bin/env bash
# scripts/test.sh — run all tests runnable on the current host.
#
# On Windows: runs the pure-Swift Models/ tests via cmd.exe
#   (Git Bash's swiftc invocation fails silently; we must route through cmd).
# On macOS: runs both Models/ tests and (if Xcode available) xcodebuild tests.
#
# Exit code: 0 on success, non-zero on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

FAIL=0

info() { printf '  [test] %s\n' "$*"; }
err()  { printf '  [test] FAIL: %s\n' "$*" >&2; FAIL=1; }

echo "==> Testing Recipe App"

# ---------------------------------------------------------------------------
# 1. Pure-Swift Models/ tests (Windows-compatible)
# ---------------------------------------------------------------------------
if [[ -f "Models/TestModels.swift" ]]; then
    info "Compiling pure-Swift model tests"
    # Note: historical SESSION_STATE claimed swiftc had to be invoked via
    # cmd.exe from Git Bash on Windows; as of Swift 6.2.4 this is no longer
    # true — direct invocation works on Windows, macOS, and Linux.
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) OUT="test.exe" ;;
        *)                    OUT="test_bin" ;;
    esac
    SWIFT_SOURCES=(Models/Recipe.swift Models/GroceryItem.swift Models/ShoppingTemplate.swift Models/ListLineParser.swift Models/OCRParser.swift Models/DetectionClassifier.swift Models/BarcodeProductMapper.swift Models/PantryItemMapper.swift Models/GroceryCategorizer.swift Models/ZoneClassifier.swift Models/QualityGate.swift Models/TestHelpers.swift Models/TestShopping.swift Models/TestListParser.swift Models/TestOCR.swift Models/TestDetection.swift Models/TestBarcode.swift Models/TestPantry.swift Models/TestGroceryCategorizer.swift Models/TestZoneClassifier.swift Models/TestQualityGate.swift Models/TestModels.swift)
    if ! swiftc "${SWIFT_SOURCES[@]}" -o "$OUT" 2>&1; then
        err "swiftc compilation failed"
    else
        info "Running Models tests"
        if ! "./$OUT"; then
            err "Models tests failed"
        fi
        rm -f "$OUT" test.lib test.exp
    fi
else
    info "no Models/TestModels.swift found — skipping pure-Swift tests"
fi

# ---------------------------------------------------------------------------
# 2. Backend tests (Python) — run if server/ has tests
# ---------------------------------------------------------------------------
if [[ -d "server" ]] && [[ -f "server/requirements.txt" ]]; then
    if command -v pytest >/dev/null 2>&1 && find server -name "test_*.py" -print -quit 2>/dev/null | grep -q .; then
        info "Running server pytest"
        if ! (cd server && pytest -q); then
            err "server tests failed"
        fi
    else
        info "server/ has no tests yet — skipped"
    fi
fi

# ---------------------------------------------------------------------------
if [[ $FAIL -eq 0 ]]; then
    echo "==> Tests passed"
    exit 0
else
    echo "==> Tests FAILED" >&2
    exit 1
fi
