import Foundation

// MARK: - PrepNoteStripper Tests

func testStripPrepNotes() {
    // Basic comma prep
    let basic = stripPrepNotes("Onion, Finely Chopped")
    checkEqual(basic.name, "Onion", "Basic: name")
    checkEqual(basic.prep, "finely chopped", "Basic: prep")

    // Multiple comma preps
    let multi = stripPrepNotes("Zucchini, Grated, Excess Moisture Squeezed Out")
    checkEqual(multi.name, "Zucchini", "Multiple preps: name")
    check(multi.prep.contains("grated"), "Multiple preps: has grated")

    // No prep
    let clean = stripPrepNotes("Chicken Breast")
    checkEqual(clean.name, "Chicken Breast", "No prep: unchanged")
    checkEqual(clean.prep, "", "No prep: empty")
}

func testSizeAdjectives() {
    let large = stripPrepNotes("Large Onion, Finely Chopped")
    checkEqual(large.name, "Onion", "Large: name")
    checkEqual(large.sizeAdjective, "large", "Large: extracted")

    // Size alone: no strip
    let sizeAlone = stripPrepNotes("Large")
    checkEqual(sizeAlone.name, "Large", "Size alone: not stripped")
}

func testParenQuantityAndEdgeCases() {
    let paren = stripPrepNotes("(1 Cup) White Self Raising Flour, Sifted")
    checkEqual(paren.name, "White Self Raising Flour", "Paren qty: name")
    checkEqual(paren.prep, "sifted", "Paren qty: prep")

    let empty = stripPrepNotes("")
    checkEqual(empty.name, "", "Empty input")

    let roomTemp = stripPrepNotes("Butter, At Room Temperature")
    checkEqual(roomTemp.name, "Butter", "Room temp: name")
    check(roomTemp.prep.contains("at room temperature"), "Room temp: prep")
}

func runPrepNoteStripperTests() -> Bool {
    print("\n=== PrepNoteStripper Tests ===")

    testStripPrepNotes()
    testSizeAdjectives()
    testParenQuantityAndEdgeCases()

    return printTestSummary("PrepNoteStripper Tests")
}
