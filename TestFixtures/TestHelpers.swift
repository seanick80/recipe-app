import Foundation

/// Shared test infrastructure for pure-Swift model tests.
/// Modeled after the fractal drawing app's TestHelpers.java pattern:
/// factory methods for test fixtures, assertion helpers, and utilities.

// MARK: - Assertion Helpers

var testFailCount = 0
var testPassCount = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("PASS: \(message)")
        testPassCount += 1
    } else {
        print("FAIL: \(message)")
        testFailCount += 1
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual == expected {
        print("PASS: \(message)")
        testPassCount += 1
    } else {
        print("FAIL: \(message) — expected \(expected), got \(actual)")
        testFailCount += 1
    }
}

func checkCodableRoundTrip<T: Codable & Equatable>(_ value: T, _ message: String) {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        check(decoded == value, message)
    } catch {
        print("FAIL: \(message) — \(error)")
        testFailCount += 1
    }
}

func printTestSummary(_ suiteName: String) -> Bool {
    let total = testPassCount + testFailCount
    print("--- \(suiteName): \(testPassCount)/\(total) passed ---")
    let passed = testFailCount == 0
    // Reset for next suite
    testPassCount = 0
    testFailCount = 0
    return passed
}

// MARK: - Recipe Factories

func makeRecipe(
    name: String = "Test Recipe",
    prepTime: Int = 10,
    cookTime: Int = 20,
    servings: Int = 4,
    cuisine: String = "",
    course: String = "",
    tags: String = "",
    sourceURL: String = "",
    difficulty: String = "",
    isFavorite: Bool = false,
    ingredientCount: Int = 0
) -> RecipeModel {
    let ingredients = (0..<ingredientCount).map { i in
        IngredientModel(name: "Ingredient \(i + 1)", quantity: Double(i + 1), unit: "cup", displayOrder: i)
    }
    return RecipeModel(
        name: name,
        prepTimeMinutes: prepTime,
        cookTimeMinutes: cookTime,
        servings: servings,
        cuisine: cuisine,
        course: course,
        tags: tags,
        sourceURL: sourceURL,
        difficulty: difficulty,
        isFavorite: isFavorite,
        ingredients: ingredients
    )
}

// MARK: - Grocery Factories

func makeGroceryItem(
    name: String = "Milk",
    quantity: Double = 1,
    unit: String = "gallon",
    category: String = "Dairy",
    isChecked: Bool = false
) -> GroceryItemModel {
    GroceryItemModel(
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
        isChecked: isChecked
    )
}

func makeGroceryList(
    name: String = "Weekly",
    items: [GroceryItemModel]? = nil
) -> GroceryListModel {
    let listItems =
        items ?? [
            makeGroceryItem(name: "Milk", category: "Dairy"),
            makeGroceryItem(name: "Eggs", quantity: 12, unit: "count", category: "Dairy"),
            makeGroceryItem(name: "Bread", quantity: 1, unit: "loaf", category: "Bakery"),
        ]
    return GroceryListModel(name: name, items: listItems)
}

// MARK: - Shopping Template Factories

func makeTemplateItem(
    name: String = "Milk",
    quantity: Double = 1,
    unit: String = "gallon",
    category: String = "Dairy",
    sortOrder: Int = 0
) -> TemplateItemModel {
    TemplateItemModel(
        name: name,
        quantity: quantity,
        unit: unit,
        category: category,
        sortOrder: sortOrder
    )
}

func makeShoppingTemplate(
    name: String = "Weekly Staples",
    items: [TemplateItemModel]? = nil
) -> ShoppingTemplateModel {
    let templateItems =
        items ?? [
            makeTemplateItem(name: "Bananas", quantity: 1, unit: "bunch", category: "Produce", sortOrder: 0),
            makeTemplateItem(name: "Milk", quantity: 1, unit: "gallon", category: "Dairy", sortOrder: 1),
            makeTemplateItem(name: "Eggs", quantity: 12, unit: "count", category: "Dairy", sortOrder: 2),
            makeTemplateItem(name: "Chicken Breast", quantity: 2, unit: "lb", category: "Meat", sortOrder: 3),
            makeTemplateItem(name: "Rice", quantity: 1, unit: "bag", category: "Dry & Canned", sortOrder: 4),
        ]
    return ShoppingTemplateModel(name: name, items: templateItems)
}

/// Creates a template with items spanning all default categories,
/// useful for testing sort order.
func makeFullCategoryTemplate() -> ShoppingTemplateModel {
    ShoppingTemplateModel(
        name: "Full Category Test",
        items: [
            makeTemplateItem(name: "Ice Cream", category: "Frozen", sortOrder: 0),
            makeTemplateItem(name: "Apples", category: "Produce", sortOrder: 0),
            makeTemplateItem(name: "Milk", category: "Dairy", sortOrder: 0),
            makeTemplateItem(name: "Chicken", category: "Meat", sortOrder: 0),
            makeTemplateItem(name: "Pasta", category: "Dry & Canned", sortOrder: 0),
            makeTemplateItem(name: "Paper Towels", category: "Household", sortOrder: 0),
            makeTemplateItem(name: "Chips", category: "Snacks", sortOrder: 0),
            makeTemplateItem(name: "OJ", category: "Beverages", sortOrder: 0),
            makeTemplateItem(name: "Ketchup", category: "Condiments", sortOrder: 0),
            makeTemplateItem(name: "Other Thing", category: "Other", sortOrder: 0),
            makeTemplateItem(name: "Sourdough", category: "Bakery", sortOrder: 0),
        ]
    )
}
