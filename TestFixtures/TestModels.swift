import Foundation

// MARK: - Recipe Model Tests

func testRecipeModel() {
    let recipe = makeRecipe(
        name: "Tikka Masala",
        prepTime: 10,
        cookTime: 20,
        servings: 4,
        cuisine: "Indian",
        course: "Dinner",
        tags: "spicy",
        sourceURL: "https://example.com",
        difficulty: "Medium",
        isFavorite: true,
        ingredientCount: 3
    )
    checkEqual(recipe.name, "Tikka Masala", "Recipe name")
    checkEqual(recipe.totalTimeMinutes, 30, "Total time")
    checkEqual(recipe.cuisine, "Indian", "Cuisine")
    check(recipe.isFavorite, "Favorite flag")
    checkEqual(recipe.ingredients.count, 3, "Ingredient count")
    checkEqual(recipe.ingredients[0].displayOrder, 0, "Display order")
}

func testGroceryModels() {
    var item = makeGroceryItem(name: "Milk")
    check(!item.isChecked, "Initially unchecked")
    item.isChecked = true
    check(item.isChecked, "Checked after toggle")

    // Traceability
    let traced = GroceryItemModel(
        name: "Chicken",
        quantity: 2,
        unit: "lb",
        category: "Meat",
        sourceRecipeName: "Tikka",
        sourceRecipeId: "abc-123"
    )
    checkEqual(traced.sourceRecipeName, "Tikka", "Source recipe name")

    // List completed count
    let list = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A", isChecked: true),
            makeGroceryItem(name: "B", isChecked: false),
            makeGroceryItem(name: "C", isChecked: true),
        ]
    )
    checkEqual(list.completedCount, 2, "Completed count")
}

func testModelCodable() {
    checkCodableRoundTrip(
        makeRecipe(name: "Test", cuisine: "Italian", isFavorite: true),
        "Recipe Codable"
    )
    checkCodableRoundTrip(
        IngredientModel(name: "flour", quantity: 2, unit: "cup", displayOrder: 3, notes: "sifted"),
        "Ingredient Codable"
    )
    checkCodableRoundTrip(
        GroceryItemModel(
            name: "Chicken",
            quantity: 2,
            unit: "lb",
            category: "Meat",
            sourceRecipeName: "Tikka",
            sourceRecipeId: "uuid"
        ),
        "GroceryItem Codable"
    )
}

func runRecipeTests() -> Bool {
    print("\n=== Recipe Model Tests ===")

    testRecipeModel()
    testGroceryModels()
    testModelCodable()

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
