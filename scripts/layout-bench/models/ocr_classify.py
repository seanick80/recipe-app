"""OCR + content-based classification model.

Two-stage approach:
  1. EasyOCR detects text lines → merge into spatial blocks
  2. Classify each block by its TEXT CONTENT, not document structure

This handles multi-component recipes (e.g. 5 sub-recipes each with
their own ingredients/instructions, plus an assembly block) because
classification is purely content-driven — a block of ingredient-like
lines is "ingredients" regardless of where it sits on the page.

Requires: easyocr, numpy, Pillow
"""
from __future__ import annotations

import re

import easyocr
import numpy as np
from PIL import Image

from .base import LayoutModel, Region, RegionLabel

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
    re.compile(r"\b(?:copyright|©|all rights reserved|advertisement)\b", re.IGNORECASE),
]


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
        RegionLabel.OTHER: 0.1,  # slight default toward other
    }

    lines = text.strip().split("\n")
    n_lines = len(lines)

    # --- Ingredient scoring ---
    ingredient_hits = 0
    for pattern in _INGREDIENT_SIGNALS:
        ingredient_hits += len(pattern.findall(text))
    if ingredient_hits > 0:
        # Scale by density: many hits in a block = strong signal
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

    # --- Title heuristic ---
    # Short text (1-3 lines, <100 chars total) that doesn't match other
    # categories strongly is likely a title or heading.
    total_len = len(text.strip())
    if n_lines <= 3 and total_len < 100:
        max_other = max(
            scores[RegionLabel.INGREDIENTS],
            scores[RegionLabel.INSTRUCTIONS],
            scores[RegionLabel.METADATA],
        )
        if max_other < 0.4:
            scores[RegionLabel.TITLE] = 0.5

    # --- Sub-heading detection ---
    # Single-word or short labels like "Ingredients", "Directions", "Method",
    # "For the filling:", "Assembly" — these are section headers.
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


def _merge_ocr_lines(
    detections: list[tuple[list[list[int]], str, float]],
    y_gap_factor: float = 1.5,
) -> list[tuple[tuple[int, int, int, int], str]]:
    """Merge OCR text lines into spatial blocks.

    Groups lines that are vertically close (gap < line_height * factor)
    and horizontally overlapping into coherent text blocks.
    """
    if not detections:
        return []

    items: list[tuple[int, int, int, int, str, int]] = []
    for bbox_pts, text, _conf in detections:
        xs = [int(p[0]) for p in bbox_pts]
        ys = [int(p[1]) for p in bbox_pts]
        h = max(ys) - min(ys)
        items.append((min(xs), min(ys), max(xs), max(ys), text, max(h, 1)))

    # Sort by vertical position.
    items.sort(key=lambda it: it[1])

    groups: list[list[tuple[int, int, int, int, str, int]]] = []
    current: list[tuple[int, int, int, int, str, int]] = [items[0]]

    for item in items[1:]:
        prev = current[-1]
        avg_height = (prev[5] + item[5]) / 2
        vert_gap = item[1] - prev[3]
        # Horizontal overlap check
        horiz_overlap = min(item[2], prev[2]) - max(item[0], prev[0])

        if vert_gap <= avg_height * y_gap_factor and horiz_overlap > -50:
            current.append(item)
        else:
            groups.append(current)
            current = [item]
    groups.append(current)

    merged: list[tuple[tuple[int, int, int, int], str]] = []
    for group in groups:
        left = min(it[0] for it in group)
        top = min(it[1] for it in group)
        right = max(it[2] for it in group)
        bottom = max(it[3] for it in group)
        text = "\n".join(it[4] for it in group)
        merged.append(((left, top, right, bottom), text))

    return merged


class OCRClassifyModel:
    """Two-stage: OCR text detection → content-based block classification."""

    name: str = "ocr-classify"

    def __init__(self) -> None:
        self._reader: easyocr.Reader | None = None

    def _get_reader(self) -> easyocr.Reader:
        if self._reader is None:
            self._reader = easyocr.Reader(["en"], gpu=False, verbose=False)
        return self._reader

    def analyze(self, image: Image.Image) -> list[Region]:
        reader = self._get_reader()
        img_array = np.array(image)
        detections = reader.readtext(img_array)

        blocks = _merge_ocr_lines(detections)

        regions: list[Region] = []
        for bbox, text in blocks:
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

        return regions
