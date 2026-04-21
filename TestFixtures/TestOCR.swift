import Foundation

// MARK: - OCR Recipe Parser Tests

func testParseFullRecipe() {
    let text = """
        Spaghetti Bolognese
        Serves 4
        Prep time: 15 min
        Cook time: 45 min

        Ingredients
        - 1 lb ground beef
        - 2 cans tomatoes
        - 1 box pasta
        - 3 cloves garlic

        Instructions
        1. Brown the ground beef in a large pan
        2. Add garlic and cook for 1 minute
        3. Add tomatoes and simmer for 30 minutes
        4. Cook pasta according to package directions
        """
    let recipe = parseRecipeText(text)
    checkEqual(recipe.title, "Spaghetti Bolognese", "Full recipe title")
    checkEqual(recipe.servings, 4, "Full recipe servings")
    checkEqual(recipe.prepTimeMinutes, 15, "Full recipe prep time")
    checkEqual(recipe.ingredients.count, 4, "Full recipe ingredients")
    checkEqual(recipe.ingredients[0].unit, "lb", "First ingredient unit")
    checkEqual(recipe.instructions.count, 4, "Full recipe instructions")
}

func testParseVariants() {
    // Servings
    checkEqual(parseServings("serves 4"), 4, "serves N")
    checkEqual(parseServings("yield: 8"), 8, "yield: N")
    check(parseServings("something else") == nil, "Non-servings nil")

    // Time
    checkEqual(parseTimeString("20 min"), 20, "N min")
    checkEqual(parseTimeString("1h 30m"), 90, "1h 30m")

    // Ingredient line
    let ing = parseIngredientLine("2 cups flour")!
    checkEqual(ing.name, "flour", "Ingredient name")
    checkEqual(ing.unit, "cup", "Ingredient unit")

    // Instruction cleaning
    checkEqual(cleanInstructionLine("1. Preheat oven"), "Preheat oven", "Number prefix removed")
    checkEqual(cleanInstructionLine("Step 2: Mix"), "Mix", "Step prefix removed")
}

func testParseEdgeCases() {
    // Empty
    let empty = parseRecipeText("")
    checkEqual(empty.ingredients.count, 0, "Empty: no ingredients")

    // Alternate headers
    let text = "Quick Salad\nWhat you need\n- lettuce\n- tomato\nMethod\nChop vegetables"
    let recipe = parseRecipeText(text)
    checkEqual(recipe.title, "Quick Salad", "Alternate headers: title")
    checkEqual(recipe.ingredients.count, 2, "Alternate headers: ingredients")
    checkEqual(recipe.instructions.count, 1, "Alternate headers: instructions")
}

func testParsedRecipeCodable() {
    let recipe = ParsedRecipe(
        title: "Test",
        ingredients: [ParsedIngredient(name: "flour", quantity: 2, unit: "cup")],
        instructions: ["Mix well"],
        servings: 4,
        prepTimeMinutes: 10,
        cookTimeMinutes: 20
    )
    checkCodableRoundTrip(recipe, "ParsedRecipe Codable")
}

// MARK: - Test Runner

func runOCRTests() -> Bool {
    print("\n=== OCR Recipe Parser Tests ===")

    testParseFullRecipe()
    testParseVariants()
    testParseEdgeCases()
    testParsedRecipeCodable()

    return printTestSummary("OCR Parser Tests")
}
