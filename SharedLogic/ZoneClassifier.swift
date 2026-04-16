import Foundation

/// Classifies a block of OCR text into recipe zones by content analysis.
/// Pure Swift — no Apple frameworks.
///
/// This is the Swift port of the Python `ocr_classify._score_block()` from
/// the layout analysis bench. Instead of structural document analysis, we
/// read the text and decide what it is based on content patterns.

/// Semantic zone label for a block of text on a recipe page.
enum ZoneLabel: String, Codable, Equatable {
    case title
    case ingredients
    case instructions
    case metadata
    case handwritten
    case other
}

/// Result of classifying a text block.
struct ZoneClassification: Codable, Equatable {
    var label: ZoneLabel
    var confidence: Double
}

// MARK: - Content Patterns

/// Ingredient signals: quantities, units, food words.
private let ingredientPatterns: [(NSRegularExpression, Double)] = {
    let patterns: [(String, Double)] = [
        // Quantity + unit: "2 cups", "1/2 lb", "3 tbsp"
        (
            "\\b\\d+\\s*(?:cup|tbsp|tsp|oz|ounce|lb|pound|g|gram|kg|ml|liter|litre"
                + "|bunch|clove|pinch|dash|can|pkg|package|stick|slice|piece|head"
                + "|tablespoon|teaspoon|quart|gallon|pint)s?\\b",
            1.0
        ),
        // Fractions: 1/2, 3/4
        ("\\b\\d+\\s*/\\s*\\d+\\b", 0.8),
        // Bullet list items
        ("^\\s*[-•*]\\s+\\w", 0.5),
        // Common ingredient words
        (
            "\\b(?:salt|pepper|sugar|flour|butter|oil|garlic|onion|egg|cream"
                + "|cheese|milk|chicken|beef|pork|fish|rice|pasta|vinegar|sauce"
                + "|lemon|lime|herb|spice|cumin|paprika|cinnamon|vanilla|honey"
                + "|olive|sesame|ginger|cilantro|parsley|basil|thyme|oregano"
                + "|tomato|potato|carrot|celery|mushroom|broccoli|spinach"
                + "|yogurt|mayo|mustard|ketchup)s?\\b",
            0.6
        ),
    ]
    return patterns.compactMap { (pattern, weight) in
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .anchorsMatchLines]
            )
        else { return nil }
        return (regex, weight)
    }
}()

/// Instruction signals: cooking verbs, numbered steps, temperatures, times.
private let instructionPatterns: [(NSRegularExpression, Double)] = {
    let patterns: [(String, Double)] = [
        // Cooking verbs
        (
            "\\b(?:preheat|stir|mix|bake|cook|simmer|saut[eé]|chop|dice"
                + "|slice|fold|whisk|drain|combine|add|pour|heat|remove|serve"
                + "|let stand|set aside|bring to|reduce|cover|uncover|roast"
                + "|grill|fry|sear|marinate|toss|season|drizzle|spread|layer"
                + "|arrange|transfer|cool|chill|refrigerate|freeze|thaw"
                + "|knead|roll|shape|form|stuff|wrap|assemble|garnish|plate"
                + "|broil|steam|blanch|deglaze|braise|poach|whip|beat"
                + "|scrape|melt|dissolve|sprinkle|brush|coat|dip)\\b",
            1.0
        ),
        // Numbered steps: "1.", "Step 3"
        ("^\\s*(?:\\d+[.)]\\s|step\\s+\\d)", 0.8),
        // Temperature: "350°F", "180 C", "oven"
        ("\\b\\d{3}\\s*°?\\s*[FCfc]\\b|\\boven\\b", 0.7),
        // Time: "20 minutes", "1 hour"
        ("\\b\\d+\\s*(?:min(?:ute)?|hour|hr)s?\\b|\\bovernight\\b", 0.6),
    ]
    return patterns.compactMap { (pattern, weight) in
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .anchorsMatchLines]
            )
        else { return nil }
        return (regex, weight)
    }
}()

/// Metadata signals: servings, times, yield.
private let metadataPattern: NSRegularExpression? = try? NSRegularExpression(
    pattern:
        "\\b(?:serves?|servings?|yield|makes?\\s+\\d|prep\\s*time|cook\\s*time"
        + "|total\\s*time|calories|difficulty|active\\s*time|rest\\s*time"
        + "|ready\\s+in|hands-on)\\b",
    options: .caseInsensitive
)

/// Junk signals: phone numbers, URLs, page numbers, copyright.
private let junkPatterns: [NSRegularExpression] = {
    let patterns = [
        "\\b\\d{3}[-. ]?\\d{3}[-. ]?\\d{4}\\b",
        "\\b(?:www\\.|http|\\. com|\\. org|\\. net)\\b",
        "^\\s*(?:page\\s+)?\\d{1,3}\\s*$",
        "\\b(?:copyright|©|all rights reserved|advertisement)\\b",
    ]
    return patterns.compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive, .anchorsMatchLines])
    }
}()

/// Handwriting content signals: scaling marks, annotation symbols.
private let handwritingContentPattern: NSRegularExpression? = try? NSRegularExpression(
    pattern: "[×xX]\\s*\\d+\\.?\\d*\\b|\\b\\d+\\.?\\d*\\s*[×xX]\\b|\\bdouble\\b|\\bhalf\\b",
    options: [.caseInsensitive, .anchorsMatchLines]
)

