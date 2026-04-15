"""DETR document layout detection model (fine-tuned on DocLayNet).

Uses cmarkea/detr-layout-detection — a DETR-ResNet-50 model fine-tuned on
the DocLayNet dataset (80k pages, 11 layout classes). Detects document
regions (text blocks, lists, titles, pictures, tables, etc.) and maps
them to recipe-specific labels.

Requires: torch, transformers, Pillow
"""
from __future__ import annotations

import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForObjectDetection

from .base import LayoutModel, Region, RegionLabel

# DocLayNet label → recipe region mapping.
# These models detect generic document elements; we remap to recipe zones.
_DOCLAYNET_LABEL_MAP: dict[str, RegionLabel] = {
    "Caption": RegionLabel.METADATA,
    "Footnote": RegionLabel.OTHER,
    "Formula": RegionLabel.OTHER,
    "List-item": RegionLabel.INGREDIENTS,  # lists are usually ingredients
    "Page-footer": RegionLabel.OTHER,
    "Page-header": RegionLabel.OTHER,
    "Picture": RegionLabel.OTHER,
    "Section-header": RegionLabel.TITLE,
    "Table": RegionLabel.METADATA,
    "Text": RegionLabel.INSTRUCTIONS,  # body text → usually instructions
    "Title": RegionLabel.TITLE,
}

# DETR fine-tuned on DocLayNet — 11 layout classes, works with
# AutoModelForObjectDetection out of the box.
_MODEL_ID = "cmarkea/detr-layout-detection"


class DiTLayoutModel:
    """Document layout detection using DETR fine-tuned on DocLayNet."""

    name: str = "dit"

    def __init__(self) -> None:
        self._processor: AutoImageProcessor | None = None
        self._model: AutoModelForObjectDetection | None = None

    def _load(self) -> None:
        if self._model is not None:
            return
        print(f"  Loading {_MODEL_ID} ...")
        self._processor = AutoImageProcessor.from_pretrained(_MODEL_ID)
        self._model = AutoModelForObjectDetection.from_pretrained(_MODEL_ID)
        self._model.eval()

    def analyze(self, image: Image.Image) -> list[Region]:
        self._load()
        assert self._processor is not None
        assert self._model is not None

        inputs = self._processor(images=image, return_tensors="pt")

        with torch.no_grad():
            outputs = self._model(**inputs)

        target_sizes = torch.tensor([image.size[::-1]])
        results = self._processor.post_process_object_detection(
            outputs, target_sizes=target_sizes, threshold=0.3
        )[0]

        id2label = self._model.config.id2label

        regions: list[Region] = []
        for score, label_id, box in zip(
            results["scores"], results["labels"], results["boxes"]
        ):
            raw_label = id2label[label_id.item()]
            recipe_label = _DOCLAYNET_LABEL_MAP.get(raw_label, RegionLabel.OTHER)

            left, top, right, bottom = box.int().tolist()
            regions.append(
                Region(
                    bbox=(left, top, right, bottom),
                    label=recipe_label,
                    confidence=score.item(),
                    text=f"[{raw_label}]",
                    source_model=self.name,
                )
            )

        return regions
