-- Migration: add sync watermark (updated_at) to grocery/shopping/template tables.
--
-- Context: the deployed Neon database was created from database/init.sql (there is
-- no Alembic env/versions in this repo; the app does not run create_all at startup).
-- The grocery tables already exist on Neon, so this migration ALTERs them in place.
--
-- Apply on deploy (human step — do NOT run automatically against production):
--   psql "$DATABASE_URL" -f server/migrations/2026-07-14-grocery-updated-at.sql
--
-- Idempotent: uses IF NOT EXISTS so re-running is safe.

ALTER TABLE grocery_lists
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE grocery_items
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE shopping_templates
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE template_items
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Backfill existing rows so watermarks are non-null and monotonic-friendly.
UPDATE grocery_lists      SET updated_at = COALESCE(updated_at, created_at, NOW()) WHERE updated_at IS NULL;
UPDATE grocery_items      SET updated_at = COALESCE(updated_at, NOW())             WHERE updated_at IS NULL;
UPDATE shopping_templates SET updated_at = COALESCE(updated_at, created_at, NOW()) WHERE updated_at IS NULL;
UPDATE template_items     SET updated_at = COALESCE(updated_at, NOW())             WHERE updated_at IS NULL;
