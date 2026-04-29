#!/usr/bin/env bash
# maintenance.sh — Weekly maintenance for the Recipe App database.
#
# Tasks:
#   1. Purge soft-deleted recipes older than 30 days
#   2. Backup via pg_dump with anomaly detection
#   3. Check Neon free-tier quota usage
#
# Usage:
#   ./scripts/maintenance.sh                # run all tasks
#   ./scripts/maintenance.sh --dry-run      # show plan, don't execute
#   ./scripts/maintenance.sh --skip-backup  # skip backup step
#   ./scripts/maintenance.sh --skip-purge   # skip purge step
#   ./scripts/maintenance.sh --skip-quota   # skip quota check
#
# Requires: psql, pg_dump, gzip
# Optional: gsutil (for Cloud Storage upload)
#
# Environment:
#   DATABASE_URL — Neon PostgreSQL connection string (required)
#                  Can also be loaded from secrets/neon.env

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
METADATA_FILE="$BACKUP_DIR/last_backup_metadata.json"
RETENTION_DAYS=30
MAX_BACKUPS=4
ANOMALY_THRESHOLD=20  # percentage change that triggers failure

# -- Parse flags ---------------------------------------------------------------

DRY_RUN=false
SKIP_BACKUP=false
SKIP_PURGE=false
SKIP_QUOTA=false

for arg in "$@"; do
    case "$arg" in
        --dry-run)     DRY_RUN=true ;;
        --skip-backup) SKIP_BACKUP=true ;;
        --skip-purge)  SKIP_PURGE=true ;;
        --skip-quota)  SKIP_QUOTA=true ;;
        *)             echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

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
    echo "ERROR: DATABASE_URL not set. Provide it via environment or secrets/neon.env"
    exit 1
fi

echo "=== Recipe App Maintenance ==="
echo "  Database: ${DATABASE_URL%%@*}@***"
echo "  Dry run:  $DRY_RUN"
echo ""

# -- Task 1: Purge expired soft-deletes ----------------------------------------

purge_expired() {
    echo "--- Task 1: Purge expired soft-deletes (>${RETENTION_DAYS} days) ---"

    local count
    count=$(psql "$DATABASE_URL" -t -A -c \
        "SELECT COUNT(*) FROM recipes
         WHERE deleted_at IS NOT NULL
           AND deleted_at < NOW() - INTERVAL '${RETENTION_DAYS} days';")

    echo "  Expired recipes found: $count"

    if [[ "$count" -eq 0 ]]; then
        echo "  Nothing to purge."
        return
    fi

    if $DRY_RUN; then
        echo "  [DRY RUN] Would hard-delete $count recipes (and their ingredients via CASCADE)."
        return
    fi

    # Delete ingredients first (CASCADE would handle it, but be explicit)
    psql "$DATABASE_URL" -c \
        "DELETE FROM ingredients WHERE recipe_id IN (
             SELECT id FROM recipes
             WHERE deleted_at IS NOT NULL
               AND deleted_at < NOW() - INTERVAL '${RETENTION_DAYS} days'
         );"

    psql "$DATABASE_URL" -c \
        "DELETE FROM recipes
         WHERE deleted_at IS NOT NULL
           AND deleted_at < NOW() - INTERVAL '${RETENTION_DAYS} days';"

    echo "  Purged $count expired recipes."
}

# -- Task 2: Backup with anomaly detection -------------------------------------

