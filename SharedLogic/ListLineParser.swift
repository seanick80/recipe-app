import Foundation

/// Parses raw text lines (from OCR of a handwritten shopping list) into
/// structured grocery item candidates. Pure Swift — no Apple frameworks.
///
/// Input: multi-line string from OCR (one item per line, possibly with
/// quantities like "2 cans tomatoes" or "milk x3").
/// Output: array of `ParsedListItem` structs ready for user confirmation.

struct ParsedListItem: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String

    init(name: String, quantity: Double = 1, unit: String = "") {
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}

/// Known unit abbreviations and their canonical forms.
let knownUnits: [String: String] = [
    "g": "g", "gram": "g", "grams": "g",
    "kg": "kg", "kilogram": "kg", "kilograms": "kg",
    "mg": "mg", "milligram": "mg", "milligrams": "mg",
    "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
    "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
    "lb": "lb", "lbs": "lb", "pound": "lb", "pounds": "lb",
    "oz": "oz", "ounce": "oz", "ounces": "oz",
    "gal": "gallon", "gallon": "gallon", "gallons": "gallon",
    "qt": "quart", "quart": "quart", "quarts": "quart",
    "pt": "pint", "pint": "pint", "pints": "pint",
    "cup": "cup", "cups": "cup",
    "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp",
    "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
    "can": "can", "cans": "can",
    "bag": "bag", "bags": "bag",
    "box": "box", "boxes": "box",
    "bottle": "bottle", "bottles": "bottle",
    "bunch": "bunch", "bunches": "bunch",
    "dozen": "dozen", "doz": "dozen",
    "loaf": "loaf", "loaves": "loaf",
    "count": "count", "ct": "count",
    "pkg": "package", "package": "package", "packages": "package",
    "jar": "jar", "jars": "jar",
    "stick": "stick", "sticks": "stick",
    "head": "head", "heads": "head",
    "piece": "piece", "pieces": "piece", "pc": "piece", "pcs": "piece",
    "roll": "roll", "rolls": "roll",
    "pack": "pack", "packs": "pack",
    "slice": "slice", "slices": "slice",
]

/// Parses a multi-line OCR string into an array of `ParsedListItem`.
/// Blank lines and lines that look like headers/noise are skipped.
func parseShoppingListText(_ text: String) -> [ParsedListItem] {
    let lines = text.components(separatedBy: .newlines)
    return lines.compactMap { parseListLine($0) }
}

/// Parses a single line of text into a `ParsedListItem`, or nil if the
/// line is blank/noise.
///
/// Supported formats:
///   "milk"                    → (milk, 1, "")
///   "2 milk"                  → (milk, 2, "")
///   "2x milk"                 → (milk, 2, "")
///   "milk x3"                 → (milk, 3, "")
///   "2 cans tomatoes"         → (tomatoes, 2, "can")
///   "1 lb chicken breast"     → (chicken breast, 1, "lb")
///   "- eggs"                  → (eggs, 1, "")     (bullet prefix stripped)
///   "• bread"                 → (bread, 1, "")     (bullet prefix stripped)
///   "3. bananas"              → (bananas, 3, "")   (numbered list)
func parseListLine(_ rawLine: String) -> ParsedListItem? {
    var line = rawLine.trimmingCharacters(in: .whitespaces)

    // Skip blank lines
    guard !line.isEmpty else { return nil }

    // Strip common list prefixes: "- ", "• ", "* ", "[] ", "[x] "
    if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
        line = String(line.dropFirst(2))
    } else if line.hasPrefix("[] ") {
        line = String(line.dropFirst(3))
    } else if line.hasPrefix("[x] ") || line.hasPrefix("[X] ") {
        line = String(line.dropFirst(4))
    }

    line = line.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty else { return nil }

    // Skip lines that look like headers (all caps, short, no lowercase)
    if line.count <= 20 && line == line.uppercased() && line.rangeOfCharacter(from: .lowercaseLetters) == nil
        && line.rangeOfCharacter(from: .letters) != nil
    {
        // Could be a category header like "DAIRY" or "PRODUCE"
        return nil
    }

    var quantity: Double = 1
    var unit: String = ""

    let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard !tokens.isEmpty else { return nil }

    var startIndex = 0

    // Try to parse leading quantity: "2", "2x", "0.5"
    if let firstNum = parseQuantityToken(tokens[0]) {
        quantity = firstNum
        startIndex = 1
        // Compound fraction: "1 1/2", "1 ½", "2 3/4"
        if startIndex < tokens.count && firstNum == Double(Int(firstNum)) {
            if let frac = parseQuantityToken(tokens[startIndex]),
                frac > 0 && frac < 1
            {
                quantity = firstNum + frac
                startIndex += 1
            }
        }
        // Also handle "1 and 1/2"
        if startIndex < tokens.count && tokens[startIndex].lowercased() == "and" {
            if startIndex + 1 < tokens.count,
                let frac = parseQuantityToken(tokens[startIndex + 1]),
                frac > 0 && frac < 1
            {
                quantity = firstNum + frac
                startIndex += 2
            }
        }
    } else if let fused = parseFusedQuantityUnit(tokens[0]) {
        // Handles tokens like "150g", "60ml", "2oz" where OCR / recipe
        // formatting has glued the number and unit with no space.
        quantity = fused.quantity
        unit = fused.unit
        startIndex = 1
    }

    // Check for "x3" or "×3" suffix at end of line
    if startIndex == 0 {
        let lastToken = tokens[tokens.count - 1]
        if let trailingQty = parseTrailingMultiplier(lastToken) {
            quantity = trailingQty
            // Parse remaining tokens (excluding last)
            let nameTokens = tokens.dropLast()
            if nameTokens.isEmpty { return nil }
            let name = nameTokens.joined(separator: " ")
            return ParsedListItem(name: cleanItemName(name), quantity: quantity, unit: unit)
        }
    }

    // Check for numbered list: "3. bananas" — the number is the quantity
    if startIndex == 0 && tokens[0].hasSuffix(".") {
        let numPart = String(tokens[0].dropLast())
        if let n = Double(numPart), n > 0, n <= 100 {
            quantity = n
            startIndex = 1
        }
    }

    // Check if next token is a known unit
    if startIndex < tokens.count {
        let candidate = tokens[startIndex].lowercased()
        if let canonical = knownUnits[candidate] {
            unit = canonical
            startIndex += 1
        }
    }

    // Remaining tokens form the item name
    guard startIndex < tokens.count else {
        // Only had a number and maybe a unit, no item name
        // Treat the unit as the name if we have one
        if !unit.isEmpty {
            return ParsedListItem(name: unit, quantity: quantity, unit: "")
        }
        return nil
    }

    let name = tokens[startIndex...].joined(separator: " ")
    return ParsedListItem(name: cleanItemName(name), quantity: quantity, unit: unit)
}

