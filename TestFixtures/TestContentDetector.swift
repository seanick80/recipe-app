import Foundation

// MARK: - ContentDetector Tests

func testDetectContentTypes() {
    // Recipe with headers
    let recipe = """
        Chocolate Cake
        Ingredients
        2 cups flour
        Instructions
        Preheat oven to 350
        """
    checkEqual(detectContentType(recipe), .recipe, "Recipe with headers")

    // Shopping list
    let shopping = "Shopping List\nMilk\nEggs\nBread"
    checkEqual(detectContentType(shopping), .shoppingList, "Shopping list")

    // Unknown
    checkEqual(detectContentType(""), .unknown, "Empty is unknown")

    // Shopping marker overrides weak recipe
    let ambiguous = "Grocery List\nMilk\nEggs\nServes as breakfast staple"
    check(detectContentType(ambiguous) != .recipe, "Shopping marker overrides recipe")
}

func runContentDetectorTests() -> Bool {
    print("\n=== ContentDetector Tests ===")

    testDetectContentTypes()

    return printTestSummary("ContentDetector Tests")
}
