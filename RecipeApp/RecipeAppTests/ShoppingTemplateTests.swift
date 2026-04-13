import XCTest

@testable import RecipeApp

final class ShoppingTemplateTests: XCTestCase {
    func testShoppingTemplateInit() {
        let template = ShoppingTemplate(name: "Weekly")
        XCTAssertEqual(template.name, "Weekly")
        XCTAssertEqual(template.items?.count ?? 0, 0)
    }

    func testTemplateItemInit() {
        let item = TemplateItem(
            name: "Milk",
            quantity: 1,
            unit: "gallon",
            category: "Dairy",
            sortOrder: 0
        )
        XCTAssertEqual(item.name, "Milk")
        XCTAssertEqual(item.category, "Dairy")
    }

    func testGroceryListArchivedAt() {
        let list = GroceryList(name: "Test")
        XCTAssertNil(list.archivedAt)
        list.archivedAt = Date()
        XCTAssertNotNil(list.archivedAt)
    }

    func testIngredientCategory() {
        let ingredient = Ingredient(name: "Chicken", quantity: 1, unit: "lb", category: "Meat")
        XCTAssertEqual(ingredient.category, "Meat")
    }

    func testIngredientDefaultCategory() {
        let ingredient = Ingredient(name: "Something", quantity: 1, unit: "")
        XCTAssertEqual(ingredient.category, "Other")
    }
}
