"""OCR + content-based classification model.

Two-stage approach:
  1. EasyOCR detects text lines → column detection → merge into spatial blocks
  2. Classify each block by its TEXT CONTENT, not document structure

Improvements over v1:
  - Column detection: clusters lines by x-position before merging, so two-column
    cookbook spreads produce separate blocks instead of one merged mess.
  - Handwriting detection: low-confidence OCR lines near page edges or with
    inconsistent sizing are flagged as handwritten margin notes.
  - Quality gate: reports overall image quality so the iOS pipeline can prompt
    a retake instead of ingesting garbage from rotated/blurry photos.

Requires: easyocr, numpy, Pillow
"""
from __future__ import annotations

import math
import re
import statistics

import easyocr
import numpy as np
from PIL import Image

from .base import LayoutModel, QualityAssessment, Region, RegionLabel

# ---------------------------------------------------------------------------
# Content classification patterns
# ---------------------------------------------------------------------------

# Ingredient signals: quantities, units, bullet lists of food items
_INGREDIENT_SIGNALS = [
    re.compile(
        r"\b\d+\s*(?:cup|tbsp|tsp|oz|ounce|lb|pound|g|gram|kg|ml|liter|litre"
        r"|bunch|clove|pinch|dash|can|pkg|package|stick|slice|piece|head"
        r"|tablespoon|teaspoon|quart|gallon|pint)s?\b",
        re.IGNORECASE,
    ),
    # Fraction patterns: 1/2, 3/4, ½, ¼
    re.compile(r"\b\d+\s*/\s*\d+\b|[½¼¾⅓⅔⅛]"),
    # Bullet/dash list items (short lines)
    re.compile(r"^\s*[-•*]\s+\w", re.MULTILINE),
    # Common ingredient words
    re.compile(
        r"\b(?:salt|pepper|sugar|flour|butter|oil|garlic|onion|egg|cream"
        r"|cheese|milk|chicken|beef|pork|fish|rice|pasta|vinegar|sauce"
        r"|lemon|lime|herb|spice|cumin|paprika|cinnamon|vanilla|honey"
        r"|olive|sesame|ginger|cilantro|parsley|basil|thyme|oregano"
        r"|tomato|potato|carrot|celery|mushroom|broccoli|spinach"
        r"|yogurt|sour cream|mayo|mustard|ketchup)s?\b",
        re.IGNORECASE,
    ),
]

# Instruction signals: cooking verbs, numbered steps, imperative sentences
_INSTRUCTION_SIGNALS = [
    re.compile(
        r"\b(?:preheat|stir|mix|bake|cook|simmer|sauté|saute|chop|dice"
        r"|slice|fold|whisk|drain|combine|add|pour|heat|remove|serve"
        r"|let stand|set aside|bring to|reduce|cover|uncover|roast"
        r"|grill|fry|sear|marinate|toss|season|drizzle|spread|layer"
        r"|arrange|transfer|cool|chill|refrigerate|freeze|thaw"
        r"|knead|roll|shape|form|stuff|wrap|assemble|garnish|plate"
        r"|broil|steam|blanch|deglaze|braise|poach|whip|beat|cream"
        r"|scrape|melt|dissolve|sprinkle|brush|coat|dip)\b",
        re.IGNORECASE,
    ),
    # Numbered steps: "1.", "2.", "Step 3"
    re.compile(r"^\s*(?:\d+[.)]\s|step\s+\d)", re.IGNORECASE | re.MULTILINE),
    # Temperature references
    re.compile(r"\b\d{3}\s*°?\s*[FCfc]\b|\boven\b", re.IGNORECASE),
    # Time references in cooking context
    re.compile(
        r"\b\d+\s*(?:min(?:ute)?|hour|hr)s?\b|\bovernight\b",
        re.IGNORECASE,
    ),
]

# Metadata signals: servings, times, yield
_METADATA_SIGNALS = [
    re.compile(
        r"\b(?:serves?|servings?|yield|makes?\s+\d|prep\s*time|cook\s*time"
        r"|total\s*time|calories|difficulty|active\s*time|rest\s*time"
        r"|ready\s+in|hands-on)\b",
        re.IGNORECASE,
    ),
]

