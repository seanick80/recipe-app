# Layout Analysis Benchmark

Local evaluation pipeline for comparing document layout analysis approaches
on recipe page images. Runs entirely on Windows with PyTorch — no macOS or
CoreML required.

## Why

The recipe scanner currently OCR's the entire page and parses all text as
a flat stream. This causes problems when recipes sit alongside non-recipe
content (phone numbers, ads, handwritten notes). A layout-aware pipeline
would first detect *where* the recipe regions are, then parse only those.

This bench lets us test different approaches on real recipe images before
committing to a model for the iOS app.

## Quick start

```bash
# Install dependencies (one-time)
pip install -r scripts/layout-bench/requirements.txt

# Drop recipe photos into the test images folder
cp ~/photos/cookbook_page_*.jpg data/layout-bench/images/

# Run all models
python scripts/layout-bench/evaluate.py

# Run a specific model
python scripts/layout-bench/evaluate.py --model heuristic

# Side-by-side comparison
python scripts/layout-bench/evaluate.py --compare
```

Results (annotated images + JSON) land in `data/layout-bench/results/`.

## Models

| Name           | Type                          | Speed  | What it does                                           |
|----------------|-------------------------------|--------|--------------------------------------------------------|
| `heuristic`    | OCR + per-line patterns       | ~15s   | EasyOCR text detection → spatial clustering → regex per line |
| `ocr-classify` | OCR + block content scoring   | ~15s   | EasyOCR → merge into blocks → classify by text content |
| `dit`          | DETR obj detection (DocLayNet)| ~5s    | Transformer layout detection (needs better model checkpoint) |

More models can be added by implementing the `LayoutModel` protocol in
`models/base.py` and registering in `models/__init__.py`.

## Region labels

| Label          | Color  | What it covers                                      |
|----------------|--------|-----------------------------------------------------|
| `title`        | Blue   | Recipe name / heading                               |
| `ingredients`  | Green  | Ingredient list (quantities, items)                 |
| `instructions` | Orange | Cooking steps / directions                          |
| `metadata`     | Purple | Servings, prep time, cook time, yield               |
| `other`        | Red    | Phone numbers, ads, page numbers, stray notes       |

## Ground truth (optional)

For quantitative metrics (precision, recall, label accuracy), create
annotation files in `data/layout-bench/ground-truth/`. See
[SCHEMA.md](../../data/layout-bench/ground-truth/SCHEMA.md) for format.

5-10 annotated images is enough for development iteration.

### Public datasets for supplemental benchmarking

| Dataset | Size | License | Relevance | Notes |
|---------|------|---------|-----------|-------|
| [VDR Cooking Recipes](https://huggingface.co/datasets/racineai/OGC_Cooking_Recipes) | ~23k | Apache 2.0 | **High** | Real recipe document images with text pairs. No bbox annotations but best source of recipe page images. |
| [DocLayNet](https://huggingface.co/datasets/docling-project/DocLayNet) | 80k pages | CDLA-Permissive | Medium | 11 layout classes. "Manuals" category closest to recipe layouts. Best for pre-training layout detector. |
| [FUNSD](https://guillaumejaume.github.io/FUNSD/) | 199 forms | CC BY 4.0 | Medium | Noisy scans, mixed printed/handwritten. Good for OCR quality testing on degraded scans. |
| [OmniDocBench](https://huggingface.co/datasets/opendatalab/OmniDocBench) | 1.6k pages | Research | Medium | High annotation quality, includes handwritten notes and textbook categories. |
| [PubLayNet](https://huggingface.co/datasets/jordanparker6/publaynet) | 360k pages | CDLA-Permissive | Low-Med | 5 layout classes, scientific papers only. Models pre-trained here struggle with freeform layouts. |

No purpose-built recipe page scan dataset with layout bounding boxes exists.
Your personal 5-10 photos are more valuable than any generic dataset for
tuning this specific pipeline. For a reportable benchmark, 200-500 annotated
pages is the accepted minimum (FUNSD uses just 199).

## Output

- **Annotated images**: bounding boxes color-coded by region label
- **Comparison images**: side-by-side when `--compare` is used
- **results.json**: machine-readable results with regions, timings, metrics
- **Console summary**: region counts and metrics per model per image

## Adding a new model

1. Create `models/your_model.py` implementing `LayoutModel` protocol
2. Register it in `models/__init__.py`
3. Run: `python evaluate.py --model your_model`
