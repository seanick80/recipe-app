#!/usr/bin/env python3
"""Compare layout analysis extraction against golden recipe files.

Validates that the zone detection pipeline actually produces the correct
recipe content end-to-end. Runs the model, collects text from each label,
then fuzzy-matches against the golden expected output.

Usage:
    python golden_check.py                          # all models with golden files
    python golden_check.py --model ocr-classify     # single model
    python golden_check.py --verbose                # show per-ingredient matches
"""
from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

REPO_ROOT = SCRIPT_DIR.parent.parent
GOLDEN_DIR = REPO_ROOT / "data" / "layout-bench" / "golden"
IMAGE_DIR = REPO_ROOT / "data" / "layout-bench" / "images"
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".bmp", ".tiff", ".webp"}

FUZZY_THRESHOLD = 0.60  # minimum similarity ratio to count as a match


def _normalize(text: str) -> str:
    """Normalize text for fuzzy comparison."""
    import re

    text = text.lower().strip()
    # Collapse whitespace.
    text = re.sub(r"\s+", " ", text)
    # Remove common OCR artifacts.
    text = text.replace("|", " ").replace("_", " ")
    return text


def _fuzzy_match(needle: str, haystack: str) -> float:
    """Return similarity ratio between needle and best substring of haystack."""
    needle_n = _normalize(needle)
    haystack_n = _normalize(haystack)

    if not needle_n:
        return 1.0

    # Direct substring check first.
    if needle_n in haystack_n:
        return 1.0

    # Try each sentence/chunk of haystack.
    best = 0.0
    # Split haystack into overlapping windows roughly the size of needle.
    words_h = haystack_n.split()
    words_n = needle_n.split()
    window = max(len(words_n), 3)

    for i in range(max(1, len(words_h) - window + 1)):
        chunk = " ".join(words_h[i : i + window + 2])
        ratio = SequenceMatcher(None, needle_n, chunk).ratio()
        best = max(best, ratio)

    # Also try full-text ratio.
    full_ratio = SequenceMatcher(None, needle_n, haystack_n).ratio()
    best = max(best, full_ratio)

    return best


@dataclass
class MatchResult:
    """Result of matching one golden item against extracted text."""

    golden_text: str
    best_match_ratio: float
    matched: bool
    matched_in: str = ""  # which extracted region matched


@dataclass
class RecipeCheckResult:
    """Full check result for one image + model."""

    image_name: str
    model_name: str
    title_match: MatchResult | None = None
    ingredient_matches: list[MatchResult] = field(default_factory=list)
    instruction_matches: list[MatchResult] = field(default_factory=list)

    @property
    def ingredient_recall(self) -> float:
        if not self.ingredient_matches:
            return 0.0
        matched = sum(1 for m in self.ingredient_matches if m.matched)
        return matched / len(self.ingredient_matches)

    @property
    def instruction_recall(self) -> float:
        if not self.instruction_matches:
            return 0.0
        matched = sum(1 for m in self.instruction_matches if m.matched)
        return matched / len(self.instruction_matches)

    @property
    def overall_recall(self) -> float:
        all_matches = (
            self.ingredient_matches + self.instruction_matches
        )
        if self.title_match:
            all_matches = [self.title_match] + all_matches
        if not all_matches:
            return 0.0
        matched = sum(1 for m in all_matches if m.matched)
        return matched / len(all_matches)


def check_recipe(
    golden: dict,
    regions: list[dict],
    model_name: str,
    image_name: str,
) -> RecipeCheckResult:
    """Check extracted regions against a golden recipe."""
    result = RecipeCheckResult(
        image_name=image_name, model_name=model_name,
    )

    # Collect extracted text by label.
    extracted: dict[str, str] = {}
    for r in regions:
        label = r["label"]
        text = r.get("text", "")
        extracted.setdefault(label, "")
        extracted[label] += " " + text

    all_text = " ".join(extracted.values())

    # --- Title check ---
    golden_title = golden.get("title", "")
    if golden_title:
        # Check in title regions first, then all text.
        title_text = extracted.get("title", "")
        ratio = _fuzzy_match(golden_title, title_text)
        if ratio < FUZZY_THRESHOLD:
            # Fall back to checking all text.
            ratio_all = _fuzzy_match(golden_title, all_text)
            result.title_match = MatchResult(
                golden_text=golden_title,
                best_match_ratio=max(ratio, ratio_all),
                matched=max(ratio, ratio_all) >= FUZZY_THRESHOLD,
                matched_in="title" if ratio >= FUZZY_THRESHOLD else "all",
            )
        else:
            result.title_match = MatchResult(
                golden_text=golden_title,
                best_match_ratio=ratio,
                matched=True,
                matched_in="title",
            )

    # --- Ingredient check ---
    ingredient_text = extracted.get("ingredients", "")
    for ing in golden.get("ingredients", []):
        # Try ingredient regions first.
        ratio = _fuzzy_match(ing, ingredient_text)
        matched_in = "ingredients"
        if ratio < FUZZY_THRESHOLD:
            # Fall back to all text (ingredient might be in wrong zone).
            ratio_all = _fuzzy_match(ing, all_text)
            if ratio_all > ratio:
                ratio = ratio_all
                matched_in = "all"
        result.ingredient_matches.append(
            MatchResult(
                golden_text=ing,
                best_match_ratio=ratio,
                matched=ratio >= FUZZY_THRESHOLD,
                matched_in=matched_in,
            )
        )

    # --- Instruction check ---
    instruction_text = extracted.get("instructions", "")
    for step in golden.get("instructions", []):
        # Extract key phrases (first 8 words) for matching since
        # full instruction steps are long and OCR may split them.
        words = step.split()
        key_phrase = " ".join(words[:8]) if len(words) > 8 else step

        ratio = _fuzzy_match(key_phrase, instruction_text)
        matched_in = "instructions"
        if ratio < FUZZY_THRESHOLD:
            ratio_all = _fuzzy_match(key_phrase, all_text)
            if ratio_all > ratio:
                ratio = ratio_all
                matched_in = "all"
        result.instruction_matches.append(
            MatchResult(
                golden_text=step,
                best_match_ratio=ratio,
                matched=ratio >= FUZZY_THRESHOLD,
                matched_in=matched_in,
            )
        )

    return result