# Junk signals: phone numbers, URLs, page numbers, copyright
_JUNK_SIGNALS = [
    re.compile(r"\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b"),  # phone
    re.compile(r"\b(?:www\.|http|\.com|\.org|\.net)\b", re.IGNORECASE),
    re.compile(r"^\s*(?:page\s+)?\d{1,3}\s*$", re.MULTILINE),  # page number
    re.compile(
        r"\b(?:copyright|©|all rights reserved|advertisement)\b",
        re.IGNORECASE,
    ),
]

# Handwriting indicators in text content (scaling notes, annotations)
_HANDWRITING_CONTENT = re.compile(
    r"[×xX]\s*\d+\.?\d*\b|"       # scaling: ×1.5, x2, X3
    r"\b\d+\.?\d*\s*[×xX]\b|"     # scaling: 1.5×, 2x
    r"^\s*[!?★☆✓✗→←↑↓]\s*|"       # annotation symbols
    r"\bdouble\b|\bhalf\b",        # scaling words
    re.IGNORECASE | re.MULTILINE,
)


# ---------------------------------------------------------------------------
# Content scoring
# ---------------------------------------------------------------------------

def _score_block(text: str) -> tuple[RegionLabel, float]:
    """Score a text block by content patterns. Returns best label + confidence.

    Unlike the heuristic model's per-line approach, this scores the ENTIRE
    block as a unit — a block with 8 ingredient-like lines and 1 instruction
    verb is ingredients, not a mix.
    """
    if not text.strip():
        return RegionLabel.OTHER, 0.1

    scores: dict[RegionLabel, float] = {
        RegionLabel.TITLE: 0.0,
        RegionLabel.INGREDIENTS: 0.0,
        RegionLabel.INSTRUCTIONS: 0.0,
        RegionLabel.METADATA: 0.0,
        RegionLabel.HANDWRITTEN: 0.0,
        RegionLabel.OTHER: 0.1,  # slight default toward other
    }

    lines = text.strip().split("\n")
    n_lines = len(lines)

    # --- Ingredient scoring ---
    ingredient_hits = 0
    for pattern in _INGREDIENT_SIGNALS:
        ingredient_hits += len(pattern.findall(text))
    if ingredient_hits > 0:
        density = ingredient_hits / max(n_lines, 1)
        scores[RegionLabel.INGREDIENTS] = min(0.3 + density * 0.25, 0.95)

    # --- Instruction scoring ---
    instruction_hits = 0
    for pattern in _INSTRUCTION_SIGNALS:
        instruction_hits += len(pattern.findall(text))
    if instruction_hits > 0:
        density = instruction_hits / max(n_lines, 1)
        scores[RegionLabel.INSTRUCTIONS] = min(0.3 + density * 0.2, 0.95)

    # --- Metadata scoring ---
    for pattern in _METADATA_SIGNALS:
        if pattern.search(text):
            scores[RegionLabel.METADATA] += 0.7

    # --- Junk scoring ---
    for pattern in _JUNK_SIGNALS:
        if pattern.search(text):
            scores[RegionLabel.OTHER] += 0.6

    # --- Handwriting content scoring ---
    if _HANDWRITING_CONTENT.search(text):
        scores[RegionLabel.HANDWRITTEN] += 0.4

    # --- Title heuristic ---
    # Only assign title to very short text (1-2 lines, <60 chars) that
    # looks like a heading: starts with a capital letter and has no
    # strong content signals. Longer unclassified text stays as OTHER.
    total_len = len(text.strip())
    if n_lines <= 2 and total_len < 60:
        max_other = max(
            scores[RegionLabel.INGREDIENTS],
            scores[RegionLabel.INSTRUCTIONS],
            scores[RegionLabel.METADATA],
        )
        first_char = text.strip()[0] if text.strip() else ""
        if max_other < 0.3 and first_char.isupper():
            scores[RegionLabel.TITLE] = 0.5

    # --- Sub-heading detection ---
    stripped = text.strip().rstrip(":")
    if n_lines == 1 and len(stripped.split()) <= 4:
        lower = stripped.lower()
        if any(
            kw in lower
            for kw in [
                "ingredient", "direction", "instruction", "method",
                "step", "preparation", "procedure", "assembly",
                "for the", "garnish", "topping", "filling",
                "frosting", "glaze", "sauce", "dressing", "note",
            ]
        ):
            scores[RegionLabel.TITLE] = 0.8

    best_label = max(scores, key=lambda k: scores[k])
    return best_label, scores[best_label]


# ---------------------------------------------------------------------------
# Column detection
# ---------------------------------------------------------------------------

