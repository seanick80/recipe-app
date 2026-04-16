#!/usr/bin/env bash
# scripts/generate-signing-identity.sh
#
# ONE-TIME CEREMONY. Issues a single long-lived iOS signing identity
# (Development OR Distribution), packages it as a password-protected
# .p12, and emits a renewal-record markdown file you can save to a
# password manager or saved email draft. Run this once per identity
# type, upload the .p12 to Codemagic, and forget about it until the
# cert expires (1 year from issue).
#
# Usage:
#   ./scripts/generate-signing-identity.sh                   # development (default)
#   ./scripts/generate-signing-identity.sh --type development
#   ./scripts/generate-signing-identity.sh --type distribution
#
# The two types are independent identities on disk and in ASC:
#   - development → secrets/ios_dev.p12,   uploaded as `ios_development_cert`
#   - distribution → secrets/ios_dist.p12, uploaded as `ios_distribution_cert`
#
# Prerequisites (all handled before this script runs):
#   - codemagic-cli-tools installed locally (pip install codemagic-cli-tools)
#   - secrets/AuthKey_<KEYID>.p8 present
#   - APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_KEY_IDENTIFIER,
#     APP_STORE_CONNECT_PRIVATE_KEY exported (source secrets/env.sh)
#   - secrets/p12_password.txt present, containing the desired .p12
#     password as raw bytes (no trailing newline). This file is the
#     single source of truth for the password — NEVER pass the password
#     via a shell variable. Shell layers (Git Bash histexpand, JSON
#     argument passthrough, cmd.exe delayed expansion, etc.) can silently
#     corrupt characters like `!`, leaving you with a .p12 whose password
#     nobody can reproduce. File-based password sources sidestep all of
#     that. Create it with your editor directly, or:
#       printf '%s' 'your-password-here' > secrets/p12_password.txt
#     The same password file is reused across dev/dist ceremonies; if
#     you want a per-identity password, rotate the file between runs.
#
# Outputs for --type development (all in secrets/, all gitignored):
#   - ios_dev.key                — RSA private key (delete after .p12 confirmed)
#   - ios_dev.pem                — issued cert in PEM form (delete after .p12 confirmed)
#   - ios_dev.p12                — password-protected bundle for Codemagic
#   - ios_dev_cert_record.md     — renewal metadata (save to password manager/email)
#   - cert-response-dev.json     — raw ASC API response (delete after .p12 confirmed)
#
# Outputs for --type distribution (same shape, `dev` → `dist`):
#   - ios_dist.key, ios_dist.pem, ios_dist.p12, ios_dist_cert_record.md,
#   - cert-response-dist.json
#
# To rotate: revoke the old cert in the Apple Developer portal, delete
# the .p12 for that type, re-run this script with the same --type flag.

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse --type flag (default: development)
# ---------------------------------------------------------------------------
IDENTITY_TYPE="development"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)
            IDENTITY_TYPE="${2:-}"
            shift 2
            ;;
        --type=*)
            IDENTITY_TYPE="${1#*=}"
            shift
            ;;
        -h|--help)
            sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'ERROR: unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

case "$IDENTITY_TYPE" in
    development)
        PREFIX="dev"
        HUMAN_TYPE="Development"
        ASC_CERT_TYPE="IOS_DEVELOPMENT"
        CODEMAGIC_REF_NAME="ios_development_cert"
        ;;
    distribution)
        PREFIX="dist"
        HUMAN_TYPE="Distribution"
        ASC_CERT_TYPE="IOS_DISTRIBUTION"
        CODEMAGIC_REF_NAME="ios_distribution_cert"
        ;;
    *)
        printf 'ERROR: --type must be development or distribution (got: %s)\n' "$IDENTITY_TYPE" >&2
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# All paths below are RELATIVE to $REPO_ROOT. This matters on Windows
# Git Bash: Python-based Windows binaries do not understand MINGW-style
# /c/sourcecode/... paths embedded in argument values like `@file:PATH`,
# and the shell's auto-convert heuristic fails on the `@file:` prefix.
# Relative paths sidestep the whole translation issue.
SECRETS_DIR="secrets"

