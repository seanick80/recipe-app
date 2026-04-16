import Foundation

// MARK: - Zone Classifier Tests

func testClassifyIngredients() {
    let text = """
        2 cups flour
        1 tsp vanilla extract
        3 eggs
        1/2 lb butter
        """
    let result = classifyZone(text)
    checkEqual(result.label, .ingredients, "Ingredient list -> ingredients")
    check(result.confidence > 0.5, "Ingredient confidence > 50% (got \(result.confidence))")
}

func testClassifyInstructions() {
    let text = """
        1. Preheat oven to 350°F
        2. Mix flour and sugar in a large bowl
        3. Add eggs and stir until combined
        4. Bake for 25 minutes
        """
    let result = classifyZone(text)
    checkEqual(result.label, .instructions, "Cooking steps -> instructions")
    check(result.confidence > 0.5, "Instruction confidence > 50% (got \(result.confidence))")
}

func testClassifyTitle() {
    let result = classifyZone("Grandma's Chicken Soup")
    checkEqual(result.label, .title, "Short title-case text -> title")
}

func testClassifySectionHeader() {
    checkEqual(classifyZone("Ingredients").label, .title, "'Ingredients' header -> title")
    checkEqual(classifyZone("Directions:").label, .title, "'Directions:' header -> title")
    checkEqual(classifyZone("Method").label, .title, "'Method' header -> title")
    checkEqual(classifyZone("For the filling").label, .title, "'For the filling' -> title")
}

func testClassifyMetadata() {
    let text = "Serves 4\nPrep time: 15 min\nCook time: 45 min"
    let result = classifyZone(text)
    checkEqual(result.label, .metadata, "Servings + times -> metadata")
}

func testClassifyJunk() {
    let phone = classifyZone("Call 555-123-4567")
    checkEqual(phone.label, .other, "Phone number -> other")

    let url = classifyZone("Visit www.example.com for more")
    checkEqual(url.label, .other, "URL -> other")

    let copyright = classifyZone("Copyright 2024 All Rights Reserved")
    checkEqual(copyright.label, .other, "Copyright -> other")
}

func testClassifyEmpty() {
    let result = classifyZone("")
    checkEqual(result.label, .other, "Empty text -> other")
    check(result.confidence < 0.2, "Empty confidence low")
}

func testClassifyHandwritingContent() {
    let result = classifyZone("x2 double the recipe")
    checkEqual(result.label, .handwritten, "Scaling note -> handwritten")
}

func testClassifyMixedBlock() {
    // A block with mostly ingredient lines should be classified as ingredients
    // even if it contains one cooking verb.
    let text = """
        1 cup flour
        2 eggs
        1/2 tsp salt
        3 tbsp butter
        mix well
        """
    let result = classifyZone(text)
    checkEqual(result.label, .ingredients, "Mostly ingredients wins over 1 verb")
}

func testClassifyInstructionDominant() {
    let text = """
        Preheat the oven to 375°F
        Combine the ingredients in a bowl and stir
        Pour into a greased pan and bake for 30 minutes
        Let cool before serving
        """
    let result = classifyZone(text)
    checkEqual(result.label, .instructions, "All instruction lines -> instructions")
}

func testFilterZones() {
    let blocks = [
        "Easy Chocolate Chip Cookies",
        "2 cups flour\n1 tsp vanilla\n3 eggs",
        "1. Preheat oven to 350°F\n2. Mix and bake",
        "Serves 4",
    ]
    let ingredients = filterZones(blocks, label: .ingredients)
    checkEqual(ingredients.count, 1, "filterZones finds 1 ingredient block")
    check(ingredients[0].contains("flour"), "filterZones ingredient block has flour")

    let instructions = filterZones(blocks, label: .instructions)
    checkEqual(instructions.count, 1, "filterZones finds 1 instruction block")
}

func testClassifyZonesArray() {
    let blocks = [
        "My Recipe",
        "1 cup sugar\n2 eggs",
        "Mix well and bake at 350°F for 20 minutes",
    ]
    let results = classifyZones(blocks)
    checkEqual(results.count, 3, "classifyZones returns one result per block")
    checkEqual(results[0].label, .title, "First block is title")
    checkEqual(results[1].label, .ingredients, "Second block is ingredients")
    checkEqual(results[2].label, .instructions, "Third block is instructions")
}

func testZoneClassificationCodable() {
    let value = ZoneClassification(label: .ingredients, confidence: 0.85)
    checkCodableRoundTrip(value, "ZoneClassification Codable round-trip")
}

func testZoneLabelCodable() {
    // Verify all labels round-trip correctly.
    for label in [ZoneLabel.title, .ingredients, .instructions, .metadata, .handwritten, .other] {
        let value = ZoneClassification(label: label, confidence: 0.5)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        do {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(ZoneClassification.self, from: data)
            check(decoded.label == label, "ZoneLabel.\(label.rawValue) round-trips")
        } catch {
            check(false, "ZoneLabel.\(label.rawValue) encode/decode failed: \(error)")
        }
    }
}

// MARK: - Test Runner

func runZoneClassifierTests() -> Bool {
    print("\n=== Zone Classifier Tests ===")

    testClassifyIngredients()
    testClassifyInstructions()
    testClassifyTitle()
    testClassifySectionHeader()
    testClassifyMetadata()
    testClassifyJunk()
    testClassifyEmpty()
    testClassifyHandwritingContent()
    testClassifyMixedBlock()
    testClassifyInstructionDominant()
    testFilterZones()
    testClassifyZonesArray()
    testZoneClassificationCodable()
    testZoneLabelCodable()

    return printTestSummary("Zone Classifier Tests")
}
