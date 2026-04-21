import Foundation

// MARK: - Pantry Item Mapper Tests

func testMapYOLOLabels() {
    let apple = mapYOLOLabel("apple", confidence: 0.92)!
    checkEqual(apple.name, "Apple", "Known label display name")
    checkEqual(apple.category, "Produce", "Known label category")

    let unknown = mapYOLOLabel("weird_thing", confidence: 0.60)!
    checkEqual(unknown.category, "Other", "Unknown -> Other")

    // Variant labels
    checkEqual(mapYOLOLabel("milk_carton", confidence: 0.88)!.name, "Milk", "milk_carton -> Milk")

    // Normalize
    checkEqual(normalizeYOLOLabel("bell pepper"), "bell_pepper", "Space -> underscore")
}

func testMergePantryDetections() {
    let items = [
        PantryItemModel(name: "Apple", category: "Produce", quantity: 1, confidence: 0.80),
        PantryItemModel(name: "Apple", category: "Produce", quantity: 1, confidence: 0.95),
        PantryItemModel(name: "apple", category: "Produce", quantity: 3, confidence: 0.70),
    ]
    let merged = mergePantryDetections(items)
    checkEqual(merged.count, 1, "Merge: 1 unique")
    checkEqual(merged[0].quantity, 5, "Merge: quantity summed")
    checkEqual(merged[0].confidence, 0.95, "Merge: max confidence")

    checkEqual(mergePantryDetections([]).count, 0, "Merge empty")
}

func testPantryItemCodable() {
    checkCodableRoundTrip(
        PantryItemModel(name: "Apple", category: "Produce", quantity: 3, confidence: 0.92),
        "PantryItem Codable"
    )
}

// MARK: - Test Runner

func runPantryTests() -> Bool {
    print("\n=== Pantry Item Mapper Tests ===")

    testMapYOLOLabels()
    testMergePantryDetections()
    testPantryItemCodable()

    return printTestSummary("Pantry Mapper Tests")
}