def _detect_columns(
    items: list[tuple[int, int, int, int, str, float, int]],
    image_width: int,
) -> list[list[tuple[int, int, int, int, str, float, int]]]:
    """Cluster OCR lines into columns by x-position.

    Uses a simple gap-based approach: sort lines by left edge, find large
    horizontal gaps that suggest a column boundary.

    Args:
        items: (left, top, right, bottom, text, confidence, line_height)
        image_width: width of the source image in pixels

    Returns:
        List of column groups, each containing its lines.
    """
    if len(items) <= 1:
        return [items]

    # Find the horizontal center of each line.
    centers = [(it[0] + it[2]) / 2 for it in items]

    # Sort by center x.
    indexed = sorted(enumerate(centers), key=lambda ic: ic[1])

    # Look for a gap in center positions that's > 25% of image width.
    # Must be wide enough to distinguish real columns from normal word spacing.
    gap_threshold = image_width * 0.25
    split_points: list[int] = []
    for i in range(1, len(indexed)):
        gap = indexed[i][1] - indexed[i - 1][1]
        if gap > gap_threshold:
            split_points.append(i)

    if not split_points:
        return [items]

    # Build column groups.
    columns: list[list[tuple[int, int, int, int, str, float, int]]] = []
    prev = 0
    for sp in split_points:
        col_indices = {indexed[j][0] for j in range(prev, sp)}
        columns.append([items[i] for i in sorted(col_indices)])
        prev = sp
    # Last column.
    col_indices = {indexed[j][0] for j in range(prev, len(indexed))}
    columns.append([items[i] for i in sorted(col_indices)])

    return columns


# ---------------------------------------------------------------------------
# Handwriting detection
# ---------------------------------------------------------------------------

_HANDWRITING_CONFIDENCE_THRESHOLD = 0.35
_EDGE_MARGIN_RATIO = 0.05  # 5% from page edges


def _is_likely_handwritten(
    left: int,
    top: int,
    right: int,
    bottom: int,
    confidence: float,
    line_height: int,
    image_width: int,
    image_height: int,
    median_confidence: float,
    median_line_height: int,
) -> bool:
    """Detect likely handwritten text based on multiple signals.

    Requires BOTH low confidence AND a spatial/size anomaly. Low confidence
    alone is not enough — printed text on low-quality photos can also have
    low confidence. The combination of low confidence + margin position or
    unusual sizing is what distinguishes handwriting.

    Signals (each worth 1 point):
      - Very low absolute confidence (< 0.35)
      - Confidence well below page median (< 60% of median)
      - Position in page margins (outer 5%)
      - Line height very different from median (>80% bigger or <50% smaller)
      - Text contains handwriting-specific content (scaling marks, etc.)

    Needs 3+ signals to flag, ensuring we don't catch normal printed text.
    """
    signals = 0

    # Very low absolute confidence.
    if confidence < _HANDWRITING_CONFIDENCE_THRESHOLD:
        signals += 1

    # Confidence well below page median.
    if median_confidence > 0 and confidence < median_confidence * 0.6:
        signals += 1

    # In page margins.
    edge_x = image_width * _EDGE_MARGIN_RATIO
    edge_y = image_height * _EDGE_MARGIN_RATIO
    in_margin = (
        left < edge_x
        or right > image_width - edge_x
    )
    if in_margin:
        signals += 1

    # Line height very different from median.
    if median_line_height > 0:
        ratio = line_height / median_line_height
        if ratio > 1.8 or ratio < 0.5:
            signals += 1

    # Need at least 3 signals — this prevents false positives on
    # normal printed text that just happens to have low OCR confidence.
    return signals >= 3


# ---------------------------------------------------------------------------
# Quality gate
# ---------------------------------------------------------------------------

