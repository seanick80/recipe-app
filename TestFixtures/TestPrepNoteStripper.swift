import Foundation

// MARK: - PrepNoteStripper Tests

func testStripBasicCommaPrep() {
    let result = stripPrepNotes("Onion, Finely Chopped")
    checkEqual(result.name, "Onion", "Basic comma prep: name")
    checkEqual(result.prep, "finely chopped", "Basic comma prep: prep")
}

func testStripMultipleCommaPreps() {
    let result = stripPrepNotes("Zucchini, Grated, Excess Moisture Squeezed Out")
    checkEqual(result.name, "Zucchini", "Multiple comma preps: name")
    check(result.prep.contains("grated"), "Multiple comma preps: contains grated")
}

func testStripLeadingSizeAdjective() {
    let result = stripPrepNotes("Large Onion, Finely Chopped")
    checkEqual(result.name, "Onion", "Size adjective + prep: name")
    checkEqual(result.sizeAdjective, "large", "Size adjective + prep: size")
    checkEqual(result.prep, "finely chopped", "Size adjective + prep: prep")
}

func testStripMediumSize() {
    let result = stripPrepNotes("Medium Potato, Diced")
    checkEqual(result.name, "Potato", "Medium size: name")
    checkEqual(result.sizeAdjective, "medium", "Medium size: size")
    checkEqual(result.prep, "diced", "Medium size: prep")
}

func testStripSmallSize() {
    let result = stripPrepNotes("Small Carrot, Peeled")
    checkEqual(result.name, "Carrot", "Small size: name")
    checkEqual(result.sizeAdjective, "small", "Small size: size")
}

func testNoStripSizeAlone() {
    // "Large" alone should not be stripped (nothing left)
    let result = stripPrepNotes("Large")
    checkEqual(result.name, "Large", "Size alone: no strip")
    checkEqual(result.sizeAdjective, "", "Size alone: no size extracted")
}

func testParenQuantityPrefix() {
    let result = stripPrepNotes("(1 Cup) White Self Raising Flour, Sifted")
    checkEqual(result.name, "White Self Raising Flour", "Paren quantity: name")
    checkEqual(result.prep, "sifted", "Paren quantity: prep")
}

func testRindlessBacon() {
    let result = stripPrepNotes("Rindless Bacon, Chopped")
    checkEqual(result.name, "Rindless Bacon", "Rindless Bacon: name")
    checkEqual(result.prep, "chopped", "Rindless Bacon: prep")
}

func testNoPrep() {
    let result = stripPrepNotes("Chicken Breast")
    checkEqual(result.name, "Chicken Breast", "No prep: name unchanged")
    checkEqual(result.prep, "", "No prep: prep empty")
    checkEqual(result.sizeAdjective, "", "No prep: no size")
}

func testEmptyString() {
    let result = stripPrepNotes("")
    checkEqual(result.name, "", "Empty: name empty")
    checkEqual(result.prep, "", "Empty: prep empty")
}

func testWhitespaceOnly() {
    let result = stripPrepNotes("   ")
    checkEqual(result.name, "", "Whitespace: name empty")
}

func testSinglePrepWord() {
    let result = stripPrepNotes("Garlic, Minced")
    checkEqual(result.name, "Garlic", "Single prep word: name")
    checkEqual(result.prep, "minced", "Single prep word: prep")
}

func testMultiplePrepSegments() {
    let result = stripPrepNotes("Carrot, Peeled, Diced")
    checkEqual(result.name, "Carrot", "Multiple prep segments: name")
    check(result.prep.contains("peeled"), "Multiple prep segments: has peeled")
    check(result.prep.contains("diced"), "Multiple prep segments: has diced")
}

func testNonPrepCommaSegment() {
    // "Self Raising" is not a prep word — should be kept
    let result = stripPrepNotes("White Self Raising Flour")
    checkEqual(result.name, "White Self Raising Flour", "Non-prep segment preserved")
}

func testCompoundNameWithPrep() {
    let result = stripPrepNotes("Fresh Mozzarella, Sliced")
    checkEqual(result.name, "Fresh Mozzarella", "Compound name: name")
    checkEqual(result.prep, "sliced", "Compound name: prep")
}

func testCaseInsensitivity() {
    let result = stripPrepNotes("onion, FINELY CHOPPED")
    checkEqual(result.name, "onion", "Case insensitive: name")
    check(!result.prep.isEmpty, "Case insensitive: prep extracted")
}

func testAtRoomTemperature() {
    let result = stripPrepNotes("Butter, At Room Temperature")
    checkEqual(result.name, "Butter", "Room temp phrase: name")
    check(result.prep.contains("at room temperature"), "Room temp phrase: prep")
}

func testForGarnish() {
    let result = stripPrepNotes("Parsley, Chopped, For Garnish")
    checkEqual(result.name, "Parsley", "For garnish: name")
    check(result.prep.contains("chopped"), "For garnish: contains chopped")
}

func testLeadingParenThenSize() {
    let result = stripPrepNotes("(2) Large Eggs")
    checkEqual(result.name, "Eggs", "Paren then size: name")
    checkEqual(result.sizeAdjective, "large", "Paren then size: size")
}

func testComplexIngredient() {
    let result = stripPrepNotes("Zucchini, Grated, Excess Moisture Squeezed Out")
    checkEqual(result.name, "Zucchini", "Complex zucchini: name")
}

func runPrepNoteStripperTests() -> Bool {
    print("\n=== PrepNoteStripper Tests ===")

    testStripBasicCommaPrep()
    testStripMultipleCommaPreps()
    testStripLeadingSizeAdjective()
    testStripMediumSize()
    testStripSmallSize()
    testNoStripSizeAlone()
    testParenQuantityPrefix()
    testRindlessBacon()
    testNoPrep()
    testEmptyString()
    testWhitespaceOnly()
    testSinglePrepWord()
    testMultiplePrepSegments()
    testNonPrepCommaSegment()
    testCompoundNameWithPrep()
    testCaseInsensitivity()
    testAtRoomTemperature()
    testForGarnish()
    testLeadingParenThenSize()
    testComplexIngredient()

    return printTestSummary("PrepNoteStripper Tests")
}
