import Foundation

// MARK: - Grocery Categorizer Tests

func testCategorizeBasicItems() {
    // One representative item per category (10 categories)
    let cases: [(String, String)] = [
        ("apple", "Produce"),
        ("milk", "Dairy"),
        ("chicken", "Meat"),
        ("bread", "Bakery"),
        ("rice", "Dry & Canned"),
        ("coffee", "Beverages"),
        ("chips", "Snacks"),
        ("ketchup", "Condiments"),
        ("cumin", "Spices"),
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

func testSpicesCategory() {
    let cases: [(String, String)] = [
        ("cumin", "Spices"),
        ("paprika", "Spices"),
        ("turmeric", "Spices"),
        ("cinnamon", "Spices"),
        ("nutmeg", "Spices"),
        ("cardamom", "Spices"),
        ("cayenne", "Spices"),
        ("curry", "Spices"),
        ("saffron", "Spices"),
        ("sumac", "Spices"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testSpicesMultiWord() {
    let cases: [(String, String)] = [
        ("garam masala", "Spices"),
        ("chili powder", "Spices"),
        ("garlic powder", "Spices"),
        ("onion powder", "Spices"),
        ("curry powder", "Spices"),
        ("ground cumin", "Spices"),
        ("italian seasoning", "Spices"),
        ("bay leaf", "Spices"),
        ("vanilla extract", "Spices"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testCategoryPriority() {
    // When multiple tokens match different categories, food categories
    // (Produce, Meat) should outrank Spices/Condiments
    let cases: [(String, String, String)] = [
        ("cloves garlic minced", "Produce", "garlic outranks clove"),
        ("fresh ginger", "Produce", "ginger is Produce"),
        ("fresh parsley", "Produce", "parsley multi-word match"),
        ("chicken thighs", "Meat", "chicken multi-word match"),
    ]
    for (item, expected, note) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected) (\(note))")
    }
}

func testBuild67ScreenshotItems() {
    // Regression tests from build 67 screenshot failures (GM-16)
    let cases: [(String, String)] = [
        ("16-Oz (450G) Tomato Sauce", "Dry & Canned"),
        ("Chicken Thighs", "Meat"),
        ("Fresh Ginger", "Produce"),
        ("Fresh Parsley, Mint, Or Cilantro", "Produce"),
        ("Garam Masala", "Spices"),
        ("Ground Cumin", "Spices"),
        ("Chili Powder", "Spices"),
        ("Cloves Garlic Minced", "Produce"),
        ("Granulated Sugar Or Honey", "Dry & Canned"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "build67: \(item) -> \(expected)")
    }
}

func testCompoundOverrideNotTooAggressive() {
    // "powder" was removed from blanket overrides — verify specific items
    // still categorize correctly
    let cases: [(String, String, String)] = [
        ("baking powder", "Dry & Canned", "specific multi-word match"),
        ("baking soda", "Dry & Canned", "specific multi-word match"),
        ("flour", "Dry & Canned", "exact word match"),
        ("all purpose flour", "Dry & Canned", "specific multi-word match"),
        ("cornstarch", "Dry & Canned", "exact word match"),
    ]
    for (item, expected, note) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected) (\(note))")
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
    testSpicesCategory()
    testSpicesMultiWord()
    testCategoryPriority()
    testBuild67ScreenshotItems()
    testCompoundOverrideNotTooAggressive()
    testEdgeCases()

    return printTestSummary("Grocery Categorizer Tests")
}