def assess_quality(
    detections: list[tuple[list[list[int]], str, float]],
    image_width: int,
    image_height: int,
) -> QualityAssessment:
    """Assess image quality from OCR detections.

    Checks:
      - Median OCR confidence (below 0.4 = probably blurry/bad lighting)
      - Ratio of low-confidence lines (>50% = widespread problems)
      - Estimated rotation from text line angles

    Returns a QualityAssessment with is_acceptable=False if a retake is needed.
    """
    if not detections:
        return QualityAssessment(
            median_confidence=0.0,
            low_confidence_ratio=1.0,
            estimated_rotation=0.0,
            is_acceptable=False,
            reason="No text detected — page may be blank or image too dark",
        )

    confidences = [conf for _, _, conf in detections]
    median_conf = statistics.median(confidences)
    low_count = sum(1 for c in confidences if c < 0.5)
    low_ratio = low_count / len(confidences)

    # Estimate rotation from text line angles.
    angles: list[float] = []
    for bbox_pts, _, _ in detections:
        # Top-left to top-right vector.
        dx = bbox_pts[1][0] - bbox_pts[0][0]
        dy = bbox_pts[1][1] - bbox_pts[0][1]
        if abs(dx) > 5:  # skip tiny detections
            angle = math.degrees(math.atan2(dy, dx))
            angles.append(angle)

    estimated_rotation = statistics.median(angles) if angles else 0.0

    # Decision logic.
    reasons: list[str] = []

    if median_conf < 0.35:
        reasons.append(
            f"Very low OCR confidence ({median_conf:.0%}) — "
            f"image may be blurry or poorly lit"
        )

    if low_ratio > 0.6:
        reasons.append(
            f"{low_ratio:.0%} of text lines have low confidence — "
            f"widespread readability issues"
        )

    if abs(estimated_rotation) > 8:
        reasons.append(
            f"Text is rotated ~{estimated_rotation:.1f}° — "
            f"straighten the page or retake"
        )

    is_acceptable = len(reasons) == 0
    reason = "; ".join(reasons) if reasons else ""

    return QualityAssessment(
        median_confidence=median_conf,
        low_confidence_ratio=low_ratio,
        estimated_rotation=estimated_rotation,
        is_acceptable=is_acceptable,
        reason=reason,
    )


# ---------------------------------------------------------------------------
# Block merging (column-aware)
# ---------------------------------------------------------------------------

def _merge_ocr_lines(
    detections: list[tuple[list[list[int]], str, float]],
    image_width: int,
    y_gap_factor: float = 2.0,
) -> list[tuple[tuple[int, int, int, int], str, float]]:
    """Merge OCR text lines into spatial blocks with column awareness.

    1. Convert detections to structured items with confidence + line height
    2. Detect columns by x-position clustering
    3. Within each column, merge vertically adjacent lines
    4. Return blocks with average confidence for handwriting detection

    Returns:
        List of (bbox, text, avg_confidence) tuples.
    """
    if not detections:
        return []

    items: list[tuple[int, int, int, int, str, float, int]] = []
    for bbox_pts, text, conf in detections:
        xs = [int(p[0]) for p in bbox_pts]
        ys = [int(p[1]) for p in bbox_pts]
        h = max(ys) - min(ys)
        items.append(
            (min(xs), min(ys), max(xs), max(ys), text, conf, max(h, 1))
        )

    # Detect columns.
    columns = _detect_columns(items, image_width)

    merged: list[tuple[tuple[int, int, int, int], str, float]] = []

    for column in columns:
        # Sort by vertical position within column.
        column.sort(key=lambda it: it[1])

        groups: list[list[tuple[int, int, int, int, str, float, int]]] = []
        current: list[tuple[int, int, int, int, str, float, int]] = [
            column[0]
        ]

        for item in column[1:]:
            prev = current[-1]
            avg_height = (prev[6] + item[6]) / 2
            vert_gap = item[1] - prev[3]
            horiz_overlap = min(item[2], prev[2]) - max(item[0], prev[0])

            if (
                vert_gap <= avg_height * y_gap_factor
                and horiz_overlap > -50
            ):
                current.append(item)
            else:
                groups.append(current)
                current = [item]
        groups.append(current)

        for group in groups:
            left = min(it[0] for it in group)
            top = min(it[1] for it in group)
            right = max(it[2] for it in group)
            bottom = max(it[3] for it in group)
            text = "\n".join(it[4] for it in group)
            avg_conf = sum(it[5] for it in group) / len(group)
            merged.append(((left, top, right, bottom), text, avg_conf))

    return merged


# ---------------------------------------------------------------------------
# Post-classification consolidation
# ---------------------------------------------------------------------------

