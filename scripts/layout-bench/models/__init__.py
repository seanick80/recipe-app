from __future__ import annotations

from .base import LayoutModel, Region, RegionLabel

# Model names registered here; actual classes imported lazily on first use
# so that `evaluate.py --help` works without heavyweight dependencies.
MODELS: dict[str, str] = {
    "heuristic": "models.heuristic:HeuristicModel",
    "dit": "models.dit_layout:DiTLayoutModel",
    "ocr-classify": "models.ocr_classify:OCRClassifyModel",
}


def get_model(name: str) -> LayoutModel:
    """Instantiate a model by name (lazy import)."""
    if name not in MODELS:
        available = ", ".join(sorted(MODELS))
        raise ValueError(f"Unknown model {name!r}. Available: {available}")

    module_path, class_name = MODELS[name].rsplit(":", 1)
    import importlib

    mod = importlib.import_module(f".{module_path.split('.')[-1]}", package=__package__)
    cls = getattr(mod, class_name)
    return cls()
