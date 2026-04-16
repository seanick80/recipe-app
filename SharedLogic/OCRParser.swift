import Foundation

/// Parses raw OCR text from a recipe photo into structured recipe fields.
/// Pure Swift — no Apple frameworks.
///
/// The OCR text is expected to be a full recipe with a title, ingredients
/// list, and instructions. This parser uses heuristic line-by-line analysis
/// to extract structure from flat text.

struct ParsedRecipe: Codable, Equatable {
    var title: String
    var ingredients: [ParsedIngredient]
    var instructions: [String]
    var servings: Int?
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
}

struct ParsedIngredient: Codable, Equatable {
    var name: String
    var quantity: Double
    var unit: String

    init(name: String, quantity: Double = 1, unit: String = "") {
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}

/// Section markers that indicate the start of an ingredients list.
private let ingredientHeaders = [
    "ingredients", "ingredient list", "what you need",
    "you will need", "you'll need", "shopping list",
]

/// Section markers that indicate the start of instructions.
private let instructionHeaders = [
    "instructions", "directions", "method", "steps",
    "preparation", "how to make", "procedure",
]

/// Parses raw OCR text into a `ParsedRecipe`.
func parseRecipeText(_ text: String) -> ParsedRecipe {
    let lines = text.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }

    var title = ""
    var ingredients: [ParsedIngredient] = []
    var instructions: [String] = []
    var servings: Int? = nil
    var prepTime: Int? = nil
    var cookTime: Int? = nil

    enum Section { case header, ingredients, instructions, unknown }
    var currentSection: Section = .header

    for line in lines {
        let lower = line.lowercased()

        // Skip blank lines
        if line.isEmpty { continue }

        // Detect section headers
        if ingredientHeaders.contains(where: { lower.hasPrefix($0) }) {
            currentSection = .ingredients
            continue
        }
        if instructionHeaders.contains(where: { lower.hasPrefix($0) }) {
            currentSection = .instructions
            continue
        }

        // Extract metadata from any section
        if let s = parseServings(lower) {
            servings = s
            continue
        }
        if let t = parseTimeField(lower, prefixes: ["prep time", "prep"]) {
            prepTime = t
            continue
        }
        if let t = parseTimeField(lower, prefixes: ["cook time", "cooking time", "cook"]) {
            cookTime = t
            continue
        }
        if let t = parseTimeField(lower, prefixes: ["total time", "total"]) {
            // If we have prep but not cook, derive cook from total
            if prepTime != nil && cookTime == nil {
                cookTime = max(0, t - (prepTime ?? 0))
            } else if prepTime == nil && cookTime == nil {
                // Just store as cook time
                cookTime = t
            }
            continue
        }

        switch currentSection {
        case .header:
            // First non-metadata, non-blank line is the title
            if title.isEmpty {
                title = cleanRecipeTitle(line)
            }
        case .ingredients:
            if let ingredient = parseIngredientLine(line) {
                ingredients.append(ingredient)
            }
        case .instructions:
            let cleaned = cleanInstructionLine(line)
            if !cleaned.isEmpty {
                instructions.append(cleaned)
            }
        case .unknown:
            break
        }
    }

    // Fallback: if no section headers were found, try parsing all non-title
    // lines as ingredients. Real-world recipe photos often lack headers.
    if ingredients.isEmpty && instructions.isEmpty {
        for line in lines {
            if line.isEmpty { continue }
            let lower = line.lowercased()
            // Skip the title line
            if line == title || line == cleanRecipeTitle(line) && line == title { continue }
            // Skip metadata lines
            if parseServings(lower) != nil { continue }
            if parseTimeField(lower, prefixes: ["prep time", "prep"]) != nil { continue }
            if parseTimeField(lower, prefixes: ["cook time", "cooking time", "cook"]) != nil { continue }
            if parseTimeField(lower, prefixes: ["total time", "total"]) != nil { continue }
            // Try as ingredient
            if let ingredient = parseIngredientLine(line) {
                ingredients.append(ingredient)
            }
        }
    }

    return ParsedRecipe(
        title: title,
        ingredients: ingredients,
        instructions: instructions,
        servings: servings,
        prepTimeMinutes: prepTime,
        cookTimeMinutes: cookTime
    )
}