PRIVATE_KEY="$SECRETS_DIR/ios_${PREFIX}.key"
CERT_PEM="$SECRETS_DIR/ios_${PREFIX}.pem"
P12_PATH="$SECRETS_DIR/ios_${PREFIX}.p12"
P12_PASSWORD_FILE="$SECRETS_DIR/p12_password.txt"
RESPONSE_JSON="$SECRETS_DIR/cert-response-${PREFIX}.json"
RECORD_MD="$SECRETS_DIR/ios_${PREFIX}_cert_record.md"

COMMON_NAME="iOS ${HUMAN_TYPE}: Nick Harlson"

# ---------------------------------------------------------------------------
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '[ceremony] %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Guardrails: env + idempotence
# ---------------------------------------------------------------------------
[[ -d "$SECRETS_DIR" ]] || die "secrets/ directory missing; run from repo root"

for var in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY; do
    if [[ -z "${!var:-}" ]]; then
        die "$var is unset. Run: source secrets/env.sh"
    fi
done
[[ -s "$P12_PASSWORD_FILE" ]] || die "$P12_PASSWORD_FILE missing or empty. See script header for how to create it."
# Sanity: warn loudly if the password file has a trailing newline, which
# would silently become part of the password and nobody would notice until
# Codemagic rejected the upload.
if [[ "$(tail -c 1 "$P12_PASSWORD_FILE" | xxd -p)" == "0a" ]]; then
    die "$P12_PASSWORD_FILE ends in a newline. Rewrite with: printf '%s' 'PASSWORD' > $P12_PASSWORD_FILE"
fi

if [[ -f "$P12_PATH" ]]; then
    die "$P12_PATH already exists. Refusing to re-issue. Delete it manually if you really mean to rotate."
fi

command -v openssl >/dev/null || die "openssl not found on PATH"
command -v app-store-connect >/dev/null || die "app-store-connect CLI not found; pip install codemagic-cli-tools"
command -v python >/dev/null || die "python not found on PATH"

# ---------------------------------------------------------------------------
# 2. Generate fresh 2048-bit RSA private key (skipped on resume)
# ---------------------------------------------------------------------------
if [[ -f "$PRIVATE_KEY" && -f "$RESPONSE_JSON" ]]; then
    info "resuming from existing $PRIVATE_KEY and $RESPONSE_JSON"
else
    info "generating 2048-bit RSA private key -> $PRIVATE_KEY"
    openssl genrsa -out "$PRIVATE_KEY" 2048 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 3. Submit CSR to App Store Connect via ASC API (skipped on resume)
# ---------------------------------------------------------------------------
# Resume-safety: if cert-response.json already exists on disk, a previous
# run of this script already created a cert in ASC. Re-calling "create"
# would hit Apple's 1-cert-per-type limit with a 409 and leave us stuck.
# Reuse the existing response instead.
if [[ -f "$RESPONSE_JSON" ]]; then
    info "$RESPONSE_JSON already exists -> reusing (skipping ASC API create)"
else
    info "submitting CSR to App Store Connect API ($ASC_CERT_TYPE)"
    app-store-connect certificates create \
        --type "$ASC_CERT_TYPE" \
        --certificate-key=@file:"$PRIVATE_KEY" \
        --json \
        > "$RESPONSE_JSON"
    info "cert issued."
fi
info "parsing response."

# ---------------------------------------------------------------------------
# 4. Extract cert content and metadata from response
# ---------------------------------------------------------------------------
# codemagic-cli-tools returns the JSON:API resource object. Attributes
# of interest: displayName, serialNumber, certificateType, certificateContent
# (base64-encoded DER), expirationDate, id (cert resource ID).
python - "$RESPONSE_JSON" "$CERT_PEM" "$RECORD_MD" "$COMMON_NAME" "$P12_PATH" \
    "$ASC_CERT_TYPE" "$HUMAN_TYPE" "$CODEMAGIC_REF_NAME" "$PREFIX" <<'PY'
