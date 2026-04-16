# Golden Recipe Extraction Format

One JSON file per image, same stem name (e.g. `chocChip.json` for `chocChip.png`).

These files represent the **expected recipe output** after the full pipeline
(OCR + layout analysis + parsing) runs on an image. They validate that zone
detection produces correct recipe content end-to-end, not just correct bounding
boxes.

## Schema

```json
{
    "title": "Recipe Name",
    "ingredients": [
        "100g unsalted butter",
        "2 eggs",
        "..."
    ],
    "instructions": [
        "Heat the oven to 160°C.",
        "Combine butter, sugar, egg and vanilla.",
        "..."
    ],
    "metadata": {
        "servings": "4",
        "prep_time": "10 minutes",
        "cook_time": "30 minutes"
    },
    "notes": "Optional freeform notes or source attribution."
}
```

## Matching rules

- **title**: Fuzzy string match (case-insensitive, ignore punctuation).
- **ingredients**: Each golden ingredient must appear (substring match) in at
  least one extracted ingredient region. Order does not matter. OCR typos are
  tolerated via fuzzy matching (ratio >= 0.8).
- **instructions**: Each golden step must appear (substring) in at least one
  extracted instruction region. Order matters for numbering but not for match.
- **metadata**: Key-value fuzzy match where present.
- **Recall-oriented**: we care more about not *missing* content than about
  extra noise in the extraction. Precision is secondary.
