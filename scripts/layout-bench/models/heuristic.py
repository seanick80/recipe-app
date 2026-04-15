"""Heuristic baseline: OCR text detection + spatial clustering + pattern matching.

No ML model required — uses EasyOCR for text detection, then classifies
regions by text patterns and spatial position on the page.
"""
from __future__ import annotations

import re

import easyocr
import numpy as np
from PIL import Image

from .base import LayoutModel, Region, RegionLabel

# Patterns that strongly suggest a region's role.
_TITLE_PATTERNS = re.compile(
    r"^(recipe|dish|meal)\b|"
    r"^[A-Z][a-z]+(?: [A-Z][a-z]+){1,5}$",  # Title Case phrase
    re.IGNORECASE,
)
_INGREDIENT_PATTERNS = re.compile(
    r"\b\d+\s*(?:cup|tbsp|tsp|oz|lb|g|kg|ml|liter|bunch|clove|pinch|dash|can|pkg)"
    r"s?\b|"
    r"^\s*[-•*]\s+\w|"  # bullet list
    r"\b(?:salt|pepper|sugar|flour|butter|oil|garlic|onion|egg)s?\b",
    re.IGNORECASE,
)
_INSTRUCTION_PATTERNS = re.compile(
    r"\b(?:preheat|stir|mix|bake|cook|simmer|sauté|chop|dice|slice|fold|"
    r"whisk|drain|combine|add|pour|heat|remove|serve|let stand|set aside|"
    r"bring to|reduce heat|cover|uncover)\b",
    re.IGNORECASE,
)
_METADATA_PATTERNS = re.compile(
    r"\b(?:serves?|servings?|prep\s*time|cook\s*time|total\s*time|yield|"
    r"makes?\s+\d|calories|difficulty)\b",
    re.IGNORECASE,
)
_JUNK_PATTERNS = re.compile(
    r"\b(?:\d{3}[-.\s]?\d{3}[-.\s]?\d{4})\b|"  # phone numbers
    r"\b(?:www\.|http|\.com|\.org)\b|"  # URLs
    r"^\s*(?:page\s+\d+|\d+\s*$)|"  # page numbers
    r"\b(?:advertisement|sponsored|copyright|©)\b",
    re.IGNORECASE,
)


def _classify_text(text: str) -> tuple[RegionLabel, float]:
    """Classify a text block by pattern matching. Returns label + confidence."""
    text_stripped = text.strip()
    if not text_stripped:
        return RegionLabel.OTHER, 0.1

    scores: dict[RegionLabel, float] = {
        RegionLabel.TITLE: 0.0,
        RegionLabel.INGREDIENTS: 0.0,
        RegionLabel.INSTRUCTIONS: 0.0,
        RegionLabel.METADATA: 0.0,
        RegionLabel.OTHER: 0.0,
    }

    if _JUNK_PATTERNS.search(text_stripped):
        scores[RegionLabel.OTHER] += 0.8

    if _METADATA_PATTERNS.search(text_stripped):
        scores[RegionLabel.METADATA] += 0.7

    ingredient_hits = len(_INGREDIENT_PATTERNS.findall(text_stripped))
    if ingredient_hits > 0:
        scores[RegionLabel.INGREDIENTS] += min(0.4 + ingredient_hits * 0.15, 0.9)

    instruction_hits = len(_INSTRUCTION_PATTERNS.findall(text_stripped))
    if instruction_hits > 0:
        scores[RegionLabel.INSTRUCTIONS] += min(0.4 + instruction_hits * 0.15, 0.9)

    # Short title-case lines near the top are likely titles.
    lines = text_stripped.split("\n")
    if len(lines) <= 2 and len(text_stripped) < 80:
        if _TITLE_PATTERNS.match(text_stripped):
            scores[RegionLabel.TITLE] += 0.6

    # If nothing matched strongly, lean toward OTHER.
    if max(scores.values()) < 0.3:
        scores[RegionLabel.OTHER] = 0.5

    best_label = max(scores, key=lambda k: scores[k])
    return best_label, scores[best_label]


def _merge_nearby_boxes(
    detections: list[tuple[list[list[int]], str, float]],
    y_threshold: int = 30,
) -> list[tuple[tuple[int, int, int, int], str]]:
    """Group OCR text boxes that are vertically close into blocks.

    EasyOCR returns one box per text line. We merge lines that are
    close vertically and overlapping horizontally into logical blocks.
    """
    if not detections:
        return []

    # Convert EasyOCR's polygon format to (left, top, right, bottom, text).
    items: list[tuple[int, int, int, int, str]] = []
    for bbox_pts, text, _conf in detections:
        xs = [int(p[0]) for p in bbox_pts]
        ys = [int(p[1]) for p in bbox_pts]
        items.append((min(xs), min(ys), max(xs), max(ys), text))

    # Sort by vertical position.
    items.sort(key=lambda it: it[1])

    groups: list[list[tuple[int, int, int, int, str]]] = []
    current_group: list[tuple[int, int, int, int, str]] = [items[0]]

    for item in items[1:]:
        prev = current_group[-1]
        # Merge if top of current is within y_threshold of bottom of previous
        # and horizontal overlap exists.
        horiz_overlap = min(item[2], prev[2]) - max(item[0], prev[0])
        vert_gap = item[1] - prev[3]
        if vert_gap <= y_threshold and horiz_overlap > 0:
            current_group.append(item)
        else:
            groups.append(current_group)
            current_group = [item]
    groups.append(current_group)

    # Collapse each group into one bounding box + concatenated text.
    merged: list[tuple[tuple[int, int, int, int], str]] = []
    for group in groups:
        left = min(it[0] for it in group)
        top = min(it[1] for it in group)
        right = max(it[2] for it in group)
        bottom = max(it[3] for it in group)
        text = "\n".join(it[4] for it in group)
        merged.append(((left, top, right, bottom), text))

    return merged


class HeuristicModel:
    """OCR + spatial clustering + pattern matching baseline."""

    name: str = "heuristic"

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

        merged = _merge_nearby_boxes(detections)
        img_height = image.height

        regions: list[Region] = []
        for bbox, text in merged:
            label, confidence = _classify_text(text)

            # Spatial boost: title-like text in the top 15% of the page.
            _, top, _, _ = bbox
            if top < img_height * 0.15 and label == RegionLabel.TITLE:
                confidence = min(confidence + 0.2, 1.0)

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
