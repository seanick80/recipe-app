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

func testGroceryItem() {
    var item = makeGroceryItem(name: "Milk", quantity: 1, unit: "gallon", category: "Dairy")
    check(!item.isChecked, "Initially unchecked")
    item.isChecked = true
    check(item.isChecked, "Checked after toggle")
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
    let recipe = makeRecipe(name: "Test", prepTime: 5)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(recipe)
        let decoded = try decoder.decode(RecipeModel.self, from: data)
        checkEqual(decoded.name, recipe.name, "Codable round-trip name")
        checkEqual(decoded.prepTimeMinutes, recipe.prepTimeMinutes, "Codable round-trip prep time")
    } catch {
        print("FAIL: Codable encoding/decoding - \(error)")
        testFailCount += 1
    }
}

func runRecipeTests() -> Bool {
    print("\n=== Recipe Model Tests ===")

    testRecipeCreation()
    testRecipeWithIngredients()
    testGroceryItem()
    testGroceryList()
    testRecipeCodable()

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

        print("\n=== Done ===")
        if !allPassed {
            print("SOME TESTS FAILED")
            exit(1)
        }
    }
}
