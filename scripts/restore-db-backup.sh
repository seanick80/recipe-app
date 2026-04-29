#!/usr/bin/env bash
# restore-db-backup.sh — Restore a Recipe App database from a backup file.
#
# Usage:
#   ./scripts/restore-db-backup.sh                           # list available backups
#   ./scripts/restore-db-backup.sh backups/recipe_app_20260429_120000.sql.gz
#   ./scripts/restore-db-backup.sh gs://recipe-app-backups/recipe_app_20260429_120000.sql.gz
#
# Requires: psql, gunzip
# Optional: gsutil (for Cloud Storage downloads)
#
# Environment:
#   DATABASE_URL — Neon PostgreSQL connection string (required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"

# -- Load DATABASE_URL ---------------------------------------------------------

if [[ -z "${DATABASE_URL:-}" ]]; then
    if [[ -f "$PROJECT_DIR/secrets/neon.env" ]]; then
        # shellcheck disable=SC1091
        source "$PROJECT_DIR/secrets/neon.env"
    elif [[ -f "$PROJECT_DIR/server/.env" ]]; then
        # shellcheck disable=SC1091
        source "$PROJECT_DIR/server/.env"
    fi
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "ERROR: DATABASE_URL not set."
    exit 1
fi

# -- List backups if no argument -----------------------------------------------

if [[ $# -eq 0 ]]; then
    echo "=== Available local backups ==="
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -name "recipe_app_*.sql.gz" -printf '%T@ %p\n' \
            | sort -rn | awk '{print $2}' \
            | while read -r f; do
                local_size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "?")
                echo "  $f  ($((local_size / 1024)) KB)"
            done
    else
        echo "  No backups directory found."
    fi

    if command -v gsutil &>/dev/null; then
        echo ""
        echo "=== Cloud Storage backups ==="
        gsutil ls -l "gs://recipe-app-backups/recipe_app_*.sql.gz" 2>/dev/null \
            || echo "  No cloud backups found or bucket not accessible."
    fi

    echo ""
    echo "Usage: $0 <backup-file-or-gs-url>"
    exit 0
fi

BACKUP_SOURCE="$1"

# -- Download from Cloud Storage if needed -------------------------------------

if [[ "$BACKUP_SOURCE" == gs://* ]]; then
    if ! command -v gsutil &>/dev/null; then
        echo "ERROR: gsutil required to download from Cloud Storage."
        exit 1
    fi
    local_file="/tmp/$(basename "$BACKUP_SOURCE")"
    echo "Downloading $BACKUP_SOURCE → $local_file"
    gsutil cp "$BACKUP_SOURCE" "$local_file"
    BACKUP_SOURCE="$local_file"
fi

if [[ ! -f "$BACKUP_SOURCE" ]]; then
    echo "ERROR: File not found: $BACKUP_SOURCE"
    exit 1
fi

# -- Confirm restore -----------------------------------------------------------

echo ""
echo "=== Database Restore ==="
echo "  Backup:   $BACKUP_SOURCE"
echo "  Database: ${DATABASE_URL%%@*}@***"
echo ""

# Current state
echo "Current database state:"
psql "$DATABASE_URL" -t -A -c \
    "SELECT 'recipes', COUNT(*) FROM recipes
     UNION ALL
     SELECT 'ingredients', COUNT(*) FROM ingredients
     UNION ALL
     SELECT 'users', COUNT(*) FROM allowed_users;" \
| while IFS='|' read -r table count; do
    printf "  %-15s %s rows\n" "$table" "$count"
done

echo ""
echo "WARNING: This will DROP all existing data and restore from the backup."
read -rp "Type 'yes' to proceed: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 1
fi

# -- Restore -------------------------------------------------------------------

echo ""
echo "Dropping existing tables..."
psql "$DATABASE_URL" -c "
    DROP TABLE IF EXISTS template_items CASCADE;
    DROP TABLE IF EXISTS shopping_templates CASCADE;
    DROP TABLE IF EXISTS grocery_items CASCADE;
    DROP TABLE IF EXISTS grocery_lists CASCADE;
    DROP TABLE IF EXISTS ingredients CASCADE;
    DROP TABLE IF EXISTS recipes CASCADE;
    DROP TABLE IF EXISTS allowed_users CASCADE;
"

echo "Restoring from backup..."
gunzip -c "$BACKUP_SOURCE" | psql "$DATABASE_URL" --quiet

echo ""
echo "Restored database state:"
psql "$DATABASE_URL" -t -A -c \
    "SELECT 'recipes', COUNT(*) FROM recipes
     UNION ALL
     SELECT 'ingredients', COUNT(*) FROM ingredients
     UNION ALL
     SELECT 'users', COUNT(*) FROM allowed_users;" \
| while IFS='|' read -r table count; do
    printf "  %-15s %s rows\n" "$table" "$count"
done

echo ""
echo "=== Restore complete ==="
