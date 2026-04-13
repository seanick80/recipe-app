#!/usr/bin/env bash
# scripts/poll-build.sh — poll Codemagic build status after push.
#
# Usage:
#   ./scripts/poll-build.sh              # poll the latest build
#   ./scripts/poll-build.sh <build_id>   # poll a specific build
#
# Reads CODEMAGIC_API_TOKEN and CODEMAGIC_APP_ID from .env in repo root.
# Exit code: 0 on success (finished), 1 on failure/canceled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
        | python -c "
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
# Poll loop
# -----------------------------------------------------------------------
INTERVAL=15
while true; do
    RESPONSE=$(curl -s "${AUTH[@]}" "$API/builds/$BUILD_ID")

    STATUS=$(echo "$RESPONSE" | python -c "import sys,json; print(json.load(sys.stdin)['build']['status'])" 2>/dev/null)

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
            # Try to extract artifact URLs
            echo "$RESPONSE" | python -c "
import sys, json
build = json.load(sys.stdin)['build']
artifacts = build.get('artefacts', [])
if artifacts:
    print('Artifacts:')
    for a in artifacts:
        name = a.get('name', a.get('type', 'unknown'))
        url = a.get('url', 'no url')
        print(f'  {name}: {url}')
else:
    print('No artifacts found in response')
" 2>/dev/null || true
            exit 0
            ;;
        failed)
            echo ""
            echo "BUILD FAILED"
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
