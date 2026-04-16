#!/usr/bin/env python3
"""Layout analysis evaluation harness.

Runs one or more layout detection models against recipe page images and
produces annotated outputs + JSON results for comparison.

Usage:
    python evaluate.py                           # all models, default image dir
    python evaluate.py --model heuristic         # single model
    python evaluate.py --model heuristic --model dit  # specific models
    python evaluate.py --images path/to/photos   # custom image dir
    python evaluate.py --compare                 # side-by-side comparison images

Results go to data/layout-bench/results/ by default.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

# Allow running from the script directory or the repo root.
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from models import MODELS  # noqa: E402 — lightweight, no heavy deps
from models.base import LayoutResult, QualityAssessment, Region  # noqa: E402


def _check_deps() -> None:
    """Verify heavy dependencies are installed before running."""
    missing: list[str] = []
    for pkg in ("PIL", "matplotlib", "numpy"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(
            f"Missing dependencies: {', '.join(missing)}\n"
            f"Install with: pip install -r {SCRIPT_DIR / 'requirements.txt'}"
        )
        sys.exit(1)

REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_IMAGE_DIR = REPO_ROOT / "data" / "layout-bench" / "images"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "data" / "layout-bench" / "results"
GROUND_TRUTH_DIR = REPO_ROOT / "data" / "layout-bench" / "ground-truth"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}


def find_images(image_dir: Path) -> list[Path]:
    """Find all image files in the given directory."""
    images = sorted(
        p for p in image_dir.iterdir()
        if p.suffix.lower() in IMAGE_EXTENSIONS
    )
    return images


def run_model(
    model_name: str,
    image_path: Path,
    max_regions: int = 10,
) -> tuple[LayoutResult, QualityAssessment | None]:
    """Run a single model on a single image and return results + quality."""
    from models import get_model
    from PIL import Image

    model = get_model(model_name)
    # Pass max_regions to models that support consolidation.
    if hasattr(model, "max_regions"):
        model.max_regions = max_regions
    image = Image.open(image_path).convert("RGB")

    t0 = time.perf_counter()
    regions = model.analyze(image)
    elapsed_ms = (time.perf_counter() - t0) * 1000

    # Extract quality assessment if the model provides one.
    quality = getattr(model, "quality_assessment", None)

    result = LayoutResult(
        image_path=str(image_path),
        regions=regions,
        elapsed_ms=elapsed_ms,
        model_name=model_name,
    )
    return result, quality


def load_ground_truth(image_path: Path) -> list[dict] | None:
    """Load ground-truth annotations if they exist.

    Ground truth files are JSON with the same stem as the image:
        data/layout-bench/ground-truth/my_recipe.json

    Format:
        [
            {"bbox": [left, top, right, bottom], "label": "ingredients"},
            {"bbox": [left, top, right, bottom], "label": "instructions"},
            ...
        ]
    """
    gt_path = GROUND_TRUTH_DIR / f"{image_path.stem}.json"
    if gt_path.exists():
        with open(gt_path) as f:
            return json.load(f)
    return None


def compute_metrics(
    regions: list[Region],
    ground_truth: list[dict],
) -> dict:
    """Compute simple accuracy metrics against ground truth.

    Uses IoU (intersection over union) matching between predicted and
    ground-truth bounding boxes, then checks label agreement.
    """
    matched = 0
    label_correct = 0

    for gt in ground_truth:
        gt_bbox = tuple(gt["bbox"])
        gt_label = gt["label"]
        best_iou = 0.0
        best_region: Region | None = None

        for region in regions:
            iou = _compute_iou(region.bbox, gt_bbox)
            if iou > best_iou:
                best_iou = iou
                best_region = region

        if best_iou >= 0.5:
            matched += 1
            if best_region and best_region.label.value == gt_label:
                label_correct += 1

    n_gt = len(ground_truth)
    n_pred = len(regions)
    return {
        "ground_truth_count": n_gt,
        "predicted_count": n_pred,
        "matched_regions": matched,
        "label_correct": label_correct,
        "recall": matched / n_gt if n_gt > 0 else 0.0,
        "precision": matched / n_pred if n_pred > 0 else 0.0,
        "label_accuracy": label_correct / matched if matched > 0 else 0.0,
    }


def _compute_iou(
    box_a: tuple[int, ...],
    box_b: tuple[int, ...],
) -> float:
    """Intersection over union between two (left, top, right, bottom) boxes."""
    x1 = max(box_a[0], box_b[0])
    y1 = max(box_a[1], box_b[1])
    x2 = min(box_a[2], box_b[2])
    y2 = min(box_a[3], box_b[3])

    intersection = max(0, x2 - x1) * max(0, y2 - y1)
    area_a = (box_a[2] - box_a[0]) * (box_a[3] - box_a[1])
    area_b = (box_b[2] - box_b[0]) * (box_b[3] - box_b[1])
    union = area_a + area_b - intersection

    return intersection / union if union > 0 else 0.0


def result_to_dict(
    result: LayoutResult,
    metrics: dict | None = None,
    quality: QualityAssessment | None = None,
) -> dict:
    """Serialize a LayoutResult to a JSON-safe dict."""
    d: dict = {
        "image": result.image_path,
        "model": result.model_name,
        "elapsed_ms": round(result.elapsed_ms, 1),
        "region_count": len(result.regions),
        "regions": [
            {
                "bbox": list(r.bbox),
                "label": r.label.value,
                "confidence": round(r.confidence, 3),
                "text": r.text[:200],  # truncate long text
            }
            for r in result.regions
        ],
    }
    if metrics:
        d["metrics"] = metrics
    if quality:
        d["quality"] = {
            "median_confidence": round(quality.median_confidence, 3),
            "low_confidence_ratio": round(quality.low_confidence_ratio, 3),
            "estimated_rotation": round(quality.estimated_rotation, 1),
            "is_acceptable": quality.is_acceptable,
            "reason": quality.reason,
        }
    return d


def print_summary(
    all_results: list[tuple[LayoutResult, dict | None, QualityAssessment | None]],
) -> None:
    """Print a human-readable summary table."""
    print("\n" + "=" * 72)
    print("LAYOUT ANALYSIS RESULTS")
    print("=" * 72)

    for result, metrics, quality in all_results:
        stem = Path(result.image_path).stem
        print(f"\n  {stem} [{result.model_name}] — {result.elapsed_ms:.0f}ms")

        # Quality gate.
        if quality:
            status = "OK" if quality.is_acceptable else "RETAKE"
            print(
                f"    quality: {status}"
                f" (conf={quality.median_confidence:.0%},"
                f" rotation={quality.estimated_rotation:.1f}°,"
                f" low={quality.low_confidence_ratio:.0%})"
            )
            if quality.reason:
                print(f"    reason: {quality.reason}")

        # Count by label.
        label_counts: dict[str, int] = {}
        for region in result.regions:
            label_counts[region.label.value] = (
                label_counts.get(region.label.value, 0) + 1
            )
        for label, count in sorted(label_counts.items()):
            print(f"    {label:15s}: {count}")

        if metrics:
            print(f"    --- metrics ---")
            print(f"    precision:      {metrics['precision']:.1%}")
            print(f"    recall:         {metrics['recall']:.1%}")
            print(f"    label accuracy: {metrics['label_accuracy']:.1%}")

    print("\n" + "=" * 72)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Evaluate layout analysis models on recipe page images",
    )
    parser.add_argument(
        "--model",
        action="append",
        dest="models",
        choices=list(MODELS.keys()),
        help="Model(s) to evaluate (default: all available)",
    )
    parser.add_argument(
        "--images",
        type=Path,
        default=DEFAULT_IMAGE_DIR,
        help=f"Directory of recipe page images (default: {DEFAULT_IMAGE_DIR})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for results (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--compare",
        action="store_true",
        help="Generate side-by-side comparison images",
    )
    parser.add_argument(
        "--max-regions",
        type=int,
        default=10,
        help="Target max regions per image (consolidation stops here)",
    )
    args = parser.parse_args()

    # Check dependencies before doing real work.
    _check_deps()
    from PIL import Image
    from visualize import save_annotated, save_comparison

    model_names = args.models or list(MODELS.keys())
    image_dir: Path = args.images
    output_dir: Path = args.output

    if not image_dir.exists():
        print(f"Image directory not found: {image_dir}")
        print(f"Drop recipe photos into {image_dir} and re-run.")
        sys.exit(1)

    images = find_images(image_dir)
    if not images:
        print(f"No images found in {image_dir}")
        print(f"Supported formats: {', '.join(sorted(IMAGE_EXTENSIONS))}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Images:  {len(images)} in {image_dir}")
    print(f"Models:  {', '.join(model_names)}")
    print(f"Output:  {output_dir}")

    all_results: list[tuple[LayoutResult, dict | None, QualityAssessment | None]] = []
    # Per-image results grouped for comparison.
    per_image: dict[str, list[LayoutResult]] = {}

    for image_path in images:
        print(f"\n--- {image_path.name} ---")
        image = Image.open(image_path).convert("RGB")
        ground_truth = load_ground_truth(image_path)

        for model_name in model_names:
            print(f"  Running {model_name}...")
            result, quality = run_model(
                model_name, image_path, max_regions=args.max_regions,
            )

            if quality and quality.should_retake:
                print(f"    QUALITY GATE: {quality.reason}")

            metrics = None
            if ground_truth:
                metrics = compute_metrics(result.regions, ground_truth)

            all_results.append((result, metrics, quality))
            per_image.setdefault(str(image_path), []).append(result)

            # Save annotated image.
            out_path = save_annotated(result, image, output_dir)
            print(f"    -> {out_path.name}")

    # Side-by-side comparisons.
    if args.compare and len(model_names) > 1:
        print("\nGenerating comparisons...")
        for image_path_str, results in per_image.items():
            image = Image.open(image_path_str).convert("RGB")
            out_path = save_comparison(results, image, output_dir)
            print(f"  -> {out_path.name}")

    # Save JSON results.
    json_results = [
        result_to_dict(result, metrics, quality)
        for result, metrics, quality in all_results
    ]
    json_path = output_dir / "results.json"
    with open(json_path, "w") as f:
        json.dump(json_results, f, indent=2)
    print(f"\nJSON results: {json_path}")

    print_summary(all_results)


if __name__ == "__main__":
    main()
