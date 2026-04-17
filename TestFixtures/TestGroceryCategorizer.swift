import Foundation

// MARK: - Grocery Categorizer Tests

func testCategorizeBasicItems() {
    // One representative item per category (9 categories)
    let cases: [(String, String)] = [
        ("apple", "Produce"),
        ("milk", "Dairy"),
        ("chicken", "Meat"),
        ("bread", "Bakery"),
        ("rice", "Dry & Canned"),
        ("coffee", "Beverages"),
        ("chips", "Snacks"),
        ("ketchup", "Condiments"),
        ("soap", "Household"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testCompoundOverrides() {
    // Priority logic: compound phrases override single-word category
    let cases: [(String, String, String)] = [
        ("turkey broth", "Dry & Canned", "not Meat"),
        ("chicken stock", "Dry & Canned", "not Meat"),
        ("chicken broth", "Dry & Canned", "not Meat"),
        ("beef stock", "Dry & Canned", "not Meat"),
        ("vegetable broth", "Dry & Canned", "compound"),
        ("bone broth", "Dry & Canned", "compound"),
        ("chicken soup", "Dry & Canned", "not Meat"),
        ("onion soup mix", "Dry & Canned", "not Produce"),
        ("cake mix", "Dry & Canned", "not Bakery"),
        ("pancake mix", "Dry & Canned", "compound"),
    ]
    for (item, expected, note) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected) (\(note))")
    }
}

func testMultiWordPhrases() {
    let cases: [(String, String)] = [
        ("bell pepper", "Produce"),
        ("cream cheese", "Dairy"),
        ("ground beef", "Meat"),
        ("peanut butter", "Dry & Canned"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testPluralsAndPreviouslyMissed() {
    let cases: [(String, String)] = [
        ("berries", "Produce"),
        ("potatoes", "Produce"),
        ("ginger", "Produce"),
        ("mozzarella", "Dairy"),
        ("lamb", "Meat"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testEdgeCases() {
    checkEqual(categorizeGroceryItem("ice cream"), "Frozen", "ice cream -> Frozen")
    checkEqual(categorizeGroceryItem("  Milk  "), "Dairy", "whitespace trimmed")
    checkEqual(categorizeGroceryItem("CHICKEN"), "Meat", "all caps")
    checkEqual(categorizeGroceryItem(""), "Other", "empty string -> Other")
}

// MARK: - Test Runner

func runGroceryCategorizerTests() -> Bool {
    print("\n=== Grocery Categorizer Tests ===")

    testCategorizeBasicItems()
    testCompoundOverrides()
    testMultiWordPhrases()
    testPluralsAndPreviouslyMissed()
    testEdgeCases()

    return printTestSummary("Grocery Categorizer Tests")
}
