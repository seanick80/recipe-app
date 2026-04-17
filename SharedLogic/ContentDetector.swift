import Foundation

/// Detects whether OCR text is a shopping list or a recipe, so the scan
/// pipeline can warn users who photograph a recipe from the shopping-list
/// scanner.
///
/// Pure Swift — no Apple-specific frameworks beyond Foundation.

/// Content type detected from OCR text.
enum ContentType: String {
    case shoppingList
    case recipe
    case unknown
}

/// Recipe marker keywords — if ≥ 2 are found in the text, it's probably a
/// recipe, not a shopping list. These reuse the same vocabulary as
/// `QualityGate.sectionFromHeader()` plus additional recipe signals.
private let recipeMarkers: [String] = [
    // Section headers (from QualityGate)
    "ingredients", "ingredient list", "what you need", "what you'll need",
    "method", "directions", "instructions", "preparation", "procedure",
    "steps", "how to make",
    // Additional recipe signals
    "preheat", "preheat oven", "bake at", "cook for", "simmer",
    "prep time", "cook time", "total time", "servings", "serves",
    "yield", "makes", "minutes", "degrees",
]

/// Shopping list markers — numbered/bulleted item lines, category headers.
private let shoppingMarkers: [String] = [
    "grocery", "shopping list", "to buy", "need to get",
]

/// Detects the content type of OCR text.
///
/// Scans for recipe-specific markers (section headers, cooking verbs, time
/// references). If ≥ 2 distinct markers are found, returns `.recipe`.
///
/// - Parameter text: Raw OCR text (all lines joined or multi-line).
/// - Returns: Detected content type.
func detectContentType(_ text: String) -> ContentType {
    let lower = text.lowercased()

    var recipeHits = 0
    var matchedMarkers: Set<String> = []
    for marker in recipeMarkers {
        if lower.contains(marker) && !matchedMarkers.contains(marker) {
            matchedMarkers.insert(marker)
            recipeHits += 1
        }
    }

    // Also check for "step N" patterns (step 1, step 2, etc.)
    let stepPattern = #"step\s+\d"#
    if let _ = lower.range(of: stepPattern, options: .regularExpression) {
        recipeHits += 1
    }

    var shoppingHits = 0
    for marker in shoppingMarkers {
        if lower.contains(marker) {
            shoppingHits += 1
        }
    }

    // If there are strong shopping signals, bias toward shopping list
    if shoppingHits > 0 && recipeHits < 3 {
        return .shoppingList
    }

    // 2+ recipe markers → likely a recipe
    if recipeHits >= 2 {
        return .recipe
    }

    return .unknown
}
