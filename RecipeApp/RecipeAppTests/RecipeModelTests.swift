import XCTest
@testable import RecipeApp

final class RecipeModelTests: XCTestCase {
    func testRecipeInit() {
        let recipe = Recipe(name: "Test", prepTimeMinutes: 10, cookTimeMinutes: 20)
        XCTAssertEqual(recipe.name, "Test")
        XCTAssertEqual(recipe.totalTimeMinutes, 30)
        XCTAssertEqual(recipe.servings, 1)
    }

    func testIngredientInit() {
        let ingredient = Ingredient(name: "Salt", quantity: 1, unit: "tsp")
        XCTAssertEqual(ingredient.name, "Salt")
        XCTAssertEqual(ingredient.quantity, 1)
    }

    func testGroceryItemToggle() {
        let item = GroceryItem(name: "Milk")
        XCTAssertFalse(item.isChecked)
        item.isChecked = true
        XCTAssertTrue(item.isChecked)
    }
}
