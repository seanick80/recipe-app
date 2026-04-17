import Foundation

/// Strips preparation notes and size adjectives from ingredient names so
/// shopping lists show only what to buy, not how to prep it.
///
/// Pure Swift — no Apple-specific frameworks beyond Foundation.

/// Result of stripping prep notes from an ingredient name.
struct StrippedIngredient {
    var name: String
    var prep: String
    var sizeAdjective: String
}

/// Prep verbs/participles that are useless on a shopping list. Each entry
/// should be lowercase; matching is case-insensitive via lowercased input.
private let prepWords: Set<String> = [
    "chopped", "diced", "grated", "sifted", "melted", "softened",
    "sliced", "minced", "peeled", "toasted", "roasted", "blanched",
    "seeded", "deveined", "squeezed", "trimmed", "crushed", "cubed",
    "julienned", "shredded", "halved", "quartered", "mashed",
    "crumbled", "torn", "beaten", "whisked", "thawed", "drained",
    "rinsed", "cored", "pitted", "zested", "divided", "packed",
    "sieved", "ground", "cracked", "snipped", "scored",
]

/// Multi-word prep phrases that should be stripped as a unit.
private let prepPhrases: [String] = [
    "finely chopped", "roughly chopped", "coarsely chopped",
    "finely diced", "finely grated", "freshly grated",
    "finely sliced", "thinly sliced", "thickly sliced",
    "finely minced", "freshly ground", "freshly squeezed",
    "freshly cracked", "lightly beaten", "lightly toasted",
    "at room temperature", "room temperature",
    "cut into chunks", "cut into cubes", "cut into pieces",
    "cut into strips", "cut into wedges", "cut into rings",
    "excess moisture squeezed out", "moisture squeezed out",
    "patted dry", "bones removed", "skin removed",
    "stems removed", "seeds removed", "rind removed",
    "to taste", "for garnish", "for serving", "for decoration",
    "plus extra", "plus more",
]

/// Size adjectives to strip when they precede a food word. Lowercase.
private let sizeAdjectives: Set<String> = [
    "large", "medium", "small", "big", "tiny", "extra-large", "jumbo",
]

/// Words that confirm the next word is a food item (so "large onion" strips
/// "large" but "large" alone does not). This is a quick heuristic — we check
/// if removing the adjective still leaves a non-empty name.
///
/// We don't maintain a full food dictionary; instead, we strip the size
/// adjective only when the remainder is ≥ 2 characters long (so bare "large"
/// is left alone).

/// Strips prep notes from an ingredient name.
///
/// - Parameter name: Raw ingredient name, e.g. "Large Onion, Finely Chopped"
/// - Returns: Cleaned name, extracted prep notes, and any stripped size adjective.
func stripPrepNotes(_ name: String) -> StrippedIngredient {
    var working = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !working.isEmpty else {
        return StrippedIngredient(name: "", prep: "", sizeAdjective: "")
    }

    // Strip parenthesized quantity prefixes like "(1 Cup)" or "(2 tbsp)"
    let parenPattern = #"^\s*\([^)]*\)\s*"#
    if let range = working.range(of: parenPattern, options: .regularExpression) {
        working = String(working[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
    }

    var collectedPrep: [String] = []

    // First pass: strip known multi-word prep phrases (case-insensitive).
    let lower = working.lowercased()
    for phrase in prepPhrases {
        if lower.contains(phrase) {
            // Remove the phrase and any surrounding comma/space.
            let pattern = ",?\\s*(?i)" + NSRegularExpression.escapedPattern(for: phrase) + "\\s*,?"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(working.startIndex..., in: working)
                let matched = regex.firstMatch(in: working, range: range)
                if let matched = matched {
                    let matchRange = Range(matched.range, in: working)!
                    let extracted = working[matchRange]
                        .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                    collectedPrep.append(extracted.lowercased())
                    working = working.replacingCharacters(in: matchRange, with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
    }

    // Second pass: split on commas and check trailing segments for prep words.
    let segments = working.components(separatedBy: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
    }

    var keptSegments: [String] = []
    for (i, segment) in segments.enumerated() {
        if i == 0 {
            // First segment is always the core name
            keptSegments.append(segment)
            continue
        }
        let words = segment.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        let isPrepSegment =
            !words.isEmpty
            && words.allSatisfy { word in
                prepWords.contains(word) || word == "and" || word == "or"
                    || word == "then" || word == "well"
            }
        if isPrepSegment {
            collectedPrep.append(segment.lowercased())
        } else {
            keptSegments.append(segment)
        }
    }

    working = keptSegments.joined(separator: ", ")
        .trimmingCharacters(in: CharacterSet(charactersIn: ", "))

    // Third pass: strip leading size adjective.
    var sizeAdj = ""
    let nameWords = working.components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
    if nameWords.count >= 2 {
        let firstLower = nameWords[0].lowercased()
        if sizeAdjectives.contains(firstLower) {
            sizeAdj = nameWords[0].lowercased()
            working = nameWords.dropFirst().joined(separator: " ")
        }
    }

    // Clean up any dangling commas or whitespace
    working =
        working
        .trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        .trimmingCharacters(in: .whitespaces)

    let prep = collectedPrep.joined(separator: ", ")

    return StrippedIngredient(
        name: working,
        prep: prep,
        sizeAdjective: sizeAdj
    )
}
