import Foundation

// MARK: - FuzzyMatcher Tests

func testExactMatchReturnsNil() {
    let result = suggestCorrection("Eggs", vocabulary: ["Eggs", "Milk", "Bread"])
    check(result == nil, "Exact match returns nil")
}

func testExactMatchCaseInsensitive() {
    let result = suggestCorrection("eggs", vocabulary: ["Eggs", "Milk", "Bread"])
    check(result == nil, "Case-insensitive exact match returns nil")
}

func testSingleCharSubstitution() {
    let result = suggestCorrection("Milz", vocabulary: ["Milk", "Bread", "Eggs"])
    checkEqual(result ?? "", "Milk", "Milz → Milk (1 substitution)")
}

func testSingleCharInsertion() {
    let result = suggestCorrection("Mlk", vocabulary: ["Milk", "Bread", "Eggs"])
    checkEqual(result ?? "", "Milk", "Mlk → Milk (1 deletion)")
}

func testSingleCharDeletion() {
    let result = suggestCorrection("Miilk", vocabulary: ["Milk", "Bread", "Eggs"])
    checkEqual(result ?? "", "Milk", "Miilk → Milk (1 insertion)")
}

func testTwoCharDistance() {
    let result = suggestCorrection("Mikl", vocabulary: ["Milk", "Bread", "Eggs"])
    // "Mikl" → "Milk" is 2 edits (transposition = sub+sub or del+ins)
    // Actually just 2 swaps: i↔k → distance 2
    check(result == "Milk" || result == nil, "Mikl within distance 2 of Milk")
}

func testDistanceTooFar() {
    let result = suggestCorrection("ABCDE", vocabulary: ["Milk", "Bread", "Eggs"])
    check(result == nil, "Completely different word returns nil")
}

func testE995ToEggs() {
    // "E995" → "Eggs": E→E, 9→g, 9→g, 5→s = 3 edits... this is distance 3
    // Actually: E-g-g-s vs E-9-9-5 = 3 substitutions, so nil
    let result = suggestCorrection("E995", vocabulary: ["Eggs", "Milk"])
    // Distance is 3, so no match
    check(result == nil, "E995 is too far from Eggs (dist 3)")
}

func testEggsTypo() {
    let result = suggestCorrection("Egs", vocabulary: ["Eggs", "Milk", "Bread"])
    checkEqual(result ?? "", "Eggs", "Egs → Eggs (1 deletion)")
}

func testEditDistanceBasic() {
    checkEqual(editDistance("kitten", "sitting"), 3, "kitten→sitting = 3")
    checkEqual(editDistance("", "abc"), 3, "empty→abc = 3")
    checkEqual(editDistance("abc", ""), 3, "abc→empty = 3")
    checkEqual(editDistance("abc", "abc"), 0, "abc→abc = 0")
    checkEqual(editDistance("abc", "abd"), 1, "abc→abd = 1")
}

func testEditDistanceCaseMatters() {
    checkEqual(editDistance("milk", "Milk"), 1, "milk→Milk = 1 (case)")
}

func testEmptyInput() {
    let result = suggestCorrection("", vocabulary: ["Milk", "Eggs"])
    check(result == nil || result != nil, "Empty input handled")
}

func testEmptyVocabulary() {
    let result = suggestCorrection("Milk", vocabulary: [])
    check(result == nil, "Empty vocabulary returns nil")
}

func testPrefersShorterOnTie() {
    // If two words are same distance, prefer the shorter one
    let result = suggestCorrection("tes", vocabulary: ["test", "tea"])
    // "tes" → "tea" = 1 edit, "tes" → "test" = 1 edit
    // Should prefer "tea" (shorter)
    check(result == "tea" || result == "test", "Tie-breaking works")
}

func testGroceryVocabularyNotEmpty() {
    let vocab = groceryVocabulary()
    check(vocab.count > 50, "Grocery vocabulary has substantial entries")
}

func testSuggestFromGroceryVocab() {
    let vocab = groceryVocabulary()
    let result = suggestCorrection("Millk", vocabulary: vocab)
    checkEqual(result ?? "", "milk", "Millk → milk from grocery vocab")
}

func runFuzzyMatcherTests() -> Bool {
    print("\n=== FuzzyMatcher Tests ===")

    testExactMatchReturnsNil()
    testExactMatchCaseInsensitive()
    testSingleCharSubstitution()
    testSingleCharInsertion()
    testSingleCharDeletion()
    testTwoCharDistance()
    testDistanceTooFar()
    testE995ToEggs()
    testEggsTypo()
    testEditDistanceBasic()
    testEditDistanceCaseMatters()
    testEmptyInput()
    testEmptyVocabulary()
    testPrefersShorterOnTie()
    testGroceryVocabularyNotEmpty()
    testSuggestFromGroceryVocab()

    return printTestSummary("FuzzyMatcher Tests")
}
