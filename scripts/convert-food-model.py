#!/usr/bin/env python3
"""Download nateraw/food (ViT Food-101) from HuggingFace and convert to CoreML.

Produces:
  FoodClassifier.mlpackage — image → food label + confidence (101 classes)

Source model: nateraw/food (ViT-base-patch16-224, fine-tuned on Food-101)
  - 1.9M+ downloads, Apache-2.0 license
  - 85.8M parameters, 224×224 input
  - https://huggingface.co/nateraw/food

Requires: coremltools, torch, transformers, Pillow, numpy
Runs on macOS only (coremltools constraint).
"""
from __future__ import annotations

import argparse
import os

import numpy as np
import torch

MODELS_DIR = os.path.join(
    os.path.dirname(__file__), "..", "RecipeApp", "RecipeApp", "MLModels"
)

HF_MODEL_ID = "nateraw/food"


def build_food_classifier(dest: str) -> None:
    """Download the HF model, trace to TorchScript, convert to CoreML."""
    import coremltools as ct
    from transformers import AutoImageProcessor, AutoModelForImageClassification

    print(f"Downloading {HF_MODEL_ID} from HuggingFace...")
    model = AutoModelForImageClassification.from_pretrained(HF_MODEL_ID)
    processor = AutoImageProcessor.from_pretrained(HF_MODEL_ID)
    model.eval()

    # Get class labels from the model config (id2label mapping).
    id2label = model.config.id2label
    class_labels = [
        id2label[i].replace("_", " ").title()
        for i in range(len(id2label))
    ]
    print(f"  {len(class_labels)} classes: {class_labels[:5]} ...")

    # Determine input size from the processor config.
    h = w = 224
    if hasattr(processor, "size"):
        size = processor.size
        if isinstance(size, dict):
            h = size.get("height", size.get("shortest_edge", 224))
            w = size.get("width", size.get("shortest_edge", 224))
        elif isinstance(size, int):
            h = w = size
    print(f"  Input size: {h}×{w}")

    # Wrap the model so it returns a plain logits tensor instead of a
    # dict-like ImageClassifierOutput (torch.jit.trace cannot handle dicts).
    class LogitsWrapper(torch.nn.Module):
        def __init__(self, hf_model: torch.nn.Module) -> None:
            super().__init__()
            self.hf_model = hf_model

        def forward(self, pixel_values: torch.Tensor) -> torch.Tensor:
            return self.hf_model(pixel_values).logits

    wrapper = LogitsWrapper(model)
    wrapper.eval()

    dummy_input = torch.randn(1, 3, h, w)
    traced_model = torch.jit.trace(wrapper, dummy_input)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.ImageType(
                name="image",
                shape=(1, 3, h, w),
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        classifier_config=ct.ClassifierConfig(class_labels),
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "nateraw (converted for RecipeApp)"
    mlmodel.short_description = (
        f"Food image classifier ({len(class_labels)} categories, "
        "ViT-base-patch16-224)"
    )
    mlmodel.license = "Apache-2.0"

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    mlmodel.save(dest)
    # .mlpackage is a directory; sum all file sizes inside it.
    total = 0
    for dirpath, _, filenames in os.walk(dest):
        for f in filenames:
            total += os.path.getsize(os.path.join(dirpath, f))
    size_mb = total / 1_000_000
    print(f"Saved FoodClassifier to {dest} ({size_mb:.1f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convert food classification model to CoreML"
    )
    parser.add_argument(
        "--skip-if-exists",
        action="store_true",
        help="Skip conversion if .mlpackage already exists",
    )
    args = parser.parse_args()

    food_dest = os.path.join(MODELS_DIR, "FoodClassifier.mlpackage")

    if args.skip_if_exists and os.path.exists(food_dest):
        print("FoodClassifier.mlpackage already exists, skipping (--skip-if-exists).")
        return

    build_food_classifier(food_dest)
    print("ML model conversion complete.")


if __name__ == "__main__":
    main()
