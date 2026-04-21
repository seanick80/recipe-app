import Foundation

// MARK: - Zone Classifier Tests

func testClassifyZoneTypes() {
    // Ingredients
    let ing = classifyZone("2 cups flour\n1 tsp vanilla\n3 eggs\n1/2 lb butter")
    checkEqual(ing.label, .ingredients, "Ingredient list -> ingredients")

    // Instructions
    let inst = classifyZone("1. Preheat oven to 350\u{00B0}F\n2. Mix flour and sugar\n3. Bake for 25 minutes")
    checkEqual(inst.label, .instructions, "Cooking steps -> instructions")

    // Title
    checkEqual(classifyZone("Grandma's Chicken Soup").label, .title, "Short text -> title")

    // Headers -> title
    checkEqual(classifyZone("Ingredients").label, .title, "Section header -> title")

    // Metadata
    checkEqual(classifyZone("Serves 4\nPrep time: 15 min").label, .metadata, "Servings+times -> metadata")

    // Junk
    checkEqual(classifyZone("Call 555-123-4567").label, .other, "Phone -> other")
    checkEqual(classifyZone("").label, .other, "Empty -> other")

    // Handwritten
    checkEqual(classifyZone("x2 double the recipe").label, .handwritten, "Scaling note -> handwritten")
}

func testMixedBlockClassification() {
    // Mostly ingredients wins
    let mixed = classifyZone("1 cup flour\n2 eggs\n1/2 tsp salt\n3 tbsp butter\nmix well")
    checkEqual(mixed.label, .ingredients, "Mostly ingredients wins")
}

func testFilterAndClassifyZones() {
    let blocks = [
        "Easy Cookies",
        "2 cups flour\n1 tsp vanilla\n3 eggs",
        "1. Preheat oven to 350\u{00B0}F\n2. Mix and bake",
    ]
    let ingredients = filterZones(blocks, label: .ingredients)
    checkEqual(ingredients.count, 1, "filterZones: 1 ingredient block")

    let results = classifyZones(blocks)
    checkEqual(results.count, 3, "classifyZones: one result per block")
}

func testZoneClassificationCodable() {
    checkCodableRoundTrip(ZoneClassification(label: .ingredients, confidence: 0.85), "ZoneClassification Codable")
}

// MARK: - Test Runner

func runZoneClassifierTests() -> Bool {
    print("\n=== Zone Classifier Tests ===")

    testClassifyZoneTypes()
    testMixedBlockClassification()
    testFilterAndClassifyZones()
    testZoneClassificationCodable()

    return printTestSummary("Zone Classifier Tests")
}
