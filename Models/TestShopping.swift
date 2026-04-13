import Foundation

// MARK: - Shopping Template Tests

func testTemplateCreation() {
    let template = makeShoppingTemplate()
    checkEqual(template.name, "Weekly Staples", "Template name")
    checkEqual(template.items.count, 5, "Template item count")
    checkEqual(template.items[0].name, "Bananas", "First template item")
}

func testTemplateItemDefaults() {
    let item = TemplateItemModel()
    checkEqual(item.name, "", "Default name is empty")
    checkEqual(item.quantity, 1, "Default quantity is 1")
    checkEqual(item.unit, "", "Default unit is empty")
    checkEqual(item.category, "Other", "Default category is Other")
    checkEqual(item.sortOrder, 0, "Default sortOrder is 0")
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
    checkEqual(list.items.count, 5, "Stamped list has same item count as template")
    checkEqual(list.items[0].name, "Bananas", "First item name matches")
    checkEqual(list.items[0].quantity, 1, "First item quantity matches")
    checkEqual(list.items[0].unit, "bunch", "First item unit matches")
    checkEqual(list.items[0].category, "Produce", "First item category matches")
    check(!list.items[0].isChecked, "Stamped items start unchecked")
}

func testStampWithCustomName() {
    let template = makeShoppingTemplate()
    let list = template.stampGroceryList(name: "Week of Apr 14")
    checkEqual(list.name, "Week of Apr 14", "Custom name overrides template name")
    checkEqual(list.items.count, 5, "Item count still matches")
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
    checkEqual(defaultCategoryOrder[1], "Dairy", "Second category is Dairy")
    checkEqual(defaultCategoryOrder[2], "Meat", "Third category is Meat")
    checkEqual(defaultCategoryOrder[3], "Dry & Canned", "Fourth category is Dry & Canned")
    checkEqual(defaultCategoryOrder[4], "Household", "Fifth category is Household")
    checkEqual(defaultCategoryOrder[5], "Frozen", "Sixth category is Frozen")
}

func testCategorySortIndex() {
    checkEqual(categorySortIndex("Produce"), 0, "Produce is index 0")
    checkEqual(categorySortIndex("Dairy"), 1, "Dairy is index 1")
    checkEqual(categorySortIndex("Frozen"), 5, "Frozen is index 5")
    checkEqual(categorySortIndex("Other"), 10, "Other is last known index")
    checkEqual(
        categorySortIndex("Unknown Category"),
        defaultCategoryOrder.count,
        "Unknown category sorts after all known"
    )
}

func testSortedByStoreAisle() {
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
}

func testSortWithinCategory() {
    let items = [
        makeTemplateItem(name: "Yogurt", category: "Dairy", sortOrder: 2),
        makeTemplateItem(name: "Milk", category: "Dairy", sortOrder: 0),
        makeTemplateItem(name: "Cheese", category: "Dairy", sortOrder: 1),
    ]
    let sorted = sortedByStoreAisle(items, category: { $0.category }, sortOrder: { $0.sortOrder })
    checkEqual(sorted[0].name, "Milk", "sortOrder 0 first")
    checkEqual(sorted[1].name, "Cheese", "sortOrder 1 second")
    checkEqual(sorted[2].name, "Yogurt", "sortOrder 2 third")
}

func testGroupedByStoreAisle() {
    let template = makeFullCategoryTemplate()
    let grouped = groupedByStoreAisle(
        template.items,
        category: { $0.category },
        sortOrder: { $0.sortOrder }
    )

    checkEqual(grouped[0].0, "Produce", "First group is Produce")
    checkEqual(grouped[1].0, "Dairy", "Second group is Dairy")
    checkEqual(grouped[2].0, "Meat", "Third group is Meat")
    checkEqual(grouped[3].0, "Dry & Canned", "Fourth group is Dry & Canned")
    checkEqual(grouped[4].0, "Household", "Fifth group is Household")
    checkEqual(grouped[5].0, "Frozen", "Sixth group is Frozen")

    checkEqual(grouped[0].1[0].name, "Apples", "Produce group contains Apples")
    checkEqual(grouped[2].1[0].name, "Chicken", "Meat group contains Chicken")
}

