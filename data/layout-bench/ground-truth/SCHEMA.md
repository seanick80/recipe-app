# Ground Truth Annotation Format

One JSON file per image, same stem name (e.g. `my_recipe.json` for `my_recipe.jpg`).

## Schema

```json
[
    {
        "bbox": [left, top, right, bottom],
        "label": "title | ingredients | instructions | metadata | other"
    }
]
```

## Labels

| Label          | What it covers                                         |
|----------------|--------------------------------------------------------|
| `title`        | Recipe name / heading                                  |
| `ingredients`  | Ingredient list (quantities, items)                    |
| `instructions` | Cooking steps / directions                             |
| `metadata`     | Servings, prep time, cook time, yield, calories        |
| `other`        | Phone numbers, ads, page numbers, stray handwriting    |

## Bounding boxes

Pixel coordinates: `[left, top, right, bottom]` relative to the original
image dimensions. Use any annotation tool that exports rectangles —
[Label Studio](https://labelstud.io/) and
[CVAT](https://www.cvat.ai/) both work.

## Example

```json
[
    {"bbox": [50, 20, 400, 70], "label": "title"},
    {"bbox": [50, 80, 350, 300], "label": "ingredients"},
    {"bbox": [50, 320, 500, 600], "label": "instructions"},
    {"bbox": [50, 610, 300, 640], "label": "metadata"},
    {"bbox": [400, 500, 520, 530], "label": "other"}
]
```

Ground truth is optional — the pipeline runs without it but can't compute
precision/recall/accuracy metrics.
