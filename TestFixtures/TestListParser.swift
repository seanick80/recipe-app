import Foundation

// MARK: - Shopping List Line Parser Tests

func testParseSimpleItem() {
    let result = parseListLine("milk")
    check(result != nil, "Simple item parses")
    checkEqual(result!.name, "milk", "Simple item name")
    checkEqual(result!.quantity, 1, "Simple item default quantity")
    checkEqual(result!.unit, "", "Simple item no unit")
}

func testParseQuantityPrefix() {
    let result = parseListLine("2 bananas")
    check(result != nil, "Quantity prefix parses")
    checkEqual(result!.name, "bananas", "Quantity prefix name")
    checkEqual(result!.quantity, 2, "Quantity prefix value")
}

func testParseQuantityWithUnit() {
    let result = parseListLine("2 cans tomatoes")
    check(result != nil, "Quantity with unit parses")
    checkEqual(result!.name, "tomatoes", "Qty+unit name")
    checkEqual(result!.quantity, 2, "Qty+unit quantity")
    checkEqual(result!.unit, "can", "Qty+unit canonical unit")
}

func testParsePoundUnit() {
    let result = parseListLine("1 lb chicken breast")
    check(result != nil, "Pound unit parses")
    checkEqual(result!.name, "chicken breast", "Pound unit name")
    checkEqual(result!.quantity, 1, "Pound unit quantity")
    checkEqual(result!.unit, "lb", "Pound unit canonical")
}

func testParseMultiplierSuffix() {
    let result = parseListLine("milk x3")
    check(result != nil, "Multiplier suffix parses")
    checkEqual(result!.name, "milk", "Multiplier suffix name")
    checkEqual(result!.quantity, 3, "Multiplier suffix quantity")
}

func testParseXPrefix() {
    let result = parseListLine("2x eggs")
    check(result != nil, "X prefix parses")
    checkEqual(result!.name, "eggs", "X prefix name")
    checkEqual(result!.quantity, 2, "X prefix quantity")
}

func testParseBulletPrefix() {
    let result = parseListLine("- eggs")
    check(result != nil, "Bullet prefix parses")
    checkEqual(result!.name, "eggs", "Bullet dash name")

    let result2 = parseListLine("• bread")
    check(result2 != nil, "Bullet dot parses")
    checkEqual(result2!.name, "bread", "Bullet dot name")

    let result3 = parseListLine("* cheese")
    check(result3 != nil, "Bullet star parses")
    checkEqual(result3!.name, "cheese", "Bullet star name")
}

func testParseNumberedList() {
    let result = parseListLine("3. bananas")
    check(result != nil, "Numbered list parses")
    checkEqual(result!.name, "bananas", "Numbered list name")
    checkEqual(result!.quantity, 3, "Numbered list uses number as quantity")
}

func testParseBlankLine() {
    check(parseListLine("") == nil, "Blank line returns nil")
    check(parseListLine("   ") == nil, "Whitespace line returns nil")
}

func testParseCategoryHeader() {
    check(parseListLine("DAIRY") == nil, "All-caps header returns nil")
    check(parseListLine("PRODUCE") == nil, "PRODUCE header returns nil")
}

func testParseFraction() {
    let result = parseListLine("1/2 lb ground beef")
    check(result != nil, "Fraction parses")
    checkEqual(result!.quantity, 0.5, "Fraction quantity")
    checkEqual(result!.unit, "lb", "Fraction unit")
    checkEqual(result!.name, "ground beef", "Fraction name")
}

func testParseUnicodeFraction() {
    let result = parseQuantityToken("½")
    check(result != nil, "Unicode fraction parses")
    checkEqual(result!, 0.5, "Unicode ½ = 0.5")
}

func testParseCheckboxPrefix() {
    let result = parseListLine("[] bread")
    check(result != nil, "Unchecked checkbox parses")
    checkEqual(result!.name, "bread", "Unchecked checkbox name")

    let result2 = parseListLine("[x] milk")
    check(result2 != nil, "Checked checkbox parses")
    checkEqual(result2!.name, "milk", "Checked checkbox name")
}

func testParseMultiLineText() {
    let text = """
        milk
        2 cans tomatoes
        - eggs
        3 lb chicken breast

        DAIRY
        cheese
        """
    let items = parseShoppingListText(text)
    checkEqual(items.count, 5, "Multi-line: 5 items (blank + header skipped)")
    checkEqual(items[0].name, "milk", "Multi-line first item")
    checkEqual(items[1].name, "tomatoes", "Multi-line second item")
    checkEqual(items[1].quantity, 2, "Multi-line second quantity")
    checkEqual(items[1].unit, "can", "Multi-line second unit")
}

func testParseTrailingPunctuation() {
    let result = parseListLine("bread,")
    check(result != nil, "Trailing comma stripped")
    checkEqual(result!.name, "bread", "Trailing comma name clean")

    let result2 = parseListLine("eggs.")
    check(result2 != nil, "Trailing period stripped")
    checkEqual(result2!.name, "eggs", "Trailing period name clean")
}

