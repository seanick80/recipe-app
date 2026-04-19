import Foundation

// MARK: - Shopping Template Tests

func testTemplateCreation() {
    let template = makeShoppingTemplate()
    checkEqual(template.name, "Weekly Staples", "Template name")
    checkEqual(template.items.count, 5, "Template item count")
    checkEqual(template.items[0].name, "Bananas", "First template item")
}

func testEmptyTemplate() {
    let template = ShoppingTemplateModel(name: "Empty")
    checkEqual(template.items.count, 0, "Empty template has no items")
    let list = template.stampGroceryList()
    checkEqual(list.items.count, 0, "Stamped list from empty template has no items")
    checkEqual(list.name, "Empty", "Stamped list inherits template name")
}

// MARK: - Stamp Grocery List Tests

func testStampGroceryList() {
    let template = makeShoppingTemplate()
    let list = template.stampGroceryList()

    checkEqual(list.name, "Weekly Staples", "Stamped list inherits template name")
    checkEqual(list.items.count, 5, "Stamped list has same item count")
    checkEqual(list.items[0].name, "Bananas", "First item name matches")
    check(!list.items[0].isChecked, "Stamped items start unchecked")
}

func testStampWithCustomName() {
    let list = makeShoppingTemplate().stampGroceryList(name: "Week of Apr 14")
    checkEqual(list.name, "Week of Apr 14", "Custom name overrides template name")
}

func testStampProducesDistinctIds() {
    let template = makeShoppingTemplate()
    let list1 = template.stampGroceryList()
    let list2 = template.stampGroceryList()

    check(list1.id != list2.id, "Stamped lists have distinct IDs")
    check(list1.items[0].id != list2.items[0].id, "Stamped items have distinct IDs")
    checkEqual(list1.items[0].name, list2.items[0].name, "Stamped items have same name")
}

func testStampedItemsAllUnchecked() {
    let template = makeShoppingTemplate()
    let list = template.stampGroceryList()
    let allUnchecked = list.items.allSatisfy { !$0.isChecked }
    check(allUnchecked, "All stamped items are unchecked")
}

// MARK: - Category Sort Order Tests

func testDefaultCategoryOrder() {
    checkEqual(defaultCategoryOrder[0], "Produce", "First category is Produce")
    checkEqual(defaultCategoryOrder[5], "Frozen", "Frozen is at index 5")
}

func testCategorySortIndex() {
    checkEqual(categorySortIndex("Produce"), 0, "Produce is index 0")
    checkEqual(categorySortIndex("Frozen"), 5, "Frozen is index 5")
    checkEqual(categorySortIndex("Other"), 11, "Other is last known index")
    checkEqual(
        categorySortIndex("Unknown Category"),
        defaultCategoryOrder.count,
        "Unknown category sorts after all known"
    )
}

func testSortedByStoreAisle() {
    // Cross-category sort
    let items = [
        makeTemplateItem(name: "Ice Cream", category: "Frozen", sortOrder: 0),
        makeTemplateItem(name: "Apples", category: "Produce", sortOrder: 0),
        makeTemplateItem(name: "Milk", category: "Dairy", sortOrder: 0),
        makeTemplateItem(name: "Chicken", category: "Meat", sortOrder: 0),
    ]
    let sorted = sortedByStoreAisle(items, category: { $0.category }, sortOrder: { $0.sortOrder })
    checkEqual(sorted[0].name, "Apples", "Produce sorts first")
    checkEqual(sorted[1].name, "Milk", "Dairy sorts second")
    checkEqual(sorted[2].name, "Chicken", "Meat sorts third")
    checkEqual(sorted[3].name, "Ice Cream", "Frozen sorts last")

    // Within-category sort by sortOrder
    let dairy = [
        makeTemplateItem(name: "Yogurt", category: "Dairy", sortOrder: 2),
        makeTemplateItem(name: "Milk", category: "Dairy", sortOrder: 0),
        makeTemplateItem(name: "Cheese", category: "Dairy", sortOrder: 1),
    ]
    let dairySorted = sortedByStoreAisle(dairy, category: { $0.category }, sortOrder: { $0.sortOrder })
    checkEqual(dairySorted[0].name, "Milk", "sortOrder 0 first")
    checkEqual(dairySorted[1].name, "Cheese", "sortOrder 1 second")
    checkEqual(dairySorted[2].name, "Yogurt", "sortOrder 2 third")
}

func testGroupedByStoreAisle() {
    let template = makeFullCategoryTemplate()
    let grouped = groupedByStoreAisle(
        template.items,
        category: { $0.category },
        sortOrder: { $0.sortOrder }
    )
    checkEqual(grouped[0].0, "Produce", "First group is Produce")
    checkEqual(grouped.last!.0, "Other", "Last group is Other")
}

// MARK: - Codable Round-Trip Tests

func testTemplateCodable() {
    checkCodableRoundTrip(makeShoppingTemplate(), "Template Codable round-trip")
}

func testTemplateItemCodable() {
    let item = makeTemplateItem(name: "Eggs", quantity: 12, unit: "count", category: "Dairy", sortOrder: 3)
    checkCodableRoundTrip(item, "TemplateItem Codable round-trip")
}

// MARK: - GroceryList Model Tests (enhanced)

func testGroceryListCompletedCount() {
    let partial = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A", isChecked: true),
            makeGroceryItem(name: "B", isChecked: false),
            makeGroceryItem(name: "C", isChecked: true),
        ]
    )
    checkEqual(partial.completedCount, 2, "Completed count with 2 checked")

    let allChecked = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A", isChecked: true),
            makeGroceryItem(name: "B", isChecked: true),
        ]
    )
    checkEqual(allChecked.completedCount, allChecked.items.count, "All items checked")

    let noneChecked = GroceryListModel(
        name: "Test",
        items: [makeGroceryItem(name: "A"), makeGroceryItem(name: "B")]
    )
    checkEqual(noneChecked.completedCount, 0, "No items checked")
}

// MARK: - Test Runner

func runShoppingTests() -> Bool {
    print("\n=== Shopping Template Tests ===")

    testTemplateCreation()
    testEmptyTemplate()
    testStampGroceryList()
    testStampWithCustomName()
    testStampProducesDistinctIds()
    testStampedItemsAllUnchecked()
    testDefaultCategoryOrder()
    testCategorySortIndex()
    testSortedByStoreAisle()
    testGroupedByStoreAisle()
    testTemplateCodable()
    testTemplateItemCodable()
    testGroceryListCompletedCount()

    return printTestSummary("Shopping Tests")
}
