#!/usr/bin/env python3
"""YOLO pantry-detection evaluation harness.

Runs YOLOv8n (COCO-pretrained, via ultralytics) against pantry photos and
filters detections to a pantry-relevant subset of the 80-class COCO
vocabulary. Emits annotated JPGs + a JSON report so we can eyeball whether
COCO-vocabulary detection is viable for the "what's in the pantry" feature,
or if we need a custom grocery-vocab detector.

Design notes
------------
* Conservative by default: confidence threshold is 0.5. Non-detection is
  preferred over false-detection — most pantry items (cereal boxes, pasta,
  rice, sauce jars) are not in COCO's vocabulary at all, and we'd rather
  report "nothing recognized" than mis-label a box as a bowl.
* Only the PANTRY_RELEVANT class whitelist is surfaced; detections of
  "person", "chair", "car" etc. are silently dropped.
* No ground-truth comparison (yet) — this is an exploratory benchmark to
  decide whether to invest in a custom-trained model.

Usage
-----
    pip install -r scripts/pantry-bench/requirements.txt
    python scripts/pantry-bench/evaluate.py
    python scripts/pantry-bench/evaluate.py --conf 0.6
    python scripts/pantry-bench/evaluate.py --images path/to/photos

Results land in data/pantry-bench/results/.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_IMAGE_DIR = REPO_ROOT / "data" / "pantry_images"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "data" / "pantry-bench" / "results"

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}

# The subset of COCO's 80 classes that could plausibly show up in a pantry
# or kitchen shot. Everything else is dropped even if YOLOv3 finds it with
# high confidence — `person` and `chair` don't belong in a pantry report.
#
# Note the thin overlap with real pantry stock: cereal, pasta, rice, beans,
# canned goods, spices, condiments are all absent from COCO entirely. That's
# exactly what this benchmark is measuring.
PANTRY_RELEVANT: frozenset[str] = frozenset({
    # Fresh produce
    "banana", "apple", "orange", "broccoli", "carrot",
    # Prepared food (rare in a pantry photo but possible on a counter)
    "sandwich", "hot dog", "pizza", "donut", "cake",
    # Containers (jars, bottles, drinkware visible on shelves)
    "bottle", "wine glass", "cup", "bowl",
})


@dataclass
class Detection:
    """Single kept detection for one image."""
    cls: str
    confidence: float
    bbox: tuple[int, int, int, int]  # (xmin, ymin, xmax, ymax)

    def to_json(self) -> dict:
        return {
            "class": self.cls,
            "confidence": round(self.confidence, 3),
            "bbox": list(self.bbox),
        }


@dataclass
class ImageResult:
    image: str
    elapsed_ms: float
    kept: list[Detection]
    dropped_low_conf: int
    dropped_non_pantry: int

    def to_json(self) -> dict:
        return {
            "image": self.image,
            "elapsed_ms": round(self.elapsed_ms, 1),
            "kept": [d.to_json() for d in self.kept],
            "dropped_low_conf": self.dropped_low_conf,
            "dropped_non_pantry": self.dropped_non_pantry,
        }


def _check_deps() -> None:
    missing: list[str] = []
    for pkg in ("torch", "PIL", "pandas"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        print(
            f"Missing dependencies: {', '.join(missing)}\n"
            f"Install with: pip install -r {SCRIPT_DIR / 'requirements.txt'}",
            file=sys.stderr,
        )
        sys.exit(1)


def find_images(image_dir: Path) -> list[Path]:
    return sorted(
        p for p in image_dir.iterdir()
        if p.suffix.lower() in IMAGE_EXTENSIONS
    )


def load_model(conf_threshold: float):
    """Load YOLOv8n via ultralytics. First call downloads ~6MB weights."""
    from ultralytics import YOLO

    print("Loading YOLOv8n (ultralytics, cached after first run)...")
    t0 = time.perf_counter()
    model = YOLO("yolov8n.pt")
    model.conf = conf_threshold
    elapsed = time.perf_counter() - t0
    print(f"  loaded in {elapsed:.1f}s")
    return model


def analyze_image(model, image_path: Path, conf_threshold: float) -> ImageResult:
    """Run YOLOv8n on one image and filter to pantry-relevant."""
    t0 = time.perf_counter()
    results = model(str(image_path), conf=conf_threshold, verbose=False)
    elapsed_ms = (time.perf_counter() - t0) * 1000

    kept: list[Detection] = []
    dropped_low_conf = 0
    dropped_non_pantry = 0

    for result in results:
        names = result.names  # {0: 'person', 1: 'bicycle', ...}
        for box in result.boxes:
            cls_id = int(box.cls[0])
            name = names[cls_id]
            conf = float(box.conf[0])
            if conf < conf_threshold:
                dropped_low_conf += 1
                continue
            if name not in PANTRY_RELEVANT:
                dropped_non_pantry += 1
                continue
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            kept.append(Detection(
                cls=name,
                confidence=conf,
                bbox=(int(x1), int(y1), int(x2), int(y2)),
            ))

    return ImageResult(
        image=str(image_path),
        elapsed_ms=elapsed_ms,
        kept=kept,
        dropped_low_conf=dropped_low_conf,
        dropped_non_pantry=dropped_non_pantry,
    )


def annotate_image(
    image_path: Path,
    result: ImageResult,
    output_dir: Path,
) -> Path:
    """Draw kept detections onto the image and save an annotated JPG."""
    from PIL import Image, ImageDraw, ImageFont

    image = Image.open(image_path).convert("RGB")
    draw = ImageDraw.Draw(image)

    # PIL's default bitmap font is tiny on phone photos; try a TTF fallback.
    try:
        font = ImageFont.truetype("arial.ttf", size=max(16, image.width // 60))
    except OSError:
        font = ImageFont.load_default()

    for det in result.kept:
        x1, y1, x2, y2 = det.bbox
        draw.rectangle((x1, y1, x2, y2), outline="lime", width=4)
        label = f"{det.cls} {det.confidence:.2f}"
        # Label background for legibility on busy shelves.
        text_bbox = draw.textbbox((x1, y1), label, font=font)
        pad = 2
        draw.rectangle(
            (text_bbox[0] - pad, text_bbox[1] - pad,
             text_bbox[2] + pad, text_bbox[3] + pad),
            fill="lime",
        )
        draw.text((x1, y1), label, fill="black", font=font)

    out_path = output_dir / f"{image_path.stem}_annotated.jpg"
    image.save(out_path, "JPEG", quality=85)
    return out_path


def print_summary(results: list[ImageResult], conf: float) -> None:
    print("\n" + "=" * 72)
    print(f"YOLOv8n PANTRY DETECTION — conf >= {conf:.2f}")
    print("=" * 72)

    class_totals: dict[str, int] = {}
    total_kept = 0
    total_low_conf = 0
    total_non_pantry = 0

    for r in results:
        stem = Path(r.image).name
        print(f"\n  {stem} — {r.elapsed_ms:.0f}ms")
        if not r.kept:
            print("    (nothing pantry-relevant above threshold)")
        for det in sorted(r.kept, key=lambda d: -d.confidence):
            print(f"    + {det.cls:12s} conf={det.confidence:.2f}")
            class_totals[det.cls] = class_totals.get(det.cls, 0) + 1
        print(
            f"    dropped: {r.dropped_low_conf} low-confidence,"
            f" {r.dropped_non_pantry} non-pantry classes"
        )
        total_kept += len(r.kept)
        total_low_conf += r.dropped_low_conf
        total_non_pantry += r.dropped_non_pantry

    print("\n" + "-" * 72)
    print("AGGREGATE")
    print("-" * 72)
    print(f"  images:          {len(results)}")
    print(f"  kept detections: {total_kept}")
    print(f"  dropped low-conf:  {total_low_conf}")
    print(f"  dropped non-pantry:{total_non_pantry}")
    if class_totals:
        print("\n  class counts (kept):")
        for cls, count in sorted(class_totals.items(), key=lambda kv: -kv[1]):
            print(f"    {cls:12s} {count}")
    else:
        print("\n  no pantry-relevant classes detected above threshold")
    print("=" * 72)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Evaluate YOLOv3 on pantry photos (COCO vocabulary).",
    )
    parser.add_argument(
        "--images",
        type=Path,
        default=DEFAULT_IMAGE_DIR,
        help=f"Directory of pantry photos (default: {DEFAULT_IMAGE_DIR})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--conf",
        type=float,
        default=0.5,
        help="Confidence threshold [0-1]; non-detection preferred (default: 0.5)",
    )
    args = parser.parse_args()

    _check_deps()

    if not args.images.exists():
        print(f"Image directory not found: {args.images}", file=sys.stderr)
        sys.exit(1)

    images = find_images(args.images)
    if not images:
        print(f"No images found in {args.images}", file=sys.stderr)
        print(f"Supported formats: {', '.join(sorted(IMAGE_EXTENSIONS))}")
        sys.exit(1)

    args.output.mkdir(parents=True, exist_ok=True)

    print(f"Images:    {len(images)} in {args.images}")
    print(f"Output:    {args.output}")
    print(f"Threshold: conf >= {args.conf:.2f}")
    print(f"Whitelist: {sorted(PANTRY_RELEVANT)}")

    model = load_model(args.conf)

    results: list[ImageResult] = []
    for image_path in images:
        print(f"\n--- {image_path.name} ---")
        result = analyze_image(model, image_path, args.conf)
        results.append(result)
        out_path = annotate_image(image_path, result, args.output)
        print(f"  kept={len(result.kept)}  -> {out_path.name}")

    report = {
        "threshold": args.conf,
        "whitelist": sorted(PANTRY_RELEVANT),
        "images": [r.to_json() for r in results],
    }
    json_path = args.output / "report.json"
    with open(json_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nJSON report: {json_path}")

    print_summary(results, args.conf)


if __name__ == "__main__":
    main()
