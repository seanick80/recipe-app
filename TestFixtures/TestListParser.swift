import Foundation

// MARK: - Shopping List Line Parser Tests

func testParseSimpleItem() {
    let result = parseListLine("milk")!
    checkEqual(result.name, "milk", "Simple item name")
    checkEqual(result.quantity, 1, "Simple item default quantity")
    checkEqual(result.unit, "", "Simple item no unit")
}

func testParseQuantityPrefix() {
    let result = parseListLine("2 bananas")!
    checkEqual(result.name, "bananas", "Quantity prefix name")
    checkEqual(result.quantity, 2, "Quantity prefix value")
}

func testParseQuantityWithUnit() {
    let result = parseListLine("2 cans tomatoes")!
    checkEqual(result.name, "tomatoes", "Qty+unit name")
    checkEqual(result.quantity, 2, "Qty+unit quantity")
    checkEqual(result.unit, "can", "Qty+unit canonical unit")
}

func testParsePoundUnit() {
    let result = parseListLine("1 lb chicken breast")!
    checkEqual(result.name, "chicken breast", "Pound unit name")
    checkEqual(result.unit, "lb", "Pound unit canonical")
}

func testParseMultiplierSuffix() {
    let result = parseListLine("milk x3")!
    checkEqual(result.name, "milk", "Multiplier suffix name")
    checkEqual(result.quantity, 3, "Multiplier suffix quantity")
}

func testParseXPrefix() {
    let result = parseListLine("2x eggs")!
    checkEqual(result.name, "eggs", "X prefix name")
    checkEqual(result.quantity, 2, "X prefix quantity")
}

func testParseBulletPrefix() {
    checkEqual(parseListLine("- eggs")!.name, "eggs", "Bullet dash name")
    checkEqual(parseListLine("\u{2022} bread")!.name, "bread", "Bullet dot name")
    checkEqual(parseListLine("* cheese")!.name, "cheese", "Bullet star name")
}

func testParseNumberedList() {
    let result = parseListLine("3. bananas")!
    checkEqual(result.name, "bananas", "Numbered list name")
    checkEqual(result.quantity, 3, "Numbered list uses number as quantity")
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
    let result = parseListLine("1/2 lb ground beef")!
    checkEqual(result.quantity, 0.5, "Fraction quantity")
    checkEqual(result.unit, "lb", "Fraction unit")
    checkEqual(result.name, "ground beef", "Fraction name")
}

func testParseUnicodeFraction() {
    checkEqual(parseQuantityToken("\u{00BD}")!, 0.5, "Unicode 1/2 = 0.5")
}

func testParseCheckboxPrefix() {
    checkEqual(parseListLine("[] bread")!.name, "bread", "Unchecked checkbox name")
    checkEqual(parseListLine("[x] milk")!.name, "milk", "Checked checkbox name")
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
    checkEqual(parseListLine("bread,")!.name, "bread", "Trailing comma stripped")
    checkEqual(parseListLine("eggs.")!.name, "eggs", "Trailing period stripped")
}

func testParseUnitVariants() {
    // Test plural -> canonical normalization (2 representative)
    let r1 = parseListLine("2 pounds chicken")
    checkEqual(r1!.unit, "lb", "pounds -> lb")

    let r2 = parseListLine("2 bags rice")
    checkEqual(r2!.unit, "bag", "bags -> bag")
}

// MARK: - Fused Quantity+Unit (GM-6)
//
// Recipes commonly glue the number and unit together ("150g flour",
// "60ml oil", "200g bacon") — the old parser defaulted these to
// quantity=1 and jammed the fused token into the name.

func testParseFusedUnits() {
    // Data-driven: (input, expectedQty, expectedUnit, expectedName)
    let cases: [(String, Double, String, String)] = [
        ("150g flour", 150, "g", "flour"),
        ("60ml vegetable oil", 60, "ml", "vegetable oil"),
        ("1.5kg potatoes", 1.5, "kg", "potatoes"),
        ("8oz cream cheese", 8, "oz", "cream cheese"),
    ]
    for (input, qty, unit, name) in cases {
        let r = parseListLine(input)!
        checkEqual(r.quantity, qty, "Fused '\(input)' quantity")
        checkEqual(r.unit, unit, "Fused '\(input)' unit")
        checkEqual(r.name, name, "Fused '\(input)' name")
    }
}

func testParseFusedWithAlternateUnitInParens() {
    let r = parseListLine("150g (1 cup) White Self Raising Flour, sifted")!
    checkEqual(r.quantity, 150, "Fused+paren quantity picks outer metric value")
    checkEqual(r.unit, "g", "Fused+paren unit is g, not cup")
    check(r.name.contains("White Self Raising Flour"), "Fused+paren name preserves ingredient")
}

