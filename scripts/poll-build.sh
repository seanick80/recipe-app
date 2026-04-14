#!/usr/bin/env bash
# scripts/poll-build.sh — poll Codemagic build status after push.
#
# Usage:
#   ./scripts/poll-build.sh              # poll the latest build
#   ./scripts/poll-build.sh <build_id>   # poll a specific build
#
# Reads CODEMAGIC_API_TOKEN and CODEMAGIC_APP_ID from .env in repo root.
# On completion (success or failure), downloads artifacts and extracts
# the xctest.log for analysis.
# Exit code: 0 on success (finished), 1 on failure/canceled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Find python — macOS/Linux usually have python3, Windows Git Bash may not
PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
if [[ -z "$PYTHON" ]]; then
    echo "python not found on PATH" >&2
    exit 1
fi
ARTIFACT_DIR="$REPO_ROOT/build/ci-artifacts"

# Load .env
if [[ -f "$REPO_ROOT/.env" ]]; then
    set -a
    source "$REPO_ROOT/.env"
    set +a
fi

: "${CODEMAGIC_API_TOKEN:?Set CODEMAGIC_API_TOKEN in .env}"
: "${CODEMAGIC_APP_ID:?Set CODEMAGIC_APP_ID in .env}"

API="https://api.codemagic.io"
AUTH=(-H "x-auth-token: $CODEMAGIC_API_TOKEN")

# -----------------------------------------------------------------------
# Resolve build ID
# -----------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
    BUILD_ID="$1"
else
    # Fetch latest build ID from the apps list endpoint
    BUILD_ID=$(curl -s "${AUTH[@]}" "$API/apps" \
        | $PYTHON -c "
import sys, json
data = json.load(sys.stdin)
apps = data.get('applications', [])
for app in apps:
    if app['_id'] == '$CODEMAGIC_APP_ID':
        print(app.get('lastBuildId', ''))
        break
" 2>/dev/null)
    if [[ -z "$BUILD_ID" || "$BUILD_ID" == "None" ]]; then
        echo "Could not determine latest build ID" >&2
        exit 1
    fi
fi

echo "Polling build: $BUILD_ID"
echo "Dashboard: https://codemagic.io/app/$CODEMAGIC_APP_ID/build/$BUILD_ID"
echo ""

# -----------------------------------------------------------------------
# download_artifacts — fetch and extract artifact zip, show xctest.log
# -----------------------------------------------------------------------
download_artifacts() {
    local response="$1"
    local final_status="$2"

    # List all artifacts
    echo "$response" | $PYTHON -c "
import sys, json
build = json.load(sys.stdin)['build']
arts = build.get('artefacts', [])
if arts:
    print('  Artifacts:')
    for a in arts:
        print(f'    {a.get(\"name\", \"unknown\")}: {a.get(\"url\", \"no url\")}')
" 2>/dev/null || true

    # Find the artifact zip containing xctest.log (not the IPA)
    local artifact_url
    artifact_url=$(echo "$response" | $PYTHON -c "
import sys, json
build = json.load(sys.stdin)['build']
for a in build.get('artefacts', []):
    url = a.get('url', '')
    name = a.get('name', '')
    # Prefer the artifacts zip (contains xctest.log), skip IPA files
    if url and not name.endswith('.ipa'):
        print(url)
        break
" 2>/dev/null || true)

    if [[ -z "$artifact_url" ]]; then
        echo "  No artifact URL found."
        return
    fi

    echo "  Downloading artifacts..."
    mkdir -p "$ARTIFACT_DIR"
    local zip_path="$ARTIFACT_DIR/artifacts.zip"
    curl -sL "${AUTH[@]}" -o "$zip_path" "$artifact_url"

    if ! file "$zip_path" | grep -q "Zip"; then
        echo "  Downloaded file is not a valid zip."
        return
    fi

    unzip -o -q "$zip_path" -d "$ARTIFACT_DIR" 2>/dev/null || true

    # Show xctest.log summary
    local log_path="$ARTIFACT_DIR/xctest.log"
    if [[ -f "$log_path" ]]; then
        echo ""
        echo "=== XCTest Log Analysis ==="
        local line_count
        line_count=$(wc -l < "$log_path")
        echo "  Log: $log_path ($line_count lines)"

        # Extract errors
        local errors
        errors=$(grep -i "error:" "$log_path" 2>/dev/null | head -20 || true)
        if [[ -n "$errors" ]]; then
            echo ""
            echo "  ERRORS:"
            echo "$errors" | sed 's/^/    /'
        fi

        # Extract test summary
        local summary
        summary=$(grep -E "(TEST (SUCCEEDED|FAILED)|Testing failed|tests? passed|tests? failed)" "$log_path" 2>/dev/null | tail -5 || true)
        if [[ -n "$summary" ]]; then
            echo ""
            echo "  TEST SUMMARY:"
            echo "$summary" | sed 's/^/    /'
        fi

        # If build failed, show last 20 lines for context
        if [[ "$final_status" == "failed" ]]; then
            echo ""
            echo "  TAIL (last 20 lines):"
            tail -20 "$log_path" | sed 's/^/    /'
        fi
    else
        echo "  No xctest.log found in artifacts."
        echo "  Contents: $(ls "$ARTIFACT_DIR" 2>/dev/null || echo "(empty)")"
    fi
}

# -----------------------------------------------------------------------
# Poll loop
# -----------------------------------------------------------------------
INTERVAL=15
while true; do
    RESPONSE=$(curl -s "${AUTH[@]}" "$API/builds/$BUILD_ID")

    STATUS=$(echo "$RESPONSE" | $PYTHON -c "import sys,json; print(json.load(sys.stdin)['build']['status'])" 2>/dev/null)

    case "$STATUS" in
        queued|preparing)
            echo "  [$STATUS] Waiting in queue..."
            ;;
        building)
            echo "  [$STATUS] Build in progress..."
            ;;
        publishing)
            echo "  [$STATUS] Publishing artifacts..."
            ;;
        finished)
            echo ""
            echo "BUILD FINISHED"
            download_artifacts "$RESPONSE" "finished"
            exit 0
            ;;
        failed)
            echo ""
            echo "BUILD FAILED"
            download_artifacts "$RESPONSE" "failed"
            exit 1
            ;;
        canceled)
            echo ""
            echo "BUILD CANCELED"
            exit 1
            ;;
        *)
            echo "  [unknown status: $STATUS]"
            ;;
    esac

    sleep "$INTERVAL"
done