def _consolidate_regions(
    regions: list[Region],
    max_regions: int = 10,
    max_passes: int = 5,
) -> list[Region]:
    """Iteratively merge adjacent same-label regions until count is low.

    After initial classification, the page may have 50+ small regions.
    This pass merges neighboring blocks that share a label, growing the
    merge distance each iteration until we're under max_regions or
    we've exhausted passes.

    Also merges OTHER into its nearest neighbor when consolidating,
    since isolated "other" fragments between two ingredient blocks
    are usually just OCR noise.
    """
    if len(regions) <= max_regions:
        return regions

    working = list(regions)

    for pass_num in range(max_passes):
        if len(working) <= max_regions:
            break

        merged: list[Region] = []
        i = 0
        while i < len(working):
            current = working[i]
            # Look ahead for same-label or absorbable neighbors.
            j = i + 1
            while j < len(working):
                candidate = working[j]
                # Merge if same label, or if one is OTHER (absorb noise).
                same_label = current.label == candidate.label
                one_is_other = (
                    current.label == RegionLabel.OTHER
                    or candidate.label == RegionLabel.OTHER
                )
                # Only absorb OTHER after first pass (give it a chance
                # to stand alone if it's genuinely junk).
                can_absorb = same_label or (one_is_other and pass_num > 0)

                if not can_absorb:
                    break

                # Check spatial proximity — merge if vertically close.
                gap = candidate.bbox[1] - current.bbox[3]
                # Grow tolerance each pass: 50px, 100px, 150px...
                tolerance = 50 * (pass_num + 1)
                if gap > tolerance:
                    break

                # Merge the two regions.
                new_bbox = (
                    min(current.bbox[0], candidate.bbox[0]),
                    min(current.bbox[1], candidate.bbox[1]),
                    max(current.bbox[2], candidate.bbox[2]),
                    max(current.bbox[3], candidate.bbox[3]),
                )
                # Keep the non-OTHER label when absorbing.
                keep_label = current.label
                if keep_label == RegionLabel.OTHER:
                    keep_label = candidate.label
                new_conf = max(current.confidence, candidate.confidence)
                new_text = current.text + "\n" + candidate.text

                current = Region(
                    bbox=new_bbox,
                    label=keep_label,
                    confidence=new_conf,
                    text=new_text,
                    source_model=current.source_model,
                )
                j += 1

            merged.append(current)
            i = j

        working = merged

    return working


# ---------------------------------------------------------------------------
# Model class
# ---------------------------------------------------------------------------

class OCRClassifyModel:
    """Two-stage: OCR text detection → content-based block classification.

    Enhancements over v1:
      - Column-aware block merging for two-column layouts
      - Handwriting/margin note detection
      - Image quality gate (accessible via quality_assessment after analyze)
    """

    name: str = "ocr-classify"

    def __init__(self) -> None:
        self._reader: easyocr.Reader | None = None
        self.quality_assessment: QualityAssessment | None = None
        self.max_regions: int = 10

    def _get_reader(self) -> easyocr.Reader:
        if self._reader is None:
            self._reader = easyocr.Reader(["en"], gpu=False, verbose=False)
        return self._reader

    def analyze(self, image: Image.Image) -> list[Region]:
        reader = self._get_reader()
        img_array = np.array(image)
        detections = reader.readtext(img_array)

        # Quality gate.
        self.quality_assessment = assess_quality(
            detections, image.width, image.height,
        )

        # Column-aware block merging.
        blocks = _merge_ocr_lines(detections, image.width)

        # Compute page-level stats for handwriting detection.
        all_confidences = [conf for _, _, conf in detections]
        median_conf = (
            statistics.median(all_confidences) if all_confidences else 0.0
        )
        all_heights = [
            max(int(p[1]) for p in bbox) - min(int(p[1]) for p in bbox)
            for bbox, _, _ in detections
        ]
        median_height = (
            statistics.median(all_heights) if all_heights else 0
        )

        regions: list[Region] = []
        for bbox, text, avg_conf in blocks:
            # Check for handwriting first.
            left, top, right, bottom = bbox
            line_height = bottom - top

            if _is_likely_handwritten(
                left, top, right, bottom,
                avg_conf, line_height,
                image.width, image.height,
                median_conf, int(median_height),
            ):
                regions.append(
                    Region(
                        bbox=bbox,
                        label=RegionLabel.HANDWRITTEN,
                        confidence=avg_conf,
                        text=text,
                        source_model=self.name,
                    )
                )
                continue

            # Content-based classification.
            label, confidence = _score_block(text)
            regions.append(
                Region(
                    bbox=bbox,
                    label=label,
                    confidence=confidence,
                    text=text,
                    source_model=self.name,
                )
            )

        # Sort by vertical position for consolidation.
        regions.sort(key=lambda r: r.bbox[1])

        # Consolidate into fewer, larger zones.
        regions = _consolidate_regions(regions, max_regions=self.max_regions)

        return regions