import base64
import json
import sys
import textwrap
from pathlib import Path

(
    response_path,
    cert_pem_path,
    record_path,
    common_name,
    p12_path,
    asc_cert_type,
    human_type,
    codemagic_ref_name,
    prefix,
) = sys.argv[1:]

with open(response_path, encoding="utf-8") as f:
    data = json.load(f)

# codemagic-cli-tools --json wraps the Apple response; the resource attrs
# live under either top-level "attributes" or "data.attributes" depending
# on CLI version. Handle both.
if "attributes" in data and "id" in data:
    attrs = data["attributes"]
    resource_id = data["id"]
elif "data" in data:
    attrs = data["data"]["attributes"]
    resource_id = data["data"]["id"]
else:
    print("Unexpected response format:", json.dumps(data, indent=2))
    sys.exit(1)

cert_b64 = attrs["certificateContent"]
serial = attrs.get("serialNumber", "(unknown)")
display_name = attrs.get("displayName", common_name)
expiry = attrs.get("expirationDate", "(unknown)")

# Write the public cert as PEM so openssl pkcs12 can pair it with the key.
# Skip if it already exists (resume case). Always use UTF-8 explicitly —
# Windows Python defaults to cp1252 which breaks on non-ASCII content.
cert_pem_file = Path(cert_pem_path)
if not cert_pem_file.exists() or cert_pem_file.stat().st_size == 0:
    pem_lines = ["-----BEGIN CERTIFICATE-----"]
    pem_lines.extend(textwrap.wrap(cert_b64, 64))
    pem_lines.append("-----END CERTIFICATE-----")
    cert_pem_file.write_text("\n".join(pem_lines) + "\n", encoding="utf-8")

# Write the renewal record. Use ASCII-only punctuation (no arrows, em
# dashes, etc.) so the record is readable regardless of the reader's
# terminal/editor encoding and immune to Windows cp1252 issues even if
# we forget the encoding= kwarg somewhere.
renewal_window_note = (
    f"Renew any time in the 30-day window before {expiry}."
    if expiry != "(unknown)"
    else "Renewal window unknown - check cert expiry in Apple Developer portal."
)

record = f"""# Recipe App - iOS {human_type} Signing Identity

**DO NOT COMMIT.** This file is gitignored under `secrets/`.

## Cert details

| Field | Value |
| --- | --- |
| Common Name | {display_name} |
| Type | {asc_cert_type} |
| Serial Number | {serial} |
| Expiry | {expiry} |
| ASC Resource ID | {resource_id} |
| Issuing Apple ID | (whichever ID owns team 3JR8WTJUV6) |
| Local .p12 path | {p12_path} |

## Renewal

{renewal_window_note}

### Renewal procedure (when expiry approaches)

1. Revoke this cert in Apple Developer portal -> Certificates ->
   find serial `{serial}` -> Revoke.
2. Remove the expired identity from Codemagic (Teams -> Code signing
   identities -> `{codemagic_ref_name}` -> Delete).
3. Delete the old local artifacts:
   `rm secrets/ios_{prefix}.p12 secrets/ios_{prefix}_cert_record.md secrets/p12_password.txt`
4. Re-run the ceremony from the repo root:
   ```bash
   source secrets/env.sh
   # Write the new password as raw bytes, no trailing newline. Never go
   # through shell variables — histexpand and friends will corrupt `!`.
   printf '%s' 'NEW-STRONG-PASSWORD-HERE' > secrets/p12_password.txt
   ./scripts/generate-signing-identity.sh --type {human_type.lower()}
   ```
5. Upload the new `secrets/ios_{prefix}.p12` to Codemagic under the same
   name `{codemagic_ref_name}` so no `codemagic.yaml` changes are needed.
6. Save the new renewal record (this file, regenerated) to your
   password manager / saved email.

### Prerequisites for renewal

- `codemagic-cli-tools` installed: `pip install codemagic-cli-tools`
- ASC API key file at `secrets/AuthKey_Y9UV32NQUW.p8` (rotate the key
  itself in App Store Connect if compromised or lost)
- `secrets/env.sh` exporting `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_KEY_IDENTIFIER`, `APP_STORE_CONNECT_PRIVATE_KEY`
- New `P12_PASSWORD` exported in the shell before running the script
  (do NOT reuse the old .p12 password; rotate with the cert)

## P12 password

The .p12 password is stored separately in your password manager under
the entry "Recipe App - iOS {human_type} cert .p12". This file does
NOT contain the password.
"""
Path(record_path).write_text(record, encoding="utf-8")
print(f"wrote {cert_pem_path}")
print(f"wrote {record_path}")
print(f"serial={serial}")
print(f"expiry={expiry}")
print(f"resource_id={resource_id}")
PY

