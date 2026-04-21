import Foundation

// MARK: - Quality Gate Tests

func testImageQualityAssessment() {
    // Good image
    let good = assessImageQuality(lines: [
        OCRLine(text: "2 cups flour", confidence: 0.92),
        OCRLine(text: "1 tsp vanilla", confidence: 0.88),
        OCRLine(text: "3 eggs", confidence: 0.95),
    ])
    check(good.isAcceptable, "High-confidence image acceptable")
    check(!good.shouldRetake, "Good image: no retake")

    // Blurry image
    let blurry = assessImageQuality(lines: [
        OCRLine(text: "flour", confidence: 0.20),
        OCRLine(text: "eggs", confidence: 0.15),
        OCRLine(text: "sugar", confidence: 0.30),
    ])
    check(!blurry.isAcceptable, "Low-confidence not acceptable")

    // No text
    let empty = assessImageQuality(lines: [])
    check(!empty.isAcceptable, "No-text not acceptable")
    check(empty.reason.contains("No text"), "No-text reason")
}

func testHandwrittenDetection() {
    let medianConf = 0.85
    let medianH = 0.03

    // Handwritten: low conf + margin + small
    let hw = OCRLine(
        text: "x2",
        confidence: 0.20,
        boundingBox: NormalizedBox(x: 0.01, y: 0.5, width: 0.05, height: 0.02)
    )
    check(
        isLikelyHandwritten(line: hw, medianConfidence: medianConf, medianHeight: medianH),
        "Low conf + margin + small = handwritten"
    )

    // Printed: good confidence
    let printed = OCRLine(
        text: "2 cups flour",
        confidence: 0.90,
        boundingBox: NormalizedBox(x: 0.1, y: 0.3, width: 0.3, height: 0.03)
    )
    check(
        !isLikelyHandwritten(line: printed, medianConfidence: medianConf, medianHeight: medianH),
        "Good conf printed is NOT handwritten"
    )

    // Low conf alone not enough
    let lowOnly = OCRLine(
        text: "sugar",
        confidence: 0.25,
        boundingBox: NormalizedBox(x: 0.2, y: 0.5, width: 0.2, height: 0.03)
    )
    check(
        !isLikelyHandwritten(line: lowOnly, medianConfidence: medianConf, medianHeight: medianH),
        "Low conf alone NOT handwritten"
    )
}

func testSeparateHandwritten() {
    let lines = [
        OCRLine(
            text: "flour",
            confidence: 0.90,
            boundingBox: NormalizedBox(x: 0.1, y: 0.3, width: 0.3, height: 0.03)
        ),
        OCRLine(
            text: "salt",
            confidence: 0.88,
            boundingBox: NormalizedBox(x: 0.1, y: 0.35, width: 0.25, height: 0.03)
        ),
        OCRLine(
            text: "x1.5",
            confidence: 0.15,
            boundingBox: NormalizedBox(x: 0.01, y: 0.32, width: 0.06, height: 0.01)
        ),
    ]
    let (printed, handwritten) = separateHandwritten(lines: lines)
    checkEqual(printed.count, 2, "2 printed separated")
    checkEqual(handwritten.count, 1, "1 handwritten separated")
}

func testBlockGrouping() {
    checkEqual(groupLinesIntoBlocks([]).count, 0, "Empty: no blocks")

    let adjacent = [
        OCRLine(text: "a", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.30, width: 0.2, height: 0.03)),
        OCRLine(text: "b", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.34, width: 0.2, height: 0.03)),
    ]
    checkEqual(groupLinesIntoBlocks(adjacent).count, 1, "Adjacent merge into one block")

    let separated = [
        OCRLine(text: "top", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.10, width: 0.3, height: 0.03)),
        OCRLine(text: "bottom", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.80, width: 0.3, height: 0.03)),
    ]
    checkEqual(groupLinesIntoBlocks(separated).count, 2, "Large gap splits into two blocks")
}

func testSectionHeaders() {
    checkEqual(sectionFromHeader("Ingredients"), .ingredients, "Ingredients header")
    checkEqual(sectionFromHeader("Method"), .instructions, "Method header")
    check(sectionFromHeader("5 Free Range Eggs") == nil, "Ingredient line not header")
    check(sectionFromHeader("") == nil, "Empty not header")
}

func testMetadataJunk() {
    check(isLikelyMetadataJunk("270\u{2022}"), "Junk: number+bullet")
    check(!isLikelyMetadataJunk("5 Free Range Eggs"), "Not junk: ingredient")
}

func testIngredientAndInstructionDetection() {
    check(looksLikeNumberedInstruction("1 Combine flours; whisk in eggs"), "Numbered instruction")
    check(!looksLikeNumberedInstruction("2 eggs"), "Short ingredient not instruction")
    check(looksLikeIngredientStart("2 tablespoons vegetable oil"), "Tablespoon ingredient")
    check(!looksLikeIngredientStart("Preheat oven to 180\u{00B0}C"), "Instruction rejected")
}

func testDataTypeCodable() {
    checkCodableRoundTrip(
        OCRLine(
            text: "test",
            confidence: 0.85,
            boundingBox: NormalizedBox(x: 0.1, y: 0.2, width: 0.3, height: 0.04)
        ),
        "OCRLine Codable"
    )
}

// MARK: - Test Runner

func runQualityGateTests() -> Bool {
    print("\n=== Quality Gate Tests ===")

    testImageQualityAssessment()
    testHandwrittenDetection()
    testSeparateHandwritten()
    testBlockGrouping()
    testSectionHeaders()
    testMetadataJunk()
    testIngredientAndInstructionDetection()
    testDataTypeCodable()

    return printTestSummary("Quality Gate Tests")
}
