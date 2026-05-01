#!/usr/bin/env bash
# Build frontend and deploy server + SPA to Cloud Run.
# Usage: ./scripts/deploy-web.sh [--skip-build]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRONTEND_DIR="$REPO_ROOT/frontend"
SERVER_DIR="$REPO_ROOT/server"
REGION="us-west1"
SERVICE="recipe-api"

# Build frontend unless --skip-build
if [[ "${1:-}" != "--skip-build" ]]; then
  echo "==> Building frontend..."
  cd "$FRONTEND_DIR"
  VITE_API_URL=/api/v1 npm run build
fi

# Copy dist into server/static
echo "==> Copying frontend dist to server/static..."
rm -rf "$SERVER_DIR/static"
cp -r "$FRONTEND_DIR/dist" "$SERVER_DIR/static"

# Deploy
echo "==> Deploying to Cloud Run ($SERVICE in $REGION)..."
cd "$SERVER_DIR"
gcloud run deploy "$SERVICE" \
  --source . \
  --region "$REGION" \
  --allow-unauthenticated

echo "==> Done."