/// Attempts to parse a token as a quantity number.
/// Handles: "2", "2x", "0.5", "½", "1/2"
func parseQuantityToken(_ token: String) -> Double? {
    var t = token

    // Strip trailing "x" or "×" multiplier marker
    if t.hasSuffix("x") || t.hasSuffix("×") {
        t = String(t.dropLast())
    }

    // Direct number
    if let n = Double(t), n > 0 { return n }

    // Fused whole number + unicode fraction: "1½", "2¼", "1¾"
    let unicodeFractions: [Character: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
        "¼": 0.25, "¾": 0.75,
    ]
    if t.count >= 2 {
        let lastChar = t.last!
        if let fracValue = unicodeFractions[lastChar] {
            let wholePart = String(t.dropLast())
            if let whole = Double(wholePart), whole > 0 {
                return whole + fracValue
            }
        }
    }

    // Unicode fractions
    let fractions: [String: Double] = [
        "½": 0.5, "⅓": 1.0 / 3, "⅔": 2.0 / 3,
        "¼": 0.25, "¾": 0.75,
    ]
    if let f = fractions[t] { return f }

    // Slash fraction: "1/2", "3/4"
    let parts = t.split(separator: "/")
    if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
        return num / den
    }

    return nil
}

/// Metric/imperial units that commonly appear fused to their quantity
/// in printed recipes (e.g. "150g", "60ml", "2oz"). Only the short-form
/// mass/volume units are recognized in fused form — word units like
/// "cup" or "tbsp" are left to the space-separated path so ambiguous
/// tokens like "cups" aren't misparsed.
private let fusedUnitCanonicalForms: [String: String] = [
    "g": "g", "kg": "kg",
    "mg": "mg",
    "ml": "ml", "l": "l",
    "oz": "oz", "lb": "lb", "lbs": "lb",
]

/// Attempts to split a single fused token like "150g" or "60ml" into a
/// quantity and unit. Returns nil if the token doesn't match
/// `<number><short-unit>` exactly (trailing punctuation like a comma is
/// ignored so "375g," still parses).
func parseFusedQuantityUnit(_ token: String) -> (quantity: Double, unit: String)? {
    // Strip trailing punctuation the ingredient line may have attached.
    let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:"))
    guard !trimmed.isEmpty else { return nil }

    // Find the boundary between the numeric prefix and the alpha suffix.
    var splitIndex = trimmed.startIndex
    for ch in trimmed {
        if ch.isNumber || ch == "." {
            splitIndex = trimmed.index(after: splitIndex)
        } else {
            break
        }
    }
    guard splitIndex > trimmed.startIndex, splitIndex < trimmed.endIndex else {
        return nil
    }

    let numPart = String(trimmed[trimmed.startIndex..<splitIndex])
    let unitPart = String(trimmed[splitIndex...]).lowercased()

    guard let qty = Double(numPart), qty > 0 else { return nil }
    guard let canonical = fusedUnitCanonicalForms[unitPart] else { return nil }
    return (qty, canonical)
}

/// Parses trailing multiplier like "x3", "×2"
func parseTrailingMultiplier(_ token: String) -> Double? {
    let t = token
    if (t.hasPrefix("x") || t.hasPrefix("×")) && t.count > 1 {
        let numPart = String(t.dropFirst())
        if let n = Double(numPart), n > 0 { return n }
    }
    return nil
}

/// Cleans up an item name: trims whitespace, removes trailing punctuation.
func cleanItemName(_ name: String) -> String {
    var cleaned = name.trimmingCharacters(in: .whitespaces)
    // Remove trailing punctuation that OCR might add
    while cleaned.hasSuffix(",") || cleaned.hasSuffix(".") || cleaned.hasSuffix(";") {
        cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
    }
    return cleaned
}
