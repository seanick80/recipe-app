import Foundation

// MARK: - OCR Recipe Parser Tests

func testParseBasicRecipe() {
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
    checkEqual(recipe.title, "Spaghetti Bolognese", "Basic recipe title")
    checkEqual(recipe.servings, 4, "Basic recipe servings")
    checkEqual(recipe.prepTimeMinutes, 15, "Basic recipe prep time")
    checkEqual(recipe.cookTimeMinutes, 45, "Basic recipe cook time")
    checkEqual(recipe.ingredients.count, 4, "Basic recipe ingredient count")
    checkEqual(recipe.ingredients[0].name, "ground beef", "First ingredient name")
    checkEqual(recipe.ingredients[0].quantity, 1, "First ingredient quantity")
    checkEqual(recipe.ingredients[0].unit, "lb", "First ingredient unit")
    checkEqual(recipe.instructions.count, 4, "Basic recipe instruction count")
}

func testParseRecipeTitle() {
    let text = """
        Grandma's Chicken Soup:
        Ingredients
        - 1 chicken
        """
    let recipe = parseRecipeText(text)
    checkEqual(recipe.title, "Grandma's Chicken Soup", "Title trailing colon stripped")
}

func testParseServingsVariants() {
    checkEqual(parseServings("serves 4"), 4, "serves N")
    checkEqual(parseServings("servings: 6"), 6, "servings: N")
    checkEqual(parseServings("yield: 8"), 8, "yield: N")
    checkEqual(parseServings("makes 12"), 12, "makes N")
    check(parseServings("something else") == nil, "Non-servings returns nil")
}

func testParseTimeVariants() {
    checkEqual(parseTimeString("20 min"), 20, "N min")
    checkEqual(parseTimeString("1 hour"), 60, "1 hour")
    checkEqual(parseTimeString("1h 30m"), 90, "1h 30m")
    checkEqual(parseTimeString("90 minutes"), 90, "90 minutes")
    checkEqual(parseTimeString("2 hours"), 120, "2 hours")
    checkEqual(parseTimeString("45"), 45, "bare number = minutes")
}

func testParseIngredientLine() {
    let i1 = parseIngredientLine("2 cups flour")
    check(i1 != nil, "Ingredient with unit parses")
    checkEqual(i1!.name, "flour", "Ingredient name")
    checkEqual(i1!.quantity, 2, "Ingredient quantity")
    checkEqual(i1!.unit, "cup", "Ingredient unit")

    let i2 = parseIngredientLine("• 1/2 tsp salt")
    check(i2 != nil, "Bullet ingredient parses")
    checkEqual(i2!.name, "salt", "Bullet ingredient name")
    checkEqual(i2!.quantity, 0.5, "Bullet ingredient fraction")
    checkEqual(i2!.unit, "tsp", "Bullet ingredient unit")

    let i3 = parseIngredientLine("salt and pepper to taste")
    check(i3 != nil, "Plain ingredient parses")
    checkEqual(i3!.name, "salt and pepper to taste", "Plain ingredient name")
}

func testCleanInstructionLine() {
    checkEqual(cleanInstructionLine("1. Preheat oven"), "Preheat oven", "Numbered prefix removed")
    checkEqual(cleanInstructionLine("Step 2: Mix ingredients"), "Mix ingredients", "Step prefix removed")
    checkEqual(cleanInstructionLine("3) Add salt"), "Add salt", "Paren numbered prefix removed")
    checkEqual(cleanInstructionLine("Mix well"), "Mix well", "No prefix unchanged")
}

func testParseEmptyRecipe() {
    let recipe = parseRecipeText("")
    checkEqual(recipe.title, "", "Empty text: no title")
    checkEqual(recipe.ingredients.count, 0, "Empty text: no ingredients")
    checkEqual(recipe.instructions.count, 0, "Empty text: no instructions")
}

func testParseRecipeWithAlternateHeaders() {
    let text = """
        Quick Salad
        What you need
        - lettuce
        - tomato
        - cucumber
        Method
        Chop all vegetables and toss together
        """
    let recipe = parseRecipeText(text)
    checkEqual(recipe.title, "Quick Salad", "Alternate header: title")
    checkEqual(recipe.ingredients.count, 3, "Alternate header: ingredient count")
    checkEqual(recipe.instructions.count, 1, "Alternate header: instruction count")
}

func testParseRecipeNoHeaders() {
    let text = """
        Chicken Stir Fry
        2 chicken breasts
        1 tbsp soy sauce
        3 cloves garlic
        1 cup broccoli
        """
    let recipe = parseRecipeText(text)
    checkEqual(recipe.title, "Chicken Stir Fry", "No-header recipe: title")
    check(recipe.ingredients.count >= 3, "No-header recipe: at least 3 ingredients (got \(recipe.ingredients.count))")
    check(
        recipe.ingredients.contains { $0.name.lowercased().contains("chicken") },
        "No-header recipe: found chicken ingredient"
    )
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
    checkCodableRoundTrip(recipe, "ParsedRecipe Codable round-trip")
}

// MARK: - Test Runner

func runOCRTests() -> Bool {
    print("\n=== OCR Recipe Parser Tests ===")

    testParseBasicRecipe()
    testParseRecipeTitle()
    testParseServingsVariants()
    testParseTimeVariants()
    testParseIngredientLine()
    testCleanInstructionLine()
    testParseEmptyRecipe()
    testParseRecipeWithAlternateHeaders()
    testParseRecipeNoHeaders()
    testParsedRecipeCodable()

    return printTestSummary("OCR Parser Tests")
}
