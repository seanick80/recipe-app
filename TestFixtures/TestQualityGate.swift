import Foundation

// MARK: - Quality Gate Tests

// MARK: Image Quality Assessment

func testQualityAcceptableImage() {
    let lines = [
        OCRLine(text: "2 cups flour", confidence: 0.92),
        OCRLine(text: "1 tsp vanilla", confidence: 0.88),
        OCRLine(text: "3 eggs", confidence: 0.95),
        OCRLine(text: "Preheat oven", confidence: 0.90),
    ]
    let result = assessImageQuality(lines: lines)
    check(result.isAcceptable, "High-confidence image is acceptable")
    check(!result.shouldRetake, "Should not retake good image")
    check(result.medianConfidence > 0.85, "Median confidence > 85%")
}

func testQualityBlurryImage() {
    let lines = [
        OCRLine(text: "flour", confidence: 0.20),
        OCRLine(text: "eggs", confidence: 0.15),
        OCRLine(text: "sugar", confidence: 0.30),
        OCRLine(text: "bake", confidence: 0.25),
    ]
    let result = assessImageQuality(lines: lines)
    check(!result.isAcceptable, "Low-confidence image is not acceptable")
    check(result.shouldRetake, "Should retake blurry image")
    check(!result.reason.isEmpty, "Has rejection reason")
}

func testQualityNoText() {
    let result = assessImageQuality(lines: [])
    check(!result.isAcceptable, "No-text image is not acceptable")
    check(result.reason.contains("No text"), "Reason mentions no text")
}

func testQualityMixedConfidence() {
    let lines = [
        OCRLine(text: "flour", confidence: 0.90),
        OCRLine(text: "eggs", confidence: 0.85),
        OCRLine(text: "sugar", confidence: 0.92),
        OCRLine(text: "smudge", confidence: 0.20),
    ]
    let result = assessImageQuality(lines: lines)
    check(result.isAcceptable, "Mostly good image is acceptable")
    check(result.lowConfidenceRatio < 0.5, "Low confidence ratio under 50%")
}

func testQualityMostlyBad() {
    let lines = [
        OCRLine(text: "a", confidence: 0.10),
        OCRLine(text: "b", confidence: 0.20),
        OCRLine(text: "c", confidence: 0.15),
        OCRLine(text: "ok", confidence: 0.80),
    ]
    let result = assessImageQuality(lines: lines)
    check(!result.isAcceptable, "Mostly bad image is not acceptable")
    check(result.lowConfidenceRatio > 0.6, "Low confidence ratio > 60%")
}

// MARK: Handwriting Detection

func testHandwrittenLowConfidenceInMargin() {
    let line = OCRLine(
        text: "x2",
        confidence: 0.20,
        boundingBox: NormalizedBox(x: 0.01, y: 0.5, width: 0.05, height: 0.02)
    )
    let result = isLikelyHandwritten(
        line: line,
        medianConfidence: 0.85,
        medianHeight: 0.03
    )
    check(result, "Low confidence + margin + below median = handwritten")
}

func testPrintedTextNotHandwritten() {
    let line = OCRLine(
        text: "2 cups flour",
        confidence: 0.90,
        boundingBox: NormalizedBox(x: 0.1, y: 0.3, width: 0.3, height: 0.03)
    )
    let result = isLikelyHandwritten(
        line: line,
        medianConfidence: 0.85,
        medianHeight: 0.03
    )
    check(!result, "Good confidence printed text is NOT handwritten")
}

func testLowConfidenceAloneNotHandwritten() {
    let line = OCRLine(
        text: "sugar",
        confidence: 0.25,
        boundingBox: NormalizedBox(x: 0.2, y: 0.5, width: 0.2, height: 0.03)
    )
    let result = isLikelyHandwritten(
        line: line,
        medianConfidence: 0.85,
        medianHeight: 0.03
    )
    check(!result, "Low confidence alone is NOT enough for handwritten (needs 3 signals)")
}

func testHandwrittenOversizedInMargin() {
    let line = OCRLine(
        text: "NOTE",
        confidence: 0.30,
        boundingBox: NormalizedBox(x: 0.02, y: 0.8, width: 0.1, height: 0.08)
    )
    let result = isLikelyHandwritten(
        line: line,
        medianConfidence: 0.80,
        medianHeight: 0.03
    )
    check(result, "Low confidence + margin + oversized = handwritten")
}

// MARK: Separate Handwritten

