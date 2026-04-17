import Foundation

// MARK: - ContentDetector Tests

func testDetectRecipeVariants() {
    // Data-driven: 4 recipe text samples that should all detect as .recipe
    let recipeSamples: [(String, String)] = [
        (
            """
            Chocolate Cake
            Ingredients
            2 cups flour
            1 cup sugar
            Instructions
            Preheat oven to 350 degrees
            Mix dry ingredients
            """, "Recipe with headers"
        ),
        (
            """
            Pasta Bake
            Preheat oven to 375
            Cook for 30 minutes
            Serves 4
            """, "Recipe with cooking verbs"
        ),
        (
            """
            Banana Bread
            Ingredients
            3 bananas
            Step 1 Mash bananas
            Step 2 Mix with flour
            """, "Recipe with step numbers"
        ),
        (
            """
            Quick Soup
            Prep time 10 minutes
            Cook time 20 minutes
            Ingredients
            2 cans tomatoes
            """, "Recipe with times"
        ),
    ]
    for (text, desc) in recipeSamples {
        checkEqual(detectContentType(text), .recipe, desc)
    }
}

func testDetectShoppingList() {
    let text = """
        Shopping List
        Milk
        Eggs
        Bread
        """
    let result = detectContentType(text)
    checkEqual(result, .shoppingList, "Shopping list with header")
}

func testDetectUnknown() {
    checkEqual(detectContentType(""), .unknown, "Empty text is unknown")
    checkEqual(detectContentType("Milk"), .unknown, "Single word is unknown")
}

func testShoppingListOverridesWeakRecipe() {
    let text = """
        Grocery List
        Milk
        Eggs
        Serves as breakfast staple
        """
    let result = detectContentType(text)
    check(result != .recipe, "Shopping marker overrides weak recipe signal")
}

func runContentDetectorTests() -> Bool {
    print("\n=== ContentDetector Tests ===")

    testDetectRecipeVariants()
    testDetectShoppingList()
    testDetectUnknown()
    testShoppingListOverridesWeakRecipe()

    return printTestSummary("ContentDetector Tests")
}
