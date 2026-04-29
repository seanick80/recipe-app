"""Weekly maintenance for the Recipe App database.

Tasks:
    1. Purge soft-deleted recipes older than 30 days
    2. Backup via pg_dump with anomaly detection
    3. Check Neon free-tier quota usage

Usage:
    python maintenance.py                # run all tasks
    python maintenance.py --dry-run      # show plan, don't execute
    python maintenance.py --skip-backup  # skip backup step
    python maintenance.py --skip-purge   # skip purge step
    python maintenance.py --skip-quota   # skip quota check

Environment:
    DATABASE_URL — Neon PostgreSQL connection string (required)
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import create_engine, text

RETENTION_DAYS = 30
MAX_BACKUPS = 4
ANOMALY_THRESHOLD = 20  # percentage change that triggers failure
NEON_STORAGE_LIMIT_MB = 512


def get_database_url() -> str:
    """Resolve DATABASE_URL from env, secrets, or .env files."""
    url = os.environ.get("DATABASE_URL")
    if url:
        return url

    # Try loading from dotenv files
    for env_path in [
        Path(__file__).parent / ".env",
        Path(__file__).parent.parent / "secrets" / "neon.env",
    ]:
        if env_path.exists():
            for line in env_path.read_text().splitlines():
                line = line.strip()
                if line.startswith("DATABASE_URL="):
                    return line.split("=", 1)[1]

    print("ERROR: DATABASE_URL not set.")
    sys.exit(1)


def redact_url(url: str) -> str:
    """Hide password in connection string for logging."""
    at = url.find("@")
    if at == -1:
        return url
    scheme_end = url.find("://") + 3
    return url[:scheme_end] + "***@" + url[at + 1 :]


def purge_expired(engine, *, dry_run: bool) -> bool:
    """Hard-delete recipes soft-deleted more than RETENTION_DAYS ago."""
    print(f"--- Task 1: Purge expired soft-deletes (>{RETENTION_DAYS} days) ---")

    with engine.connect() as conn:
        row = conn.execute(
            text(
                "SELECT COUNT(*) FROM recipes "
                "WHERE deleted_at IS NOT NULL "
                f"AND deleted_at < NOW() - INTERVAL '{RETENTION_DAYS} days'"
            ),
        ).scalar()
        count = row or 0

    print(f"  Expired recipes found: {count}")

    if count == 0:
        print("  Nothing to purge.")
        return True

    if dry_run:
        print(
            f"  [DRY RUN] Would hard-delete {count} recipes"
            " (and their ingredients via CASCADE).",
        )
        return True

    with engine.begin() as conn:
        conn.execute(
            text(
                "DELETE FROM ingredients WHERE recipe_id IN ("
                "  SELECT id FROM recipes "
                "  WHERE deleted_at IS NOT NULL "
                f"  AND deleted_at < NOW() - INTERVAL '{RETENTION_DAYS} days'"
                ")"
            ),
        )
        conn.execute(
            text(
                "DELETE FROM recipes "
                "WHERE deleted_at IS NOT NULL "
                f"AND deleted_at < NOW() - INTERVAL '{RETENTION_DAYS} days'"
            ),
        )

    print(f"  Purged {count} expired recipes.")
    return True


def backup_database(
    database_url: str,
    backup_dir: Path,
    *,
    dry_run: bool,
    engine,
) -> bool:
    """Backup via pg_dump with anomaly detection."""
    print("--- Task 2: Database backup ---")

    backup_dir.mkdir(parents=True, exist_ok=True)
    metadata_file = backup_dir / "last_backup_metadata.json"

    with engine.connect() as conn:
        recipe_count = conn.execute(
            text("SELECT COUNT(*) FROM recipes"),
        ).scalar()
        ingredient_count = conn.execute(
            text("SELECT COUNT(*) FROM ingredients"),
        ).scalar()
        user_count = conn.execute(
            text("SELECT COUNT(*) FROM allowed_users"),
        ).scalar()

    print(
        f"  Current counts: recipes={recipe_count},"
        f" ingredients={ingredient_count}, users={user_count}",
    )

    # Anomaly detection
    if metadata_file.exists():
        try:
            prev = json.loads(metadata_file.read_text())
            prev_recipes = prev.get("recipe_count", 0)
            if prev_recipes > 0:
                pct_change = abs(recipe_count - prev_recipes) / prev_recipes * 100
                print(
                    f"  Recipe count change:"
                    f" {prev_recipes} -> {recipe_count} ({pct_change:.1f}%)",
                )
                if pct_change > ANOMALY_THRESHOLD:
                    print(
                        f"  ANOMALY DETECTED: recipe count changed by"
                        f" {pct_change:.1f}% (threshold: {ANOMALY_THRESHOLD}%)",
                    )
                    print(
                        "  Backup ABORTED to prevent overwriting"
                        " a good backup with bad data.",
                    )
                    return False
        except (json.JSONDecodeError, KeyError):
            pass

    if dry_run:
        print(f"  [DRY RUN] Would create backup in {backup_dir}")
        return True

    # Check if pg_dump is available
    pg_dump = _find_pg_dump()
    if not pg_dump:
        print("  WARNING: pg_dump not found. Skipping file backup.")
        print("  Record counts saved to metadata for anomaly detection.")
        _write_metadata(
            metadata_file,
            recipe_count=recipe_count,
            ingredient_count=ingredient_count,
            user_count=user_count,
            backup_file=None,
            backup_size=0,
        )
        return True

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_file = backup_dir / f"recipe_app_{timestamp}.sql.gz"

    print(f"  Creating backup: {backup_file}")
    result = subprocess.run(
        [pg_dump, database_url, "--no-owner", "--no-acl"],
        capture_output=True,
    )
    if result.returncode != 0:
        print(f"  pg_dump failed: {result.stderr.decode()}")
        return False

    with gzip.open(backup_file, "wb") as f:
        f.write(result.stdout)

    backup_size = backup_file.stat().st_size
    print(f"  Backup size: {backup_size // 1024} KB")

    if backup_size < 100:
        print(
            f"  WARNING: Backup file suspiciously small"
            f" ({backup_size} bytes). Removing.",
        )
        backup_file.unlink()
        return False

    _write_metadata(
        metadata_file,
        recipe_count=recipe_count,
        ingredient_count=ingredient_count,
        user_count=user_count,
        backup_file=backup_file.name,
        backup_size=backup_size,
    )
    print(f"  Metadata written to {metadata_file}")

    # Upload to Cloud Storage if gsutil is available
    if _has_command("gsutil"):
        bucket = "gs://recipe-app-backups"
        print(f"  Uploading to {bucket}...")
        subprocess.run(
            ["gsutil", "cp", str(backup_file), f"{bucket}/{backup_file.name}"],
            check=True,
        )
        print("  Upload complete.")
    else:
        print("  gsutil not found — backup saved locally only.")

    # Rotate old backups
    backups = sorted(backup_dir.glob("recipe_app_*.sql.gz"))
    if len(backups) > MAX_BACKUPS:
        for old in backups[: len(backups) - MAX_BACKUPS]:
            print(f"  Rotating: removing {old.name}")
            old.unlink()

    print("  Backup complete.")
    return True


def check_quota(engine, *, dry_run: bool) -> bool:
    """Report Neon free-tier storage usage."""
    print("--- Task 3: Neon free-tier quota check ---")

    with engine.connect() as conn:
        db_size_bytes = conn.execute(
            text("SELECT pg_database_size(current_database())"),
        ).scalar()

        rows = conn.execute(
            text(
                "SELECT tablename, n_live_tup "
                "FROM pg_stat_user_tables "
                "ORDER BY n_live_tup DESC"
            ),
        ).fetchall()

    db_size_mb = db_size_bytes / 1024 / 1024
    usage_pct = db_size_bytes / (NEON_STORAGE_LIMIT_MB * 1024 * 1024) * 100

    print(
        f"  Database size: {db_size_mb:.1f} MB"
        f" / {NEON_STORAGE_LIMIT_MB} MB ({usage_pct:.1f}%)",
    )

    if usage_pct > 80:
        print(
            "  WARNING: Database storage usage above 80%."
            " Consider cleanup or upgrade.",
        )

    print("  Table row counts:")
    for table, count in rows:
        print(f"    {table:<25} {count} rows")

    return True


def _find_pg_dump() -> str | None:
    """Find pg_dump binary."""
    for cmd in ["pg_dump", "/usr/bin/pg_dump", "/usr/local/bin/pg_dump"]:
        if _has_command(cmd):
            return cmd
    return None


def _has_command(cmd: str) -> bool:
    """Check if a shell command exists."""
    try:
        subprocess.run(
            ["which", cmd],
            capture_output=True,
            check=True,
        )
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def _write_metadata(
    path: Path,
    *,
    recipe_count: int,
    ingredient_count: int,
    user_count: int,
    backup_file: str | None,
    backup_size: int,
) -> None:
    metadata = {
        "recipe_count": recipe_count,
        "ingredient_count": ingredient_count,
        "user_count": user_count,
        "backup_size_bytes": backup_size,
        "backup_file": backup_file,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    path.write_text(json.dumps(metadata, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Recipe App maintenance")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--skip-purge", action="store_true")
    parser.add_argument("--skip-backup", action="store_true")
    parser.add_argument("--skip-quota", action="store_true")
    args = parser.parse_args()

    database_url = get_database_url()
    backup_dir = Path(__file__).parent.parent / "backups"
    engine = create_engine(database_url)

    print("=== Recipe App Maintenance ===")
    print(f"  Database: {redact_url(database_url)}")
    print(f"  Dry run:  {args.dry_run}")
    print()

    ok = True

    if not args.skip_purge:
        ok = purge_expired(engine, dry_run=args.dry_run) and ok
        print()

    if not args.skip_backup:
        ok = backup_database(
            database_url,
            backup_dir,
            dry_run=args.dry_run,
            engine=engine,
        ) and ok
        print()

    if not args.skip_quota:
        ok = check_quota(engine, dry_run=args.dry_run) and ok
        print()

    if ok:
        print("=== Maintenance complete ===")
    else:
        print("=== Maintenance completed with errors ===")
        sys.exit(1)


if __name__ == "__main__":
    main()