def print_result(
    result: RecipeCheckResult,
    verbose: bool = False,
) -> None:
    """Print a check result."""
    # Title.
    title_status = "---"
    if result.title_match:
        if result.title_match.matched:
            title_status = "PASS"
        else:
            title_status = (
                f"MISS ({result.title_match.best_match_ratio:.0%})"
            )

    # Counts.
    ing_ok = sum(1 for m in result.ingredient_matches if m.matched)
    ing_total = len(result.ingredient_matches)
    ins_ok = sum(1 for m in result.instruction_matches if m.matched)
    ins_total = len(result.instruction_matches)

    print(
        f"  {result.image_name} [{result.model_name}]"
        f"  title={title_status}"
        f"  ingredients={ing_ok}/{ing_total}"
        f" ({result.ingredient_recall:.0%})"
        f"  instructions={ins_ok}/{ins_total}"
        f" ({result.instruction_recall:.0%})"
        f"  overall={result.overall_recall:.0%}"
    )

    if verbose:
        if result.title_match and not result.title_match.matched:
            print(
                f"    MISS title: {result.title_match.golden_text!r}"
                f" (best={result.title_match.best_match_ratio:.0%})"
            )
        for m in result.ingredient_matches:
            status = "ok" if m.matched else "MISS"
            if not m.matched or m.matched_in != "ingredients":
                loc = f" [in {m.matched_in}]" if m.matched else ""
                print(
                    f"    {status} ingredient:"
                    f" {m.golden_text[:60]!r}"
                    f" ({m.best_match_ratio:.0%}){loc}"
                )
        for m in result.instruction_matches:
            if not m.matched:
                step_preview = m.golden_text[:60]
                print(
                    f"    MISS instruction:"
                    f" {step_preview!r}"
                    f" ({m.best_match_ratio:.0%})"
                )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check layout analysis against golden recipe files",
    )
    parser.add_argument(
        "--model",
        action="append",
        dest="models",
        help="Model(s) to check (default: ocr-classify)",
    )
    parser.add_argument(
        "--max-regions",
        type=int,
        default=10,
        help="Target max regions for consolidation",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show per-item match details",
    )
    args = parser.parse_args()

    model_names = args.models or ["ocr-classify"]

    # Find golden files.
    golden_files = sorted(GOLDEN_DIR.glob("*.json"))
    if not golden_files:
        print(f"No golden files found in {GOLDEN_DIR}")
        sys.exit(1)

    # Check deps.
    try:
        from PIL import Image
    except ImportError:
        print("Missing Pillow. pip install Pillow")
        sys.exit(1)

    from models import MODELS, get_model

    for name in model_names:
        if name not in MODELS:
            print(f"Unknown model: {name}")
            sys.exit(1)

    print(f"Golden files: {len(golden_files)}")
    print(f"Models: {', '.join(model_names)}")
    print("=" * 72)

    all_results: list[RecipeCheckResult] = []

    for golden_path in golden_files:
        stem = golden_path.stem
        golden = json.loads(golden_path.read_text())

        # Find matching image.
        image_path = None
        for ext in IMAGE_EXTENSIONS:
            candidate = IMAGE_DIR / f"{stem}{ext}"
            if candidate.exists():
                image_path = candidate
                break

        if image_path is None:
            print(f"  SKIP {stem} — no image found")
            continue

        for model_name in model_names:
            # Run the model.
            model = get_model(model_name)
            if hasattr(model, "max_regions"):
                model.max_regions = args.max_regions

            image = Image.open(image_path).convert("RGB")

            import time

            t0 = time.perf_counter()
            regions_raw = model.analyze(image)
            elapsed = (time.perf_counter() - t0) * 1000

            # Convert to dicts for the checker.
            regions = [
                {
                    "label": r.label.value,
                    "text": r.text,
                    "confidence": r.confidence,
                }
                for r in regions_raw
            ]

            result = check_recipe(golden, regions, model_name, stem)
            all_results.append(result)
            print_result(result, verbose=args.verbose)

    # Summary.
    print("\n" + "=" * 72)
    print("SUMMARY")
    print("=" * 72)

    for model_name in model_names:
        model_results = [r for r in all_results if r.model_name == model_name]
        if not model_results:
            continue

        avg_ing = sum(r.ingredient_recall for r in model_results) / len(
            model_results
        )
        avg_ins = sum(r.instruction_recall for r in model_results) / len(
            model_results
        )
        avg_all = sum(r.overall_recall for r in model_results) / len(
            model_results
        )

        print(
            f"  {model_name}:"
            f"  avg ingredient recall={avg_ing:.0%}"
            f"  avg instruction recall={avg_ins:.0%}"
            f"  avg overall={avg_all:.0%}"
        )

    print()


if __name__ == "__main__":
    main()
