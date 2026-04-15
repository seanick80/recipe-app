"""Visualization utilities for layout analysis results."""
from __future__ import annotations

from pathlib import Path

import matplotlib
import matplotlib.patches as mpatches
import matplotlib.pyplot as plt
from PIL import Image

from models.base import LayoutResult, Region, RegionLabel

# Deterministic colors per label — distinct enough to eyeball on any image.
LABEL_COLORS: dict[RegionLabel, str] = {
    RegionLabel.TITLE: "#2196F3",        # blue
    RegionLabel.INGREDIENTS: "#4CAF50",   # green
    RegionLabel.INSTRUCTIONS: "#FF9800",  # orange
    RegionLabel.METADATA: "#9C27B0",      # purple
    RegionLabel.OTHER: "#F44336",         # red
}


def draw_regions(
    image: Image.Image,
    regions: list[Region],
    title: str = "",
) -> matplotlib.figure.Figure:
    """Draw bounding boxes on an image, color-coded by region label."""
    fig, ax = plt.subplots(1, 1, figsize=(12, 16))
    ax.imshow(image)

    for region in regions:
        left, top, right, bottom = region.bbox
        color = LABEL_COLORS.get(region.label, "#999999")
        rect = mpatches.FancyBboxPatch(
            (left, top),
            right - left,
            bottom - top,
            linewidth=2,
            edgecolor=color,
            facecolor=color,
            alpha=0.15,
            boxstyle="round,pad=2",
        )
        ax.add_patch(rect)

        # Label + confidence badge.
        badge = f"{region.label.value} ({region.confidence:.0%})"
        ax.text(
            left,
            top - 4,
            badge,
            fontsize=8,
            color="white",
            bbox=dict(boxstyle="round,pad=0.3", facecolor=color, alpha=0.85),
            verticalalignment="bottom",
        )

    # Legend.
    handles = [
        mpatches.Patch(color=color, label=label.value)
        for label, color in LABEL_COLORS.items()
    ]
    ax.legend(
        handles=handles,
        loc="upper right",
        fontsize=9,
        framealpha=0.9,
    )

    if title:
        ax.set_title(title, fontsize=14, pad=12)
    ax.axis("off")
    fig.tight_layout()
    return fig


def save_annotated(
    result: LayoutResult,
    image: Image.Image,
    output_dir: Path,
) -> Path:
    """Save an annotated image to the output directory."""
    stem = Path(result.image_path).stem
    title = f"{result.model_name} — {stem} ({result.elapsed_ms:.0f}ms)"
    fig = draw_regions(image, result.regions, title=title)

    out_path = output_dir / f"{stem}_{result.model_name}.png"
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return out_path


def save_comparison(
    results: list[LayoutResult],
    image: Image.Image,
    output_dir: Path,
) -> Path:
    """Save side-by-side comparison of multiple models on the same image."""
    n = len(results)
    fig, axes = plt.subplots(1, n, figsize=(12 * n, 16))
    if n == 1:
        axes = [axes]

    for ax, result in zip(axes, results):
        ax.imshow(image)
        for region in result.regions:
            left, top, right, bottom = region.bbox
            color = LABEL_COLORS.get(region.label, "#999999")
            rect = mpatches.FancyBboxPatch(
                (left, top),
                right - left,
                bottom - top,
                linewidth=2,
                edgecolor=color,
                facecolor=color,
                alpha=0.15,
                boxstyle="round,pad=2",
            )
            ax.add_patch(rect)
            badge = f"{region.label.value} ({region.confidence:.0%})"
            ax.text(
                left, top - 4, badge,
                fontsize=7, color="white",
                bbox=dict(boxstyle="round,pad=0.2", facecolor=color, alpha=0.85),
                verticalalignment="bottom",
            )
        ax.set_title(
            f"{result.model_name} ({result.elapsed_ms:.0f}ms)",
            fontsize=12,
        )
        ax.axis("off")

    # Shared legend.
    handles = [
        mpatches.Patch(color=color, label=label.value)
        for label, color in LABEL_COLORS.items()
    ]
    fig.legend(
        handles=handles,
        loc="lower center",
        ncol=len(LABEL_COLORS),
        fontsize=10,
        framealpha=0.9,
    )

    stem = Path(results[0].image_path).stem
    fig.suptitle(f"Layout Comparison — {stem}", fontsize=16, y=0.98)
    fig.tight_layout(rect=[0, 0.03, 1, 0.96])

    out_path = output_dir / f"{stem}_comparison.png"
    fig.savefig(out_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    return out_path
