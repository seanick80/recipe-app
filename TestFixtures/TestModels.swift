import Foundation

// MARK: - Recipe Model Tests

func testRecipeCreation() {
    let recipe = makeRecipe(name: "Test Pasta", prepTime: 10, cookTime: 20, servings: 4)
    checkEqual(recipe.name, "Test Pasta", "Recipe name")
    checkEqual(recipe.totalTimeMinutes, 30, "Total time calculation")
    checkEqual(recipe.servings, 4, "Servings")
    check(recipe.ingredients.isEmpty, "Empty ingredients")
}

func testRecipeWithIngredients() {
    let recipe = makeRecipe(name: "Spaghetti", ingredientCount: 2)
    checkEqual(recipe.ingredients.count, 2, "Ingredient count")
    checkEqual(recipe.ingredients[0].name, "Ingredient 1", "First ingredient name")
}

func testRecipeNewFields() {
    let recipe = makeRecipe(
        name: "Tikka Masala",
        cuisine: "Indian",
        course: "Dinner",
        tags: "spicy, weeknight",
        sourceURL: "https://example.com/tikka",
        difficulty: "Medium",
        isFavorite: true
    )
    checkEqual(recipe.cuisine, "Indian", "Recipe cuisine")
    checkEqual(recipe.course, "Dinner", "Recipe course")
    checkEqual(recipe.tags, "spicy, weeknight", "Recipe tags")
    checkEqual(recipe.sourceURL, "https://example.com/tikka", "Recipe source URL")
    checkEqual(recipe.difficulty, "Medium", "Recipe difficulty")
    check(recipe.isFavorite, "Recipe is favorite")
}

func testIngredientDisplayOrder() {
    let recipe = makeRecipe(name: "Ordered", ingredientCount: 3)
    checkEqual(recipe.ingredients[0].displayOrder, 0, "First ingredient order 0")
    checkEqual(recipe.ingredients[1].displayOrder, 1, "Second ingredient order 1")
    checkEqual(recipe.ingredients[2].displayOrder, 2, "Third ingredient order 2")
}

func testIngredientNotes() {
    let ingredient = IngredientModel(
        name: "chicken breast",
        quantity: 1,
        unit: "lb",
        notes: "pounded thin"
    )
    checkEqual(ingredient.notes, "pounded thin", "Ingredient notes")
    checkEqual(ingredient.name, "chicken breast", "Ingredient name stays clean")
}

func testGroceryItem() {
    var item = makeGroceryItem(name: "Milk", quantity: 1, unit: "gallon", category: "Dairy")
    check(!item.isChecked, "Initially unchecked")
    item.isChecked = true
    check(item.isChecked, "Checked after toggle")
}

func testGroceryItemTraceability() {
    let item = GroceryItemModel(
        name: "Chicken",
        quantity: 2,
        unit: "lb",
        category: "Meat",
        sourceRecipeName: "Tikka Masala",
        sourceRecipeId: "abc-123"
    )
    checkEqual(item.sourceRecipeName, "Tikka Masala", "Source recipe name")
    checkEqual(item.sourceRecipeId, "abc-123", "Source recipe ID")
}

func testGroceryList() {
    let list = GroceryListModel(
        name: "Weekly",
        items: [
            makeGroceryItem(name: "Milk", isChecked: true),
            makeGroceryItem(name: "Eggs", isChecked: false),
            makeGroceryItem(name: "Bread", isChecked: true),
        ]
    )
    checkEqual(list.completedCount, 2, "Completed count")
    checkEqual(list.items.count, 3, "Total items")
}

func testRecipeCodable() {
    let recipe = makeRecipe(
        name: "Test",
        prepTime: 5,
        cuisine: "Italian",
        course: "Dinner",
        tags: "quick",
        sourceURL: "https://example.com",
        difficulty: "Easy",
        isFavorite: true
    )
    checkCodableRoundTrip(recipe, "Recipe Codable round-trip with all fields")
}

func testIngredientCodable() {
    let ingredient = IngredientModel(
        name: "flour",
        quantity: 2,
        unit: "cup",
        displayOrder: 3,
        notes: "sifted"
    )
    checkCodableRoundTrip(ingredient, "Ingredient Codable round-trip with notes + displayOrder")
}

func testGroceryItemCodable() {
    let item = GroceryItemModel(
        name: "Chicken",
        quantity: 2,
        unit: "lb",
        category: "Meat",
        sourceRecipeName: "Tikka",
        sourceRecipeId: "uuid-here"
    )
    checkCodableRoundTrip(item, "GroceryItem Codable round-trip with traceability")
}

func runRecipeTests() -> Bool {
    print("\n=== Recipe Model Tests ===")

    testRecipeCreation()
    testRecipeWithIngredients()
    testRecipeNewFields()
    testIngredientDisplayOrder()
    testIngredientNotes()
    testGroceryItem()
    testGroceryItemTraceability()
    testGroceryList()
    testRecipeCodable()
    testIngredientCodable()
    testGroceryItemCodable()

    return printTestSummary("Recipe Tests")
}

// MARK: - Main Entry Point

@main
struct TestRunner {
    static func main() {
        print("=== Recipe App Model Tests ===")

        var allPassed = true
        allPassed = runRecipeTests() && allPassed
        allPassed = runShoppingTests() && allPassed
        allPassed = runListParserTests() && allPassed
        allPassed = runOCRTests() && allPassed
        allPassed = runDetectionTests() && allPassed
        allPassed = runBarcodeTests() && allPassed
        allPassed = runPantryTests() && allPassed
        allPassed = runGroceryCategorizerTests() && allPassed
        allPassed = runZoneClassifierTests() && allPassed
        allPassed = runQualityGateTests() && allPassed
        allPassed = runDebugLogTests() && allPassed
        allPassed = runPrepNoteStripperTests() && allPassed
        allPassed = runContentDetectorTests() && allPassed
        allPassed = runFuzzyMatcherTests() && allPassed
        allPassed = runRecipeSchemaParserTests() && allPassed

        print("\n=== Done ===")
        if !allPassed {
            print("SOME TESTS FAILED")
            exit(1)
        }
    }
}
