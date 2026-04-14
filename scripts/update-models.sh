#!/usr/bin/env bash
# scripts/update-models.sh — regenerate CoreML models from upstream sources.
#
# Requires macOS with Python 3 and pip. Installs coremltools, tensorflow,
# huggingface_hub, Pillow, numpy into the current Python environment.
#
# Run this whenever:
#   - Switching to a different upstream model
#   - Retraining / fine-tuning a model
#   - Changing class labels or category mappings
#   - Updating coremltools conversion options (quantization, etc.)
#
# The converted .mlpackage dirs are checked into git under
# RecipeApp/RecipeApp/MLModels/. CI does NOT regenerate them — it uses
# whatever is committed.
#
# Usage:
#   ./scripts/update-models.sh              # convert and overwrite
#   ./scripts/update-models.sh --dry-run    # show what would be done

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$REPO_ROOT/RecipeApp/RecipeApp/MLModels"
CONVERT_SCRIPT="$REPO_ROOT/scripts/convert-food-model.py"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Preflight checks
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "ERROR: CoreML conversion requires macOS (coremltools constraint)."
    echo "Run this on a Mac or in a macOS CI job."
    exit 1
fi

PYTHON=$(command -v python3 2>/dev/null || echo "")
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: python3 not found."
    exit 1
fi

if $DRY_RUN; then
    echo "[dry-run] Would install: coremltools torch torchvision transformers Pillow numpy"
    echo "[dry-run] Would run: $PYTHON $CONVERT_SCRIPT"
    echo "[dry-run] Output dir: $MODELS_DIR"
    echo "[dry-run] Models would be:"
    echo "  - $MODELS_DIR/FoodClassifier.mlpackage"
    exit 0
fi

echo "==> Installing Python dependencies"
pip3 install --quiet coremltools torch torchvision transformers Pillow numpy

echo "==> Converting models"
"$PYTHON" "$CONVERT_SCRIPT"

echo ""
echo "==> Models updated:"
du -sh "$MODELS_DIR"/*.mlpackage 2>/dev/null || echo "  (none found — check for errors above)"

echo ""
echo "==> Next steps:"
echo "  1. Review model sizes above"
echo "  2. git add RecipeApp/RecipeApp/MLModels/*.mlpackage"
echo "  3. Commit and push"