func testGroupedWithGroceryItems() {
    let items = [
        makeGroceryItem(name: "Frozen Pizza", category: "Frozen"),
        makeGroceryItem(name: "Bananas", category: "Produce"),
        makeGroceryItem(name: "Milk", category: "Dairy"),
    ]
    let grouped = groupedByStoreAisle(items, category: { $0.category }, sortOrder: { _ in 0 })
    checkEqual(grouped[0].0, "Produce", "GroceryItems: Produce first")
    checkEqual(grouped[1].0, "Dairy", "GroceryItems: Dairy second")
    checkEqual(grouped[2].0, "Frozen", "GroceryItems: Frozen third")
}

// MARK: - Codable Round-Trip Tests

func testTemplateCodable() {
    let template = makeShoppingTemplate()
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(template)
        let decoded = try decoder.decode(ShoppingTemplateModel.self, from: data)
        checkEqual(decoded.name, template.name, "Template Codable round-trip name")
        checkEqual(decoded.items.count, template.items.count, "Template Codable round-trip items count")
        checkEqual(decoded.items[0].name, template.items[0].name, "Template Codable round-trip first item")
    } catch {
        print("FAIL: Template Codable — \(error)")
        testFailCount += 1
    }
}

func testTemplateItemCodable() {
    let item = makeTemplateItem(name: "Eggs", quantity: 12, unit: "count", category: "Dairy", sortOrder: 3)
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    do {
        let data = try encoder.encode(item)
        let decoded = try decoder.decode(TemplateItemModel.self, from: data)
        checkEqual(decoded.name, "Eggs", "TemplateItem Codable name")
        checkEqual(decoded.quantity, 12, "TemplateItem Codable quantity")
        checkEqual(decoded.category, "Dairy", "TemplateItem Codable category")
        checkEqual(decoded.sortOrder, 3, "TemplateItem Codable sortOrder")
    } catch {
        print("FAIL: TemplateItem Codable — \(error)")
        testFailCount += 1
    }
}

// MARK: - GroceryList Model Tests (enhanced)

func testGroceryListCompletedCount() {
    let list = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A", isChecked: true),
            makeGroceryItem(name: "B", isChecked: false),
            makeGroceryItem(name: "C", isChecked: true),
        ]
    )
    checkEqual(list.completedCount, 2, "Completed count with 2 checked")
}

func testGroceryListAllChecked() {
    let list = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A", isChecked: true),
            makeGroceryItem(name: "B", isChecked: true),
        ]
    )
    checkEqual(list.completedCount, list.items.count, "All items checked")
}

func testGroceryListNoneChecked() {
    let list = GroceryListModel(
        name: "Test",
        items: [
            makeGroceryItem(name: "A"),
            makeGroceryItem(name: "B"),
        ]
    )
    checkEqual(list.completedCount, 0, "No items checked")
}

// MARK: - Test Runner

func runShoppingTests() -> Bool {
    print("\n=== Shopping Template Tests ===")

    testTemplateCreation()
    testTemplateItemDefaults()
    testEmptyTemplate()
    testStampGroceryList()
    testStampWithCustomName()
    testStampProducesDistinctIds()
    testStampedItemsAllUnchecked()
    testDefaultCategoryOrder()
    testCategorySortIndex()
    testSortedByStoreAisle()
    testSortWithinCategory()
    testGroupedByStoreAisle()
    testGroupedWithGroceryItems()
    testTemplateCodable()
    testTemplateItemCodable()
    testGroceryListCompletedCount()
    testGroceryListAllChecked()
    testGroceryListNoneChecked()

    return printTestSummary("Shopping Tests")
}