backup_database() {
    echo "--- Task 2: Database backup ---"

    mkdir -p "$BACKUP_DIR"

    # Gather current record counts
    local recipe_count ingredient_count user_count
    recipe_count=$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM recipes;")
    ingredient_count=$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM ingredients;")
    user_count=$(psql "$DATABASE_URL" -t -A -c "SELECT COUNT(*) FROM allowed_users;")

    echo "  Current counts: recipes=$recipe_count, ingredients=$ingredient_count, users=$user_count"

    # Anomaly detection: compare against previous backup
    if [[ -f "$METADATA_FILE" ]]; then
        local prev_recipes prev_ingredients
        prev_recipes=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['recipe_count'])" 2>/dev/null || echo "0")
        prev_ingredients=$(python3 -c "import json; print(json.load(open('$METADATA_FILE'))['ingredient_count'])" 2>/dev/null || echo "0")

        if [[ "$prev_recipes" -gt 0 ]]; then
            local pct_change
            pct_change=$(python3 -c "
prev, curr = $prev_recipes, $recipe_count
pct = abs(curr - prev) / prev * 100 if prev > 0 else 0
print(f'{pct:.1f}')
")
            echo "  Recipe count change: $prev_recipes → $recipe_count (${pct_change}%)"

            # Check if change exceeds threshold
            local anomaly
            anomaly=$(python3 -c "print('yes' if float('$pct_change') > $ANOMALY_THRESHOLD else 'no')")
            if [[ "$anomaly" == "yes" ]]; then
                echo "  ANOMALY DETECTED: recipe count changed by ${pct_change}% (threshold: ${ANOMALY_THRESHOLD}%)"
                echo "  Backup ABORTED to prevent overwriting a good backup with bad data."
                echo "  Review the database manually, then re-run with confidence."
                return 1
            fi
        fi
    fi

    if $DRY_RUN; then
        echo "  [DRY RUN] Would create backup in $BACKUP_DIR"
        return
    fi

    # Create backup
    local timestamp backup_file
    timestamp=$(date +%Y%m%d_%H%M%S)
    backup_file="$BACKUP_DIR/recipe_app_${timestamp}.sql.gz"

    echo "  Creating backup: $backup_file"
    pg_dump "$DATABASE_URL" --no-owner --no-acl | gzip > "$backup_file"

    local backup_size
    backup_size=$(stat -c%s "$backup_file" 2>/dev/null || stat -f%z "$backup_file" 2>/dev/null || echo "0")
    echo "  Backup size: $((backup_size / 1024)) KB"

    if [[ "$backup_size" -lt 100 ]]; then
        echo "  WARNING: Backup file suspiciously small ($backup_size bytes). Check for errors."
        rm -f "$backup_file"
        return 1
    fi

    # Write metadata sidecar
    python3 -c "
import json, datetime
metadata = {
    'timestamp': '$timestamp',
    'recipe_count': $recipe_count,
    'ingredient_count': $ingredient_count,
    'user_count': $user_count,
    'backup_size_bytes': $backup_size,
    'backup_file': '$(basename "$backup_file")',
    'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat()
}
with open('$METADATA_FILE', 'w') as f:
    json.dump(metadata, f, indent=2)
"
    echo "  Metadata written to $METADATA_FILE"

    # Upload to Cloud Storage if gsutil is available
    if command -v gsutil &>/dev/null; then
        local bucket="gs://recipe-app-backups"
        echo "  Uploading to $bucket..."
        gsutil cp "$backup_file" "$bucket/$(basename "$backup_file")"
        echo "  Upload complete."
    else
        echo "  gsutil not found — backup saved locally only."
    fi

    # Rotate: keep only MAX_BACKUPS most recent
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "recipe_app_*.sql.gz" | wc -l)
    if [[ "$backup_count" -gt "$MAX_BACKUPS" ]]; then
        local to_delete=$((backup_count - MAX_BACKUPS))
        echo "  Rotating: removing $to_delete old backup(s)"
        find "$BACKUP_DIR" -name "recipe_app_*.sql.gz" -printf '%T@ %p\n' \
            | sort -n | head -n "$to_delete" | awk '{print $2}' \
            | xargs rm -f
    fi

    echo "  Backup complete."
}

# -- Task 3: Quota check ------------------------------------------------------

check_quota() {
    echo "--- Task 3: Neon free-tier quota check ---"

    # Query database size
    local db_size_bytes db_size_mb
    db_size_bytes=$(psql "$DATABASE_URL" -t -A -c \
        "SELECT pg_database_size(current_database());")
    db_size_mb=$(python3 -c "print(f'{$db_size_bytes / 1024 / 1024:.1f}')")

    # Neon free tier: 512 MB storage
    local storage_limit_mb=512
    local usage_pct
    usage_pct=$(python3 -c "print(f'{$db_size_bytes / ($storage_limit_mb * 1024 * 1024) * 100:.1f}')")

    echo "  Database size: ${db_size_mb} MB / ${storage_limit_mb} MB (${usage_pct}%)"

    local warning
    warning=$(python3 -c "print('yes' if float('$usage_pct') > 80 else 'no')")
    if [[ "$warning" == "yes" ]]; then
        echo "  WARNING: Database storage usage above 80%. Consider cleanup or upgrade."
    fi

    # Row counts summary
    echo "  Table row counts:"
    psql "$DATABASE_URL" -t -A -c \
        "SELECT tablename, n_live_tup
         FROM pg_stat_user_tables
         ORDER BY n_live_tup DESC;" \
    | while IFS='|' read -r table rows; do
        printf "    %-25s %s rows\n" "$table" "$rows"
    done

    if $DRY_RUN; then
        echo "  [DRY RUN] Quota check is read-only — no changes to skip."
    fi
}

# -- Run tasks -----------------------------------------------------------------

exit_code=0

if ! $SKIP_PURGE; then
    purge_expired || exit_code=1
    echo ""
fi

if ! $SKIP_BACKUP; then
    backup_database || exit_code=1
    echo ""
fi

if ! $SKIP_QUOTA; then
    check_quota || exit_code=1
    echo ""
fi

if [[ "$exit_code" -eq 0 ]]; then
    echo "=== Maintenance complete ==="
else
    echo "=== Maintenance completed with errors (exit code $exit_code) ==="
fi

exit $exit_code