func testSeparateHandwritten() {
    let lines = [
        OCRLine(
            text: "2 cups flour",
            confidence: 0.90,
            boundingBox: NormalizedBox(x: 0.1, y: 0.3, width: 0.3, height: 0.03)
        ),
        OCRLine(
            text: "1 tsp salt",
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
    checkEqual(printed.count, 2, "2 printed lines separated")
    checkEqual(handwritten.count, 1, "1 handwritten line separated")

    // Empty input
    let (ep, eh) = separateHandwritten(lines: [])
    checkEqual(ep.count + eh.count, 0, "Empty input: no lines")
}

// MARK: Block Grouping

func testGroupLinesIntoBlocks() {
    // Empty
    checkEqual(groupLinesIntoBlocks([]).count, 0, "Empty input: no blocks")

    // Single line
    let single = OCRLine(
        text: "Hello",
        confidence: 0.9,
        boundingBox: NormalizedBox(x: 0.1, y: 0.3, width: 0.2, height: 0.03)
    )
    let singleBlocks = groupLinesIntoBlocks([single])
    checkEqual(singleBlocks.count, 1, "Single line: one block")
    checkEqual(singleBlocks[0].count, 1, "Block has one line")

    // Adjacent lines merge
    let adjacent = [
        OCRLine(text: "a", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.30, width: 0.2, height: 0.03)),
        OCRLine(text: "b", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.34, width: 0.2, height: 0.03)),
        OCRLine(text: "c", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.38, width: 0.2, height: 0.03)),
    ]
    let adjBlocks = groupLinesIntoBlocks(adjacent)
    checkEqual(adjBlocks.count, 1, "Adjacent lines merge into one block")
    checkEqual(adjBlocks[0].count, 3, "Block contains all three lines")
}

func testGroupLinesLargeGapAndSort() {
    // Two tight clusters separated by a large vertical gap
    let lines = [
        OCRLine(text: "bottom", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.80, width: 0.3, height: 0.03)),
        OCRLine(text: "top", confidence: 0.9, boundingBox: NormalizedBox(x: 0.1, y: 0.10, width: 0.3, height: 0.03)),
    ]
    let blocks = groupLinesIntoBlocks(lines)
    checkEqual(blocks.count, 2, "Large gap splits into two blocks")
    checkEqual(blocks[0][0].text, "top", "First block is topmost line (sorted by Y)")
    checkEqual(blocks[1][0].text, "bottom", "Second block is bottommost line")
}

// MARK: Data Types

func testOCRLineCodable() {
    let line = OCRLine(
        text: "test",
        confidence: 0.85,
        boundingBox: NormalizedBox(x: 0.1, y: 0.2, width: 0.3, height: 0.04)
    )
    checkCodableRoundTrip(line, "OCRLine Codable round-trip")
}

func testNormalizedBoxProperties() {
    let box = NormalizedBox(x: 0.1, y: 0.2, width: 0.3, height: 0.05)
    checkEqual(box.midX, 0.25, "NormalizedBox midX")
    checkEqual(box.maxY, 0.25, "NormalizedBox maxY")
}

func testImageQualityAssessmentCodable() {
    let assessment = ImageQualityAssessment(
        medianConfidence: 0.85,
        lowConfidenceRatio: 0.1,
        isAcceptable: true,
        reason: ""
    )
    checkCodableRoundTrip(assessment, "ImageQualityAssessment Codable round-trip")
}

// MARK: Section Header Detection

func testSectionHeaderIngredients() {
    let ingredientHeaders = ["Ingredients", "INGREDIENTS", "ingredient list"]
    for header in ingredientHeaders {
        checkEqual(sectionFromHeader(header), .ingredients, "'\(header)' -> ingredients")
    }
}

func testSectionHeaderInstructions() {
    let instructionHeaders = ["Method", "Directions", "Step 1"]
    for header in instructionHeaders {
        checkEqual(sectionFromHeader(header), .instructions, "'\(header)' -> instructions")
    }
}

func testSectionHeaderNonHeader() {
    check(sectionFromHeader("5 Free Range Eggs") == nil, "ingredient line is not a header")
    check(sectionFromHeader("") == nil, "empty line is not a header")
    check(sectionFromHeader("Key ingredients in zucchini slice") == nil, "sentence is not a header")
}

// MARK: Metadata Junk Filter

func testMetadataJunk() {
    let junk = ["270\u{2022}", "360.", "160g.", "x1,8", "\u{2022}", "  "]
    for text in junk {
        check(isLikelyMetadataJunk(text), "'\(text)' is junk")
    }
}

func testMetadataNotJunk() {
    let notJunk = [
        "5 Free Range Eggs",
        "200g rindless bacon, chopped",
        "Step 2",
        "1 large onion, finely chopped",
    ]
    for text in notJunk {
        check(!isLikelyMetadataJunk(text), "'\(text)' is not junk")
    }
}

// MARK: - Test Runner

func runQualityGateTests() -> Bool {
    print("\n=== Quality Gate Tests ===")

    testQualityAcceptableImage()
    testQualityBlurryImage()
    testQualityNoText()
    testQualityMixedConfidence()
    testQualityMostlyBad()
    testHandwrittenLowConfidenceInMargin()
    testPrintedTextNotHandwritten()
    testLowConfidenceAloneNotHandwritten()
    testHandwrittenOversizedInMargin()
    testSeparateHandwritten()
    testGroupLinesIntoBlocks()
    testGroupLinesLargeGapAndSort()
    testOCRLineCodable()
    testNormalizedBoxProperties()
    testImageQualityAssessmentCodable()
    testSectionHeaderIngredients()
    testSectionHeaderInstructions()
    testSectionHeaderNonHeader()
    testMetadataJunk()
    testMetadataNotJunk()

    return printTestSummary("Quality Gate Tests")
}