# ---------------------------------------------------------------------------
# 5. Bundle key + cert into password-protected .p12
# ---------------------------------------------------------------------------
info "bundling key + cert into $P12_PATH"
openssl pkcs12 -export \
    -inkey "$PRIVATE_KEY" \
    -in "$CERT_PEM" \
    -out "$P12_PATH" \
    -name "$COMMON_NAME" \
    -passout file:"$P12_PASSWORD_FILE"

# Immediately round-trip the password to catch any byte-level surprises
# while the key material is still on disk and easy to rebuild.
openssl pkcs12 -in "$P12_PATH" -noout -passin file:"$P12_PASSWORD_FILE" \
    || die "p12 rebuild failed round-trip verification"
info "p12 password round-trip verified"

# ---------------------------------------------------------------------------
# 6. Compute .p12 fingerprint for the renewal record
# ---------------------------------------------------------------------------
P12_SHA256=$(openssl dgst -sha256 "$P12_PATH" | awk '{print $NF}')
info "p12 sha256: $P12_SHA256"

# Append fingerprint to the record
python - "$RECORD_MD" "$P12_SHA256" <<'PY'
import sys
from pathlib import Path
record_path, fp = sys.argv[1:]
text = Path(record_path).read_text(encoding="utf-8")
text = text.replace("| Local .p12 path |", f"| SHA-256 of .p12 | `{fp}` |\n| Local .p12 path |")
Path(record_path).write_text(text, encoding="utf-8")
PY

# ---------------------------------------------------------------------------
# 7. Final output
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  CEREMONY COMPLETE"
echo "============================================================"
echo ""
echo "P12 path:        $P12_PATH"
echo "P12 SHA-256:     $P12_SHA256"
echo "Renewal record:  $RECORD_MD"
echo ""
echo "============================================================"
echo "  RENEWAL RECORD — save this to password manager/email"
echo "============================================================"
cat "$RECORD_MD"
echo ""
echo "============================================================"
echo "  NEXT STEPS"
echo "============================================================"
echo "1. Upload $P12_PATH to Codemagic:"
echo "   Teams -> Code signing identities -> Upload iOS cert"
echo "   Reference name: $CODEMAGIC_REF_NAME"
echo "   Password: (from your password manager)"
echo "2. The .p12 password is in: $P12_PASSWORD_FILE"
echo "   Copy it to Codemagic with:  cat $P12_PASSWORD_FILE"
echo "   (no echo/printf wrapping — cat prints exact bytes with no newline)"
echo "3. After Codemagic confirms the upload, delete these intermediate files:"
echo "     rm $PRIVATE_KEY $CERT_PEM $RESPONSE_JSON"
echo "   KEEP $P12_PATH, $RECORD_MD, and $P12_PASSWORD_FILE until the next"
echo "   Codemagic build verifies the identity works, then move all three"
echo "   to your password manager attachment store."
