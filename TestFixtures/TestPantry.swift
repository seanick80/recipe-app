import Foundation

// MARK: - Pantry Item Mapper Tests

func testMapYOLOLabel() {
    // Known label
    let apple = mapYOLOLabel("apple", confidence: 0.92)!
    checkEqual(apple.name, "Apple", "Known label display name")
    checkEqual(apple.category, "Produce", "Known label category")
    checkEqual(apple.confidence, 0.92, "Confidence preserved")
    checkEqual(apple.quantity, 1, "Default quantity 1")

    // Unknown label
    let unknown = mapYOLOLabel("weird_thing", confidence: 0.60)!
    checkEqual(unknown.name, "Weird Thing", "Unknown label title-cased")
    checkEqual(unknown.category, "Other", "Unknown label -> Other category")
}

func testNormalizeYOLOLabel() {
    checkEqual(normalizeYOLOLabel("Apple"), "apple", "Lowercase")
    checkEqual(normalizeYOLOLabel("bell pepper"), "bell_pepper", "Space -> underscore")
    checkEqual(normalizeYOLOLabel("ice-cream"), "ice_cream", "Hyphen -> underscore")
    checkEqual(normalizeYOLOLabel("  milk  "), "milk", "Trimmed")

    // Variant labels map to correct display names
    let milkCarton = mapYOLOLabel("milk_carton", confidence: 0.88)!
    checkEqual(milkCarton.name, "Milk", "milk_carton -> Milk display name")
    checkEqual(milkCarton.category, "Dairy", "milk_carton -> Dairy")

    let bellPepper = mapYOLOLabel("bell pepper", confidence: 0.85)!
    checkEqual(bellPepper.name, "Bell Pepper", "bell pepper display name")
    checkEqual(bellPepper.category, "Produce", "bell pepper -> Produce")
}

func testMapVariousCategories() {
    let cases: [(String, String)] = [
        ("banana", "Produce"),
        ("milk", "Dairy"),
        ("chicken", "Meat"),
        ("juice", "Beverages"),
    ]
    for (label, expected) in cases {
        let item = mapYOLOLabel(label, confidence: 0.9)!
        checkEqual(item.category, expected, "\(label) -> \(expected)")
    }
}

func testMapWithCustomQuantity() {
    let item = mapYOLOLabel("apple", confidence: 0.9, quantity: 5)
    checkEqual(item!.quantity, 5, "Custom quantity preserved")
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

    let apple = merged.first { $0.name.lowercased() == "apple" }!
    checkEqual(apple.quantity, 5, "Merge: apple quantity summed (1+1+3)")
    checkEqual(apple.confidence, 0.95, "Merge: apple highest confidence kept")

    let banana = merged.first { $0.name.lowercased() == "banana" }!
    checkEqual(banana.quantity, 2, "Merge: banana quantity")
}

func testMergeEmptyDetections() {
    checkEqual(mergePantryDetections([]).count, 0, "Merge empty -> empty")
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

    testMapYOLOLabel()
    testNormalizeYOLOLabel()
    testMapVariousCategories()
    testMapWithCustomQuantity()
    testMergePantryDetections()
    testMergeEmptyDetections()
    testPantryItemCodable()

    return printTestSummary("Pantry Mapper Tests")
}
