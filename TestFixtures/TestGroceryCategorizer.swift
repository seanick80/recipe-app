import Foundation

// MARK: - Grocery Categorizer Tests

func testCategorizeAllCategories() {
    // One representative per category (10 categories)
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
        ("ice cream", "Frozen"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testCompoundOverrides() {
    // Compound phrases override single-word category
    let cases: [(String, String)] = [
        ("chicken broth", "Dry & Canned"),
        ("onion soup mix", "Dry & Canned"),
        ("cake mix", "Dry & Canned"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testMultiWordAndSpices() {
    let cases: [(String, String)] = [
        ("bell pepper", "Produce"),
        ("cream cheese", "Dairy"),
        ("ground beef", "Meat"),
        ("peanut butter", "Dry & Canned"),
        ("garam masala", "Spices"),
        ("chili powder", "Spices"),
        ("vanilla extract", "Spices"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testCategoryPriority() {
    // Food categories outrank Spices/Condiments
    checkEqual(categorizeGroceryItem("cloves garlic minced"), "Produce", "garlic outranks clove")
    checkEqual(categorizeGroceryItem("chicken thighs"), "Meat", "chicken multi-word match")
}

func testBakingAndDryCanned() {
    let cases: [(String, String)] = [
        ("baking powder", "Dry & Canned"),
        ("flour", "Dry & Canned"),
        ("cornstarch", "Dry & Canned"),
        ("Granulated Sugar Or Honey", "Dry & Canned"),
    ]
    for (item, expected) in cases {
        checkEqual(categorizeGroceryItem(item), expected, "\(item) -> \(expected)")
    }
}

func testEdgeCases() {
    checkEqual(categorizeGroceryItem("  Milk  "), "Dairy", "whitespace trimmed")
    checkEqual(categorizeGroceryItem("CHICKEN"), "Meat", "all caps")
    checkEqual(categorizeGroceryItem(""), "Other", "empty -> Other")
    checkEqual(categorizeGroceryItem("16-Oz (450G) Tomato Sauce"), "Dry & Canned", "build67 regression")
}

// MARK: - Test Runner

func runGroceryCategorizerTests() -> Bool {
    print("\n=== Grocery Categorizer Tests ===")

    testCategorizeAllCategories()
    testCompoundOverrides()
    testMultiWordAndSpices()
    testCategoryPriority()
    testBakingAndDryCanned()
    testEdgeCases()

    return printTestSummary("Grocery Categorizer Tests")
}