/// Section sub-heading keywords.
private let sectionHeaderKeywords = [
    "ingredient", "direction", "instruction", "method",
    "step", "preparation", "procedure", "assembly",
    "for the", "garnish", "topping", "filling",
    "frosting", "glaze", "sauce", "dressing", "note",
]

// MARK: - Scoring

/// Counts regex matches in text, returning weighted hit count.
private func countMatches(
    _ patterns: [(NSRegularExpression, Double)],
    in text: String
) -> Double {
    let range = NSRange(text.startIndex..., in: text)
    var total = 0.0
    for (regex, weight) in patterns {
        let count = regex.numberOfMatches(in: text, range: range)
        total += Double(count) * weight
    }
    return total
}

/// Returns true if any pattern matches.
private func anyMatch(_ patterns: [NSRegularExpression], in text: String) -> Bool {
    let range = NSRange(text.startIndex..., in: text)
    return patterns.contains { $0.firstMatch(in: text, range: range) != nil }
}

/// Classifies a block of text by content patterns.
///
/// Scores each zone label independently, then returns the best. A block with
/// 8 ingredient-like lines and 1 cooking verb is "ingredients", not a mix.
func classifyZone(_ text: String) -> ZoneClassification {
    let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stripped.isEmpty else {
        return ZoneClassification(label: .other, confidence: 0.1)
    }

    let lines = stripped.components(separatedBy: .newlines)
    let lineCount = max(lines.count, 1)

    var scores: [ZoneLabel: Double] = [
        .title: 0.0,
        .ingredients: 0.0,
        .instructions: 0.0,
        .metadata: 0.0,
        .handwritten: 0.0,
        .other: 0.1,
    ]

    // --- Ingredient scoring ---
    let ingredientHits = countMatches(ingredientPatterns, in: stripped)
    if ingredientHits > 0 {
        let density = ingredientHits / Double(lineCount)
        scores[.ingredients] = min(0.3 + density * 0.25, 0.95)
    }

    // --- Instruction scoring ---
    let instructionHits = countMatches(instructionPatterns, in: stripped)
    if instructionHits > 0 {
        let density = instructionHits / Double(lineCount)
        scores[.instructions] = min(0.3 + density * 0.2, 0.95)
    }

    // --- Metadata scoring ---
    // Only count metadata when it appears in short text (1-3 lines) that looks
    // like standalone metadata, not embedded in a long instruction block.
    let range = NSRange(stripped.startIndex..., in: stripped)
    if let regex = metadataPattern, regex.firstMatch(in: stripped, range: range) != nil {
        // Scale metadata score by line count — strong for short blocks,
        // weak when buried in a paragraph of instructions.
        let metaWeight = lineCount <= 3 ? 0.7 : 0.2
        scores[.metadata] = (scores[.metadata] ?? 0) + metaWeight
    }

    // --- Junk scoring ---
    if anyMatch(junkPatterns, in: stripped) {
        scores[.other] = (scores[.other] ?? 0) + 0.6
    }

    // --- Handwriting content ---
    if let regex = handwritingContentPattern, regex.firstMatch(in: stripped, range: range) != nil {
        scores[.handwritten] = (scores[.handwritten] ?? 0) + 0.4
    }

    // --- Title heuristic ---
    // Short text (1-2 lines, <60 chars) that starts with a capital letter
    // and has no quantity/unit patterns (just food word matches) is likely a title.
    // "Grandma's Chicken Soup" matches food words but has no quantities.
    if lines.count <= 2 && stripped.count < 60 {
        let firstChar = stripped.first ?? Character(" ")
        if firstChar.isUppercase {
            // Check for quantity+unit patterns (first 2 ingredient patterns).
            let textRange = NSRange(stripped.startIndex..., in: stripped)
            var hasQuantity = false
            for i in 0..<min(2, ingredientPatterns.count) {
                let (regex, _) = ingredientPatterns[i]
                if regex.firstMatch(in: stripped, range: textRange) != nil {
                    hasQuantity = true
                    break
                }
            }
            let hasInstructionVerb = (scores[.instructions] ?? 0) > 0.3
            if !hasQuantity && !hasInstructionVerb {
                scores[.title] = 0.6
            }
        }
    }

    // --- Sub-heading detection ---
    let trimmedColon = stripped.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    if lines.count == 1 && trimmedColon.split(separator: " ").count <= 4 {
        let lower = trimmedColon.lowercased()
        if sectionHeaderKeywords.contains(where: { lower.contains($0) }) {
            scores[.title] = 0.8
        }
    }

    // Find best label.
    let best = scores.max(by: { $0.value < $1.value })!
    return ZoneClassification(label: best.key, confidence: best.value)
}

/// Classifies an array of text blocks, returning zone labels for each.
func classifyZones(_ blocks: [String]) -> [ZoneClassification] {
    blocks.map { classifyZone($0) }
}

/// Filters an array of text blocks, returning only those matching the given label.
func filterZones(_ blocks: [String], label: ZoneLabel) -> [String] {
    zip(blocks, classifyZones(blocks))
        .filter { $0.1.label == label }
        .map { $0.0 }
}
