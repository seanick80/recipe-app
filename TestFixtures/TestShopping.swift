import Foundation

// MARK: - Shopping Template Tests

func testTemplateAndStamp() {
    let template = makeShoppingTemplate()
    checkEqual(template.name, "Weekly Staples", "Template name")
    checkEqual(template.items.count, 5, "Template item count")

    let list = template.stampGroceryList()
    checkEqual(list.name, "Weekly Staples", "Stamped list name")
    checkEqual(list.items.count, 5, "Stamped list items")
    check(!list.items[0].isChecked, "Stamped items unchecked")

    // Custom name + distinct IDs
    let custom = template.stampGroceryList(name: "Week of Apr 14")
    checkEqual(custom.name, "Week of Apr 14", "Custom name override")
    check(list.id != custom.id, "Distinct list IDs")
    check(list.items[0].id != custom.items[0].id, "Distinct item IDs")
}

func testEmptyTemplate() {
    let template = ShoppingTemplateModel(name: "Empty")
    checkEqual(template.stampGroceryList().items.count, 0, "Empty template stamps empty")
}

func testCategorySortOrder() {
    checkEqual(categorySortIndex("Produce"), 0, "Produce index 0")
    checkEqual(categorySortIndex("Unknown"), defaultCategoryOrder.count, "Unknown sorts last")

    let items = [
        makeTemplateItem(name: "Ice", category: "Frozen", sortOrder: 0),
        makeTemplateItem(name: "Apple", category: "Produce", sortOrder: 0),
        makeTemplateItem(name: "Milk", category: "Dairy", sortOrder: 0),
    ]
    let sorted = sortedByStoreAisle(items, category: { $0.category }, sortOrder: { $0.sortOrder })
    checkEqual(sorted[0].name, "Apple", "Produce sorts first")
    checkEqual(sorted[2].name, "Ice", "Frozen sorts last")
}

func testGroceryListCompletedCount() {
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

func testCodableRoundTrips() {
    checkCodableRoundTrip(makeShoppingTemplate(), "Template Codable")
    checkCodableRoundTrip(
        makeTemplateItem(name: "Eggs", quantity: 12, unit: "count", category: "Dairy", sortOrder: 3),
        "TemplateItem Codable"
    )
}

// MARK: - Test Runner

func runShoppingTests() -> Bool {
    print("\n=== Shopping Template Tests ===")

    testTemplateAndStamp()
    testEmptyTemplate()
    testCategorySortOrder()
    testGroceryListCompletedCount()
    testCodableRoundTrips()

    return printTestSummary("Shopping Tests")
}
