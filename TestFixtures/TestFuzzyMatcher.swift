import Foundation

// MARK: - FuzzyMatcher Tests

func testFuzzyMatching() {
    let vocab = ["Milk", "Bread", "Eggs"]

    // Exact match returns nil
    check(suggestCorrection("Eggs", vocabulary: vocab) == nil, "Exact match nil")
    check(suggestCorrection("eggs", vocabulary: vocab) == nil, "Case-insensitive exact nil")

    // Single-char edits
    checkEqual(suggestCorrection("Milz", vocabulary: vocab) ?? "", "Milk", "Substitution")
    checkEqual(suggestCorrection("Egs", vocabulary: ["Eggs"]) ?? "", "Eggs", "Deletion")

    // Too far
    check(suggestCorrection("ABCDE", vocabulary: vocab) == nil, "Completely different nil")

    // Empty vocabulary
    check(suggestCorrection("Milk", vocabulary: []) == nil, "Empty vocab nil")
}

func testEditDistance() {
    checkEqual(editDistance("kitten", "sitting"), 3, "kitten->sitting")
    checkEqual(editDistance("", "abc"), 3, "empty->abc")
    checkEqual(editDistance("abc", "abc"), 0, "identical")
}

func testGroceryVocabulary() {
    let vocab = groceryVocabulary()
    check(vocab.count > 50, "Vocab has substantial entries")
    checkEqual(suggestCorrection("Millk", vocabulary: vocab) ?? "", "milk", "Millk -> milk")
}

func runFuzzyMatcherTests() -> Bool {
    print("\n=== FuzzyMatcher Tests ===")

    testFuzzyMatching()
    testEditDistance()
    testGroceryVocabulary()

    return printTestSummary("FuzzyMatcher Tests")
}
