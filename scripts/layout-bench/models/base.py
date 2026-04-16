"""Base classes for layout analysis models."""
from __future__ import annotations

import enum
from dataclasses import dataclass, field
from typing import Protocol

from PIL import Image


class RegionLabel(enum.Enum):
    """Semantic zone labels for recipe page regions."""

    TITLE = "title"
    INGREDIENTS = "ingredients"
    INSTRUCTIONS = "instructions"
    METADATA = "metadata"  # servings, prep time, cook time, etc.
    HANDWRITTEN = "handwritten"  # margin notes, annotations, scaling marks
    OTHER = "other"  # phone numbers, ads, page numbers, stray notes


@dataclass
class Region:
    """A detected region on the page."""

    # Bounding box in pixels: (left, top, right, bottom)
    bbox: tuple[int, int, int, int]
    label: RegionLabel
    confidence: float
    text: str = ""
    # Model that produced this region (for A/B comparison)
    source_model: str = ""


@dataclass
class LayoutResult:
    """Full result from analyzing one image."""

    image_path: str
    regions: list[Region] = field(default_factory=list)
    elapsed_ms: float = 0.0
    model_name: str = ""

    @property
    def ingredients(self) -> list[Region]:
        return [r for r in self.regions if r.label == RegionLabel.INGREDIENTS]

    @property
    def instructions(self) -> list[Region]:
        return [r for r in self.regions if r.label == RegionLabel.INSTRUCTIONS]

    @property
    def title(self) -> list[Region]:
        return [r for r in self.regions if r.label == RegionLabel.TITLE]

    @property
    def handwritten(self) -> list[Region]:
        return [r for r in self.regions if r.label == RegionLabel.HANDWRITTEN]

    @property
    def junk(self) -> list[Region]:
        return [r for r in self.regions if r.label == RegionLabel.OTHER]


@dataclass
class QualityAssessment:
    """Image quality assessment for the quality gate."""

    median_confidence: float  # median OCR confidence across all detections
    low_confidence_ratio: float  # fraction of lines below 0.5 confidence
    estimated_rotation: float  # degrees, 0 = upright
    is_acceptable: bool  # True if image is good enough to parse
    reason: str = ""  # why it was rejected (empty if acceptable)

    @property
    def should_retake(self) -> bool:
        return not self.is_acceptable


class LayoutModel(Protocol):
    """Interface that all layout analysis models must implement."""

    name: str

    def analyze(self, image: Image.Image) -> list[Region]:
        """Detect and classify regions on a page image.

        Args:
            image: PIL Image of the recipe page.

        Returns:
            List of detected regions with labels and bounding boxes.
        """
        ...
