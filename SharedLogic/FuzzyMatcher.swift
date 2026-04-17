import Foundation

/// Fuzzy matching for post-OCR correction of handwritten list misreads.
/// Uses edit distance to suggest corrections from a known vocabulary.
///
/// Pure Swift — no Apple-specific frameworks beyond Foundation.

/// Suggests a correction for a potentially garbled OCR token.
///
/// - Parameters:
///   - input: The OCR-recognized word (e.g. "E995", "Milz").
///   - vocabulary: List of known correct words to match against.
/// - Returns: The best match if edit distance ≤ 2, or nil if no good match.
func suggestCorrection(_ input: String, vocabulary: [String]) -> String? {
    let lower = input.lowercased()

    // Exact match → no correction needed
    for word in vocabulary {
        if lower == word.lowercased() { return nil }
    }

    // Prefer exact substring matches first (input is a substring of a vocab
    // word or vice versa, with length difference ≤ 2).
    var bestMatch: String?
    var bestDistance = Int.max

    for word in vocabulary {
        let wordLower = word.lowercased()
        let dist = editDistance(lower, wordLower)

        if dist > 0 && dist <= 2 && dist < bestDistance {
            bestDistance = dist
            bestMatch = word
        } else if dist == bestDistance && dist <= 2 {
            // Tie-break: prefer shorter words (more common grocery items)
            if let current = bestMatch, word.count < current.count {
                bestMatch = word
            }
        }
    }

    return bestMatch
}

/// Computes the Levenshtein edit distance between two strings.
///
/// - Parameters:
///   - a: First string.
///   - b: Second string.
/// - Returns: Minimum number of single-character edits (insert, delete, replace).
func editDistance(_ a: String, _ b: String) -> Int {
    let aChars = Array(a)
    let bChars = Array(b)
    let m = aChars.count
    let n = bChars.count

    // Early exits for trivial cases
    if m == 0 { return n }
    if n == 0 { return m }

    // Single-row DP to save memory
    var prev = Array(0...n)
    var curr = Array(repeating: 0, count: n + 1)

    for i in 1...m {
        curr[0] = i
        for j in 1...n {
            if aChars[i - 1] == bChars[j - 1] {
                curr[j] = prev[j - 1]
            } else {
                curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
            }
        }
        (prev, curr) = (curr, prev)
    }

    return prev[n]
}

/// Extracts a vocabulary list from the GroceryCategorizer's known words.
/// This provides a reasonable set of common grocery items for fuzzy matching.
func groceryVocabulary() -> [String] {
    // We pull from the same keyword lists that GroceryCategorizer uses.
    // These are the most common grocery items that users would write.
    return [
        // Produce
        "apple", "apricot", "artichoke", "arugula", "asparagus",
        "avocado", "banana", "basil", "beet", "blueberry", "blackberry",
        "raspberry", "strawberry", "cranberry", "broccoli", "cabbage",
        "cantaloupe", "carrot", "cauliflower", "celery", "cherry",
        "cilantro", "clementine", "coconut", "corn", "cucumber",
        "dill", "eggplant", "fennel", "fig", "garlic", "ginger",
        "grape", "grapefruit", "kale", "kiwi", "leek", "lemon",
        "lettuce", "lime", "mango", "melon", "mint", "mushroom",
        "nectarine", "okra", "onion", "orange", "parsley", "parsnip",
        "peach", "pear", "pea", "pepper", "pineapple", "plum",
        "pomegranate", "potato", "pumpkin", "radish", "rosemary",
        "sage", "scallion", "shallot", "spinach", "squash",
        "thyme", "tomato", "turnip", "watermelon", "yam", "zucchini",
        // Dairy
        "milk", "cheese", "yogurt", "butter", "cream", "eggs", "egg",
        "buttermilk", "ghee", "mozzarella", "parmesan", "ricotta",
        "cheddar", "feta", "margarine",
        // Meat
        "chicken", "beef", "pork", "fish", "salmon", "shrimp",
        "bacon", "sausage", "turkey", "lamb", "ham", "steak",
        "tuna", "cod", "tilapia", "crab", "lobster",
        // Bakery
        "bread", "bagel", "muffin", "roll", "croissant", "tortilla",
        "bun", "pita", "naan", "cake", "pie",
        // Dry & Canned
        "rice", "pasta", "noodle", "spaghetti", "flour", "sugar",
        "salt", "oil", "cereal", "oatmeal", "granola", "beans",
        "lentils", "chickpea", "honey", "syrup", "vinegar",
        "vanilla", "yeast",
        // Snacks
        "chips", "cookies", "crackers", "candy", "chocolate",
        "nuts", "almonds", "popcorn",
        // Beverages
        "water", "juice", "soda", "coffee", "tea", "beer", "wine",
        // Household
        "soap", "detergent", "napkins", "towels", "tissues",
    ]
}
