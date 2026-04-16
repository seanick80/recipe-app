#!/usr/bin/env bash
#
# Generates a bullet list of user-facing changes suitable for TestFlight's
# "What to Test" field. Reads the N most recent commits (default 5), keeps
# only `feat:` / `fix:` entries, and appends any `Fixes GM-N` trailers as
# Linear references. Falls back to a neutral blurb if no qualifying
# commits are found (empty notes are rejected by App Store Connect).
#
# Usage:
#   ./scripts/generate-release-notes.sh                 # writes to stdout
#   ./scripts/generate-release-notes.sh > notes.txt     # typical CI use
#
# Env:
#   RELEASE_NOTES_COMMIT_COUNT   how far back to look (default: 5)

set -euo pipefail

MAX_COMMITS="${RELEASE_NOTES_COMMIT_COUNT:-5}"
FALLBACK="Bug fixes and improvements."

collected=""

while IFS= read -r sha; do
    subject=$(git log -1 --pretty=%s "${sha}")
    case "${subject}" in
        feat:* | fix:*) ;;
        *) continue ;;
    esac

    # Strip the conventional-commit prefix ("fix: foo" -> "foo").
    clean="${subject#*: }"

    # Capitalize first letter for TestFlight readability.
    first="$(printf '%s' "${clean:0:1}" | tr '[:lower:]' '[:upper:]')"
    clean="${first}${clean:1}"

    # Pull any GM-N references out of the commit body for traceability.
    # `|| true` swallows the grep-no-match exit under `set -o pipefail`.
    ids=$(git log -1 --pretty=%B "${sha}" \
        | grep -oE 'GM-[0-9]+' \
        | sort -u \
        | paste -sd, - || true)

    if [[ -n "${ids}" ]]; then
        line="• ${clean} (${ids})"
    else
        line="• ${clean}"
    fi

    collected+="${line}"$'\n'
done < <(git log -n "${MAX_COMMITS}" --pretty=%H)

if [[ -z "${collected}" ]]; then
    echo "${FALLBACK}"
else
    printf '%s' "${collected}"
fi
