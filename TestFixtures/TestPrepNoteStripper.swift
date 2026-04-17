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

    let result2 = stripPrepNotes("Carrot, Peeled, Diced")
    checkEqual(result2.name, "Carrot", "Multiple prep segments: name")
    check(result2.prep.contains("peeled"), "Multiple prep segments: has peeled")
    check(result2.prep.contains("diced"), "Multiple prep segments: has diced")
}

func testStripLeadingSizeAdjective() {
    let large = stripPrepNotes("Large Onion, Finely Chopped")
    checkEqual(large.name, "Onion", "Large size + prep: name")
    checkEqual(large.sizeAdjective, "large", "Large size: extracted")

    let medium = stripPrepNotes("Medium Potato, Diced")
    checkEqual(medium.sizeAdjective, "medium", "Medium size: extracted")

    let small = stripPrepNotes("Small Carrot, Peeled")
    checkEqual(small.sizeAdjective, "small", "Small size: extracted")
}

func testNoStripSizeAlone() {
    let result = stripPrepNotes("Large")
    checkEqual(result.name, "Large", "Size alone: no strip")
    checkEqual(result.sizeAdjective, "", "Size alone: no size extracted")
}

func testParenQuantityPrefix() {
    let result = stripPrepNotes("(1 Cup) White Self Raising Flour, Sifted")
    checkEqual(result.name, "White Self Raising Flour", "Paren quantity: name")
    checkEqual(result.prep, "sifted", "Paren quantity: prep")

    let result2 = stripPrepNotes("(2) Large Eggs")
    checkEqual(result2.name, "Eggs", "Paren then size: name")
    checkEqual(result2.sizeAdjective, "large", "Paren then size: size")
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
}

func testEmptyAndWhitespace() {
    let empty = stripPrepNotes("")
    checkEqual(empty.name, "", "Empty: name empty")

    let ws = stripPrepNotes("   ")
    checkEqual(ws.name, "", "Whitespace: name empty")
}

func testNonPrepCommaSegment() {
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

func runPrepNoteStripperTests() -> Bool {
    print("\n=== PrepNoteStripper Tests ===")

    testStripBasicCommaPrep()
    testStripMultipleCommaPreps()
    testStripLeadingSizeAdjective()
    testNoStripSizeAlone()
    testParenQuantityPrefix()
    testRindlessBacon()
    testNoPrep()
    testEmptyAndWhitespace()
    testNonPrepCommaSegment()
    testCompoundNameWithPrep()
    testCaseInsensitivity()
    testAtRoomTemperature()

    return printTestSummary("PrepNoteStripper Tests")
}