func testParseUnitVariants() {
    // Test plural → canonical normalization
    let r1 = parseListLine("2 pounds chicken")
    checkEqual(r1!.unit, "lb", "pounds → lb")

    let r2 = parseListLine("3 bottles water")
    checkEqual(r2!.unit, "bottle", "bottles → bottle")

    let r3 = parseListLine("1 dozen eggs")
    checkEqual(r3!.unit, "dozen", "dozen stays dozen")

    let r4 = parseListLine("2 bags rice")
    checkEqual(r4!.unit, "bag", "bags → bag")
}

// MARK: - Fused Quantity+Unit (GM-6)
//
// Recipes commonly glue the number and unit together ("150g flour",
// "60ml oil", "200g bacon") — the old parser defaulted these to
// quantity=1 and jammed the fused token into the name.

func testParseFusedGrams() {
    let r = parseListLine("150g flour")
    check(r != nil, "Fused grams parses")
    checkEqual(r!.quantity, 150, "Fused grams quantity")
    checkEqual(r!.unit, "g", "Fused grams unit")
    checkEqual(r!.name, "flour", "Fused grams name")
}

func testParseFusedMilliliters() {
    let r = parseListLine("60ml vegetable oil")
    check(r != nil, "Fused ml parses")
    checkEqual(r!.quantity, 60, "Fused ml quantity")
    checkEqual(r!.unit, "ml", "Fused ml unit")
    checkEqual(r!.name, "vegetable oil", "Fused ml name")
}

func testParseFusedWithAlternateUnitInParens() {
    // Real-world zucchini-slice recipe line: "150g (1 cup) White Self Raising Flour, sifted"
    let r = parseListLine("150g (1 cup) White Self Raising Flour, sifted")
    check(r != nil, "Fused+paren parses")
    checkEqual(r!.quantity, 150, "Fused+paren quantity picks outer metric value")
    checkEqual(r!.unit, "g", "Fused+paren unit is g, not cup")
    // The alternate unit in parens stays in the name — acceptable; better than
    // dropping the "1 cup" hint entirely.
    check(
        r!.name.contains("White Self Raising Flour"),
        "Fused+paren name preserves the actual ingredient"
    )
}

func testParseFusedKg() {
    let r = parseListLine("1.5kg potatoes")
    check(r != nil, "Fused kg parses decimals")
    checkEqual(r!.quantity, 1.5, "Fused kg decimal quantity")
    checkEqual(r!.unit, "kg", "Fused kg unit")
}

func testParseFusedOz() {
    let r = parseListLine("8oz cream cheese")
    check(r != nil, "Fused oz parses")
    checkEqual(r!.quantity, 8, "Fused oz quantity")
    checkEqual(r!.unit, "oz", "Fused oz unit")
    checkEqual(r!.name, "cream cheese", "Fused oz name")
}

func testParseBareNumberStillWinsOverFused() {
    // "2g" would fuse-parse as qty=2, unit=g — but the space-separated
    // "2 g something" case is unaffected.
    let r = parseListLine("2 g sugar")
    check(r != nil, "Bare 2 + g token still works")
    checkEqual(r!.quantity, 2, "Bare 2 quantity")
    // "g" is not in knownUnits (short-form not tracked there), so it
    // lands as part of the name. That's the same behavior as before —
    // important that fused-unit logic didn't disturb it.
    checkEqual(r!.name, "g sugar", "Space-separated short unit unchanged")
}

func testParseFusedIgnoredWhenNotFused() {
    // Token "grams" should not be treated as a unit.
    let r = parseListLine("grams of truth")
    check(r != nil, "Non-fused word starting with g parses")
    checkEqual(r!.quantity, 1, "Non-fused quantity defaults to 1")
    checkEqual(r!.unit, "", "Non-fused has no unit")
    checkEqual(r!.name, "grams of truth", "Non-fused name preserved")
}

func testParseFusedWithTrailingPunctuation() {
    // OCR / comma-separated lists often stick punctuation on the quantity.
    let r = parseListLine("375g, zucchini, grated")
    check(r != nil, "Fused+trailing comma parses")
    checkEqual(r!.quantity, 375, "Fused+comma quantity")
    checkEqual(r!.unit, "g", "Fused+comma unit")
    check(r!.name.contains("zucchini"), "Fused+comma name preserved")
}

// MARK: - Test Runner

func runListParserTests() -> Bool {
    print("\n=== List Line Parser Tests ===")

    testParseSimpleItem()
    testParseQuantityPrefix()
    testParseQuantityWithUnit()
    testParsePoundUnit()
    testParseMultiplierSuffix()
    testParseXPrefix()
    testParseBulletPrefix()
    testParseNumberedList()
    testParseBlankLine()
    testParseCategoryHeader()
    testParseFraction()
    testParseUnicodeFraction()
    testParseCheckboxPrefix()
    testParseMultiLineText()
    testParseTrailingPunctuation()
    testParseUnitVariants()
    testParseFusedGrams()
    testParseFusedMilliliters()
    testParseFusedWithAlternateUnitInParens()
    testParseFusedKg()
    testParseFusedOz()
    testParseBareNumberStillWinsOverFused()
    testParseFusedIgnoredWhenNotFused()
    testParseFusedWithTrailingPunctuation()

    return printTestSummary("List Parser Tests")
}
