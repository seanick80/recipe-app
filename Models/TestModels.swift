import Foundation

func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
    } else {
        print("PASS: \(message)")
    }
}

func testRecipeCreation() {
    let recipe = RecipeModel(name: "Test Pasta", prepTimeMinutes: 10, cookTimeMinutes: 20, servings: 4)
    check(recipe.name == "Test Pasta", "Recipe name")
    check(recipe.totalTimeMinutes == 30, "Total time calculation")
    check(recipe.servings == 4, "Servings")
    check(recipe.ingredients.isEmpty, "Empty ingredients")
}

func testRecipeWithIngredients() {
    let ingredients = [
        IngredientModel(name: "Pasta", quantity: 1, unit: "lb"),
        IngredientModel(name: "Tomato Sauce", quantity: 2, unit: "cups"),
    ]
    let recipe = RecipeModel(name: "Spaghetti", ingredients: ingredients)
    check(recipe.ingredients.count == 2, "Ingredient count")
    check(recipe.ingredients[0].name == "Pasta", "First ingredient name")
}

func testGroceryItem() {
    var item = GroceryItemModel(name: "Milk", quantity: 1, unit: "gallon", category: "Dairy")
    check(!item.isChecked, "Initially unchecked")
    item.isChecked = true
    check(item.isChecked, "Checked after toggle")
}

func testGroceryList() {
    let items = [
        GroceryItemModel(name: "Milk", isChecked: true),
        GroceryItemModel(name: "Eggs", isChecked: false),
        GroceryItemModel(name: "Bread", isChecked: true),
    ]
    let list = GroceryListModel(name: "Weekly", items: items)
    check(list.completedCount == 2, "Completed count")
    check(list.items.count == 3, "Total items")
}

func testRecipeCodable() {
    let recipe = RecipeModel(name: "Test", prepTimeMinutes: 5)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(recipe)
        let decoded = try decoder.decode(RecipeModel.self, from: data)
        check(decoded.name == recipe.name, "Codable round-trip name")
        check(decoded.prepTimeMinutes == recipe.prepTimeMinutes, "Codable round-trip prep time")
    } catch {
        print("FAIL: Codable encoding/decoding - \(error)")
    }
}

@main
struct TestRunner {
    static func main() {
        print("=== Recipe App Model Tests ===")
        testRecipeCreation()
        testRecipeWithIngredients()
        testGroceryItem()
        testGroceryList()
        testRecipeCodable()
        print("=== Done ===")
    }
}