func testParseBareNumberStillWinsOverFused() {
    let r = parseListLine("2 g sugar")!
    checkEqual(r.quantity, 2, "Bare 2 quantity")
    checkEqual(r.unit, "g", "Space-separated g recognized as unit")
    checkEqual(r.name, "sugar", "Space-separated g: name is remainder")
}

func testParseFusedIgnoredWhenNotFused() {
    let r = parseListLine("grams of truth")!
    checkEqual(r.quantity, 1, "Non-fused quantity defaults to 1")
    checkEqual(r.name, "of truth", "Non-fused: 'grams' consumed as unit, rest is name")
    checkEqual(r.unit, "g", "Non-fused: 'grams' canonicalized to g")
}

func testParseFusedWithTrailingPunctuation() {
    let r = parseListLine("375g, zucchini, grated")!
    checkEqual(r.quantity, 375, "Fused+comma quantity")
    checkEqual(r.unit, "g", "Fused+comma unit")
    check(r.name.contains("zucchini"), "Fused+comma name preserved")
}

// MARK: - Compound Fractions (GM-14)

func testCompoundFractions() {
    // "1 1/2 cups flour"
    let r1 = parseListLine("1 1/2 cups flour")!
    checkEqual(r1.quantity, 1.5, "Compound '1 1/2' quantity")
    checkEqual(r1.unit, "cup", "Compound '1 1/2' unit")
    checkEqual(r1.name, "flour", "Compound '1 1/2' name")

    // "2 3/4 lb chicken"
    let r2 = parseListLine("2 3/4 lb chicken")!
    checkEqual(r2.quantity, 2.75, "Compound '2 3/4' quantity")
    checkEqual(r2.unit, "lb", "Compound '2 3/4' unit")

    // "1 and 1/2 cups flour"
    let r3 = parseListLine("1 and 1/2 cups flour")!
    checkEqual(r3.quantity, 1.5, "Compound '1 and 1/2' quantity")
    checkEqual(r3.unit, "cup", "Compound '1 and 1/2' unit")
    checkEqual(r3.name, "flour", "Compound '1 and 1/2' name")

    // "1½ tbsp sugar"
    let r4 = parseListLine("1½ tbsp sugar")!
    checkEqual(r4.quantity, 1.5, "Fused '1½' quantity")
    checkEqual(r4.unit, "tbsp", "Fused '1½' unit")
    checkEqual(r4.name, "sugar", "Fused '1½' name")

    // "2¼ cups all-purpose flour" (real recipe import)
    let r5 = parseListLine("2¼ cups all-purpose flour")!
    checkEqual(r5.quantity, 2.25, "Fused '2¼' quantity")
    checkEqual(r5.unit, "cup", "Fused '2¼' unit")
    checkEqual(r5.name, "all-purpose flour", "Fused '2¼' name")

    // "1 ½ cup milk" (space between whole and unicode fraction)
    let r6 = parseListLine("1 ½ cup milk")!
    checkEqual(r6.quantity, 1.5, "Spaced '1 ½' quantity")
    checkEqual(r6.unit, "cup", "Spaced '1 ½' unit")
    checkEqual(r6.name, "milk", "Spaced '1 ½' name")
}

// MARK: - Metric Unit Tests

func testParseMetricUnits() {
    let r1 = parseListLine("500 g chicken breast")!
    checkEqual(r1.quantity, 500, "Metric g: quantity")
    checkEqual(r1.unit, "g", "Metric g: unit")
    checkEqual(r1.name, "chicken breast", "Metric g: name")

    let r2 = parseListLine("2 kg potatoes")!
    checkEqual(r2.quantity, 2, "Metric kg: quantity")
    checkEqual(r2.unit, "kg", "Metric kg: unit")
    checkEqual(r2.name, "potatoes", "Metric kg: name")

    let r3 = parseListLine("250 ml milk")!
    checkEqual(r3.quantity, 250, "Metric ml: quantity")
    checkEqual(r3.unit, "ml", "Metric ml: unit")
    checkEqual(r3.name, "milk", "Metric ml: name")

    let r4 = parseListLine("1 l water")!
    checkEqual(r4.quantity, 1, "Metric l: quantity")
    checkEqual(r4.unit, "l", "Metric l: unit")
    checkEqual(r4.name, "water", "Metric l: name")

    let r5 = parseListLine("100 grams flour")!
    checkEqual(r5.quantity, 100, "Metric grams: quantity")
    checkEqual(r5.unit, "g", "Metric grams: canonical unit")
    checkEqual(r5.name, "flour", "Metric grams: name")
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
    testParseFusedUnits()
    testParseFusedWithAlternateUnitInParens()
    testParseBareNumberStillWinsOverFused()
    testParseFusedIgnoredWhenNotFused()
    testParseFusedWithTrailingPunctuation()
    testCompoundFractions()
    testParseMetricUnits()

    return printTestSummary("List Parser Tests")
}
