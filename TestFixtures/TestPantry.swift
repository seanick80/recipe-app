import Foundation

// MARK: - Pantry Item Mapper Tests

func testMapKnownYOLOLabel() {
    let item = mapYOLOLabel("apple", confidence: 0.92)
    check(item != nil, "Known label maps")
    checkEqual(item!.name, "Apple", "Known label display name")
    checkEqual(item!.category, "Produce", "Known label category")
    checkEqual(item!.confidence, 0.92, "Confidence preserved")
    checkEqual(item!.quantity, 1, "Default quantity 1")
}

func testMapUnknownYOLOLabel() {
    let item = mapYOLOLabel("weird_thing", confidence: 0.60)
    check(item != nil, "Unknown label still maps")
    checkEqual(item!.name, "Weird Thing", "Unknown label title-cased")
    checkEqual(item!.category, "Other", "Unknown label → Other category")
}

func testNormalizeYOLOLabel() {
    checkEqual(normalizeYOLOLabel("Apple"), "apple", "Lowercase")
    checkEqual(normalizeYOLOLabel("bell pepper"), "bell_pepper", "Space → underscore")
    checkEqual(normalizeYOLOLabel("ice-cream"), "ice_cream", "Hyphen → underscore")
    checkEqual(normalizeYOLOLabel("  milk  "), "milk", "Trimmed")
}

func testMapVariousCategories() {
    // Produce
    let banana = mapYOLOLabel("banana", confidence: 0.9)!
    checkEqual(banana.category, "Produce", "banana → Produce")

    // Dairy
    let milk = mapYOLOLabel("milk", confidence: 0.9)!
    checkEqual(milk.category, "Dairy", "milk → Dairy")

    // Meat
    let chicken = mapYOLOLabel("chicken", confidence: 0.9)!
    checkEqual(chicken.category, "Meat", "chicken → Meat")

    // Frozen
    let iceCream = mapYOLOLabel("ice_cream", confidence: 0.9)!
    checkEqual(iceCream.category, "Frozen", "ice_cream → Frozen")

    // Beverages
    let juice = mapYOLOLabel("juice", confidence: 0.9)!
    checkEqual(juice.category, "Beverages", "juice → Beverages")

    // Snacks
    let chips = mapYOLOLabel("chips", confidence: 0.9)!
    checkEqual(chips.category, "Snacks", "chips → Snacks")

    // Condiments
    let ketchup = mapYOLOLabel("ketchup", confidence: 0.9)!
    checkEqual(ketchup.category, "Condiments", "ketchup → Condiments")
}

func testMapWithCustomQuantity() {
    let item = mapYOLOLabel("apple", confidence: 0.9, quantity: 5)
    checkEqual(item!.quantity, 5, "Custom quantity preserved")
}

func testMapMilkCarton() {
    let item = mapYOLOLabel("milk_carton", confidence: 0.88)
    check(item != nil, "milk_carton maps")
    checkEqual(item!.name, "Milk", "milk_carton → Milk display name")
    checkEqual(item!.category, "Dairy", "milk_carton → Dairy")
}

func testMapBellPepperWithSpace() {
    let item = mapYOLOLabel("bell pepper", confidence: 0.85)
    check(item != nil, "bell pepper with space maps")
    checkEqual(item!.name, "Bell Pepper", "bell pepper display name")
    checkEqual(item!.category, "Produce", "bell pepper → Produce")
}

func testMergePantryDetections() {
    let items = [
        PantryItemModel(name: "Apple", category: "Produce", quantity: 1, confidence: 0.80),
        PantryItemModel(name: "Apple", category: "Produce", quantity: 1, confidence: 0.95),
        PantryItemModel(name: "Banana", category: "Produce", quantity: 2, confidence: 0.90),
        PantryItemModel(name: "apple", category: "Produce", quantity: 3, confidence: 0.70),
    ]
    let merged = mergePantryDetections(items)
    checkEqual(merged.count, 2, "Merge: 2 unique items")

    let apple = merged.first { $0.name.lowercased() == "apple" }
    check(apple != nil, "Merge: apple found")
    checkEqual(apple!.quantity, 5, "Merge: apple quantity summed (1+1+3)")
    checkEqual(apple!.confidence, 0.95, "Merge: apple highest confidence kept")

    let banana = merged.first { $0.name.lowercased() == "banana" }
    check(banana != nil, "Merge: banana found")
    checkEqual(banana!.quantity, 2, "Merge: banana quantity")
}

func testMergeEmptyDetections() {
    let merged = mergePantryDetections([])
    checkEqual(merged.count, 0, "Merge empty → empty")
}

func testPantryItemCodable() {
    let item = PantryItemModel(
        name: "Apple",
        category: "Produce",
        quantity: 3,
        confidence: 0.92
    )
    checkCodableRoundTrip(item, "PantryItemModel Codable round-trip")
}

// MARK: - Test Runner

func runPantryTests() -> Bool {
    print("\n=== Pantry Item Mapper Tests ===")

    testMapKnownYOLOLabel()
    testMapUnknownYOLOLabel()
    testNormalizeYOLOLabel()
    testMapVariousCategories()
    testMapWithCustomQuantity()
    testMapMilkCarton()
    testMapBellPepperWithSpace()
    testMergePantryDetections()
    testMergeEmptyDetections()
    testPantryItemCodable()

    return printTestSummary("Pantry Mapper Tests")
}
