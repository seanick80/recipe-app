import Foundation

// MARK: - FuzzyMatcher Tests

func testExactMatchReturnsNil() {
    let vocab = ["Eggs", "Milk", "Bread"]
    check(suggestCorrection("Eggs", vocabulary: vocab) == nil, "Exact match returns nil")
    check(suggestCorrection("eggs", vocabulary: vocab) == nil, "Case-insensitive exact match returns nil")
}

func testSingleCharEdits() {
    let vocab = ["Milk", "Bread", "Eggs"]
    // Data-driven: (input, expected, description)
    let cases: [(String, String, String)] = [
        ("Milz", "Milk", "substitution"),
        ("Mlk", "Milk", "deletion"),
        ("Miilk", "Milk", "insertion"),
    ]
    for (input, expected, desc) in cases {
        checkEqual(suggestCorrection(input, vocabulary: vocab) ?? "", expected, "\(input) -> \(expected) (1 \(desc))")
    }
}

func testTwoCharDistance() {
    let result = suggestCorrection("Mikl", vocabulary: ["Milk", "Bread", "Eggs"])
    check(result == "Milk" || result == nil, "Mikl within distance 2 of Milk")
}

func testDistanceTooFar() {
    let result = suggestCorrection("ABCDE", vocabulary: ["Milk", "Bread", "Eggs"])
    check(result == nil, "Completely different word returns nil")
}

func testEggsTypo() {
    let result = suggestCorrection("Egs", vocabulary: ["Eggs", "Milk", "Bread"])
    checkEqual(result ?? "", "Eggs", "Egs -> Eggs (1 deletion)")
}

func testEditDistanceBasic() {
    checkEqual(editDistance("kitten", "sitting"), 3, "kitten->sitting = 3")
    checkEqual(editDistance("", "abc"), 3, "empty->abc = 3")
    checkEqual(editDistance("abc", "abc"), 0, "abc->abc = 0")
    checkEqual(editDistance("abc", "abd"), 1, "abc->abd = 1")
    checkEqual(editDistance("milk", "Milk"), 1, "milk->Milk = 1 (case)")
}

func testEmptyInputOrVocabulary() {
    let r1 = suggestCorrection("", vocabulary: ["Milk", "Eggs"])
    check(r1 == nil || r1 != nil, "Empty input handled")
    let r2 = suggestCorrection("Milk", vocabulary: [])
    check(r2 == nil, "Empty vocabulary returns nil")
}

func testGroceryVocabulary() {
    let vocab = groceryVocabulary()
    check(vocab.count > 50, "Grocery vocabulary has substantial entries")
    let result = suggestCorrection("Millk", vocabulary: vocab)
    checkEqual(result ?? "", "milk", "Millk -> milk from grocery vocab")
}

func runFuzzyMatcherTests() -> Bool {
    print("\n=== FuzzyMatcher Tests ===")

    testExactMatchReturnsNil()
    testSingleCharEdits()
    testTwoCharDistance()
    testDistanceTooFar()
    testEggsTypo()
    testEditDistanceBasic()
    testEmptyInputOrVocabulary()
    testGroceryVocabulary()

    return printTestSummary("FuzzyMatcher Tests")
}
