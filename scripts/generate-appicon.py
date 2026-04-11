#!/usr/bin/env python3
"""scripts/generate-appicon.py - regenerate the placeholder AppIcon PNG.

Produces a 1024x1024 PNG placeholder at
RecipeApp/RecipeApp/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png.

This is a *placeholder* icon so Xcode archive builds succeed. Replace
with a real designed icon before App Store submission.

Usage (from repo root):
    python scripts/generate-appicon.py

Idempotent: overwrites the existing file.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = (
    REPO_ROOT
    / "RecipeApp"
    / "RecipeApp"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon-1024.png"
)

SIZE = 1024
BG = (242, 140, 64)  # warm orange - food / recipe vibe
FG = (255, 255, 255)
LETTER = "R"


def main() -> None:
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (SIZE, SIZE), BG)
    draw = ImageDraw.Draw(img)

    font = None
    for candidate in (
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ):
        try:
            font = ImageFont.truetype(candidate, size=720)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), LETTER, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (SIZE - text_w) / 2 - bbox[0]
    y = (SIZE - text_h) / 2 - bbox[1]
    draw.text((x, y), LETTER, fill=FG, font=font)

    img.save(OUT_PATH, format="PNG")
    print(f"wrote {OUT_PATH} ({OUT_PATH.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
