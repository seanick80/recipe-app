#!/usr/bin/env bash
# scripts/generate-distribution-profile.sh
#
# ONE-TIME CEREMONY (companion to generate-signing-identity.sh --type distribution).
# Creates an "App Store" provisioning profile in ASC bound to the iOS
# Distribution certificate you just minted, and saves the .mobileprovision
# file locally so you can upload it to Codemagic as `ios_distribution_profile`.
#
# Prerequisites:
#   - scripts/generate-signing-identity.sh --type distribution has completed
#     (so secrets/cert-response-dist.json exists with the cert resource ID)
#   - secrets/env.sh sourced (ASC API creds)
#   - codemagic-cli-tools installed
#
# Outputs (in secrets/, all gitignored):
#   - distribution-profile-response.json — raw ASC API response
#   - *.mobileprovision                  — the profile file to upload to Codemagic
#
# Rerunning: Apple allows multiple App Store profiles with the same name
# but it's wasteful. If the profile already exists in ASC you can either
# skip this script entirely or delete the old profile in the portal first.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

SECRETS_DIR="secrets"
CERT_RESPONSE="$SECRETS_DIR/cert-response-dist.json"
PROFILE_RESPONSE="$SECRETS_DIR/distribution-profile-response.json"
BUNDLE_ID_LIST_RESPONSE="$SECRETS_DIR/bundle-id-list-response.json"
BUNDLE_ID="com.seanick80.recipeapp"
PROFILE_NAME="Recipe App App Store"

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[profile] %s\n' "$*"; }

# --- guardrails ----------------------------------------------------------
[[ -f "$CERT_RESPONSE" ]] || die "$CERT_RESPONSE missing. Run: ./scripts/generate-signing-identity.sh --type distribution"
for var in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY; do
    [[ -n "${!var:-}" ]] || die "$var unset. Run: source secrets/env.sh"
done
command -v app-store-connect >/dev/null || die "app-store-connect CLI not found; pip install codemagic-cli-tools"
command -v python >/dev/null || die "python not found on PATH"

# --- extract cert resource ID from the dist ceremony response -----------
CERT_ID=$(python - "$CERT_RESPONSE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
# codemagic-cli-tools returns either {id, attributes} or {data: {id, attributes}}
cert_id = data.get("id") or data.get("data", {}).get("id")
if not cert_id:
    sys.exit("could not find cert id in response")
print(cert_id)
PY
)
info "dist cert resource id: $CERT_ID"

# --- look up Bundle ID resource ID (the profiles create positional is the
#     alphanumeric ASC resource ID, NOT the reverse-DNS identifier) -----
info "looking up bundle-id resource for $BUNDLE_ID"
app-store-connect bundle-ids list \
    --bundle-id-identifier "$BUNDLE_ID" \
    --strict-match-identifier \
    --json \
    > "$BUNDLE_ID_LIST_RESPONSE"

BUNDLE_ID_RESOURCE=$(python - "$BUNDLE_ID_LIST_RESPONSE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
# List endpoint returns a bare list of resource objects.
if isinstance(data, list):
    items = data
elif isinstance(data, dict) and "data" in data:
    items = data["data"]
else:
    items = []
if not items:
    sys.exit("bundle-id not found in ASC — register it in the developer portal first")
# Prefer exact identifier match if multiple came back despite --strict-match.
for it in items:
    attrs = it.get("attributes", {})
    if attrs.get("identifier") == "com.seanick80.recipeapp":
        print(it["id"])
        break
else:
    sys.exit("no exact bundle-id identifier match")
PY
)
info "bundle-id resource id: $BUNDLE_ID_RESOURCE"

# --- create the App Store profile in ASC and save locally ---------------
info "creating profile '$PROFILE_NAME' for $BUNDLE_ID (type IOS_APP_STORE)"
app-store-connect profiles create \
    "$BUNDLE_ID_RESOURCE" \
    --type IOS_APP_STORE \
    --name "$PROFILE_NAME" \
    --certificate-ids "$CERT_ID" \
    --profiles-dir "$SECRETS_DIR" \
    --save \
    --json \
    > "$PROFILE_RESPONSE"

# Report where it landed (pick the newest .mobileprovision in secrets/).
PROFILE_FILE=$(ls -t "$SECRETS_DIR"/*.mobileprovision 2>/dev/null | head -1 || true)
[[ -n "$PROFILE_FILE" ]] || die "no .mobileprovision landed in $SECRETS_DIR — inspect $PROFILE_RESPONSE"

echo ""
echo "============================================================"
echo "  PROFILE CREATED"
echo "============================================================"
echo "Profile file:      $PROFILE_FILE"
echo "ASC response:      $PROFILE_RESPONSE"
echo ""
echo "NEXT: upload $PROFILE_FILE to Codemagic:"
echo "  Teams -> Code signing identities -> Upload provisioning profile"
echo "  Reference name: ios_distribution_profile"