/// Parses an ingredient line like "2 cups flour" or "1/2 lb chicken breast"
func parseIngredientLine(_ line: String) -> ParsedIngredient? {
    var cleaned = line.trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty else { return nil }

    // Strip list markers
    if cleaned.hasPrefix("- ") || cleaned.hasPrefix("• ") || cleaned.hasPrefix("* ") {
        cleaned = String(cleaned.dropFirst(2))
    }
    cleaned = cleaned.trimmingCharacters(in: .whitespaces)
    guard !cleaned.isEmpty else { return nil }

    // Reuse the list line parser logic
    if let parsed = parseListLine(cleaned) {
        return ParsedIngredient(name: parsed.name, quantity: parsed.quantity, unit: parsed.unit)
    }
    return ParsedIngredient(name: cleaned)
}

/// Extracts servings from a line like "Serves 4" or "Servings: 6"
func parseServings(_ lower: String) -> Int? {
    let patterns = ["serves", "servings:", "servings", "yield:", "yield", "makes"]
    for prefix in patterns {
        if lower.hasPrefix(prefix) {
            let rest = lower.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespaces)
            // Extract first number
            let digits = rest.prefix(while: { $0.isNumber })
            if let n = Int(digits), n > 0 { return n }
        }
    }
    return nil
}

/// Extracts time in minutes from a line like "Prep time: 20 min"
func parseTimeField(_ lower: String, prefixes: [String]) -> Int? {
    for prefix in prefixes {
        if lower.hasPrefix(prefix) {
            let rest = lower.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespaces)
            return parseTimeString(String(rest))
        }
    }
    return nil
}

/// Parses time strings like "20 min", "1 hour", "1h 30m", "90 minutes"
func parseTimeString(_ text: String) -> Int? {
    let lower = text.lowercased()
    var totalMinutes = 0
    var foundAny = false

    // Match hours: "1 hour", "2 hours", "1hr", "1h"
    // Use word-boundary-safe pattern: digits + optional space + hour word
    if let range = lower.range(
        of: "(\\d+)\\s*(?:hours?|hrs?|h)(?:[^a-z]|$)",
        options: .regularExpression
    ) {
        let match = String(lower[range])
        let digits = match.prefix(while: { $0.isNumber })
        if let h = Int(digits) {
            totalMinutes += h * 60
            foundAny = true
        }
    }

    // Match minutes: "30 minutes", "20 min", "30m"
    // Must not match "m" inside "hour" — require digits immediately before
    if let range = lower.range(
        of: "(\\d+)\\s*(?:minutes?|mins?|m)(?:[^a-z]|$)",
        options: .regularExpression
    ) {
        let match = String(lower[range])
        let digits = match.prefix(while: { $0.isNumber })
        if let m = Int(digits) {
            totalMinutes += m
            foundAny = true
        }
    }

    // Bare number — assume minutes
    if !foundAny {
        let digits = lower.prefix(while: { $0.isNumber })
        if let m = Int(digits), m > 0 {
            return m
        }
    }

    return foundAny ? totalMinutes : nil
}

/// Cleans a recipe title (removes trailing colons, excess whitespace).
func cleanRecipeTitle(_ title: String) -> String {
    var cleaned = title.trimmingCharacters(in: .whitespaces)
    if cleaned.hasSuffix(":") {
        cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespaces)
    }
    return cleaned
}

/// Cleans an instruction line (removes numbered prefixes like "1. ", "Step 2: ").
func cleanInstructionLine(_ line: String) -> String {
    var cleaned = line.trimmingCharacters(in: .whitespaces)

    // Remove "Step N:" or "Step N." prefix
    if cleaned.lowercased().hasPrefix("step") {
        let rest = cleaned.dropFirst(4).trimmingCharacters(in: .whitespaces)
        // Drop the number and separator
        let afterNum = rest.drop(while: { $0.isNumber })
            .trimmingCharacters(in: .whitespaces)
        if afterNum.hasPrefix(":") || afterNum.hasPrefix(".") || afterNum.hasPrefix(")") {
            cleaned = String(afterNum.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
    }
    // Remove "N. " or "N) " prefix
    else if cleaned.first?.isNumber == true {
        let afterNum = cleaned.drop(while: { $0.isNumber })
            .trimmingCharacters(in: .whitespaces)
        if afterNum.hasPrefix(".") || afterNum.hasPrefix(")") {
            cleaned = String(afterNum.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
    }

    return cleaned
}
