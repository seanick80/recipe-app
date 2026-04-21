import Foundation

// MARK: - Shopping List Line Parser Tests

func testParseBasicVariants() {
    // Data-driven: (input, expectedQty, expectedUnit, expectedName)
    let cases: [(String, Double, String, String)] = [
        ("milk", 1, "", "milk"),
        ("2 bananas", 2, "", "bananas"),
        ("2 cans tomatoes", 2, "can", "tomatoes"),
        ("1 lb chicken breast", 1, "lb", "chicken breast"),
        ("1/2 lb ground beef", 0.5, "lb", "ground beef"),
        ("2 pounds chicken", 2, "lb", "chicken"),
        ("500 g chicken breast", 500, "g", "chicken breast"),
        ("250 ml milk", 250, "ml", "milk"),
    ]
    for (input, qty, unit, name) in cases {
        let r = parseListLine(input)!
        checkEqual(r.quantity, qty, "'\(input)' qty")
        checkEqual(r.unit, unit, "'\(input)' unit")
        checkEqual(r.name, name, "'\(input)' name")
    }
}

func testParseSpecialPrefixes() {
    // Multiplier suffix, x prefix, bullets, numbered list, checkbox
    checkEqual(parseListLine("milk x3")!.quantity, 3, "Multiplier suffix")
    checkEqual(parseListLine("2x eggs")!.quantity, 2, "X prefix")
    checkEqual(parseListLine("- eggs")!.name, "eggs", "Bullet dash")
    checkEqual(parseListLine("\u{2022} bread")!.name, "bread", "Bullet dot")
    checkEqual(parseListLine("[] bread")!.name, "bread", "Checkbox unchecked")
    checkEqual(parseListLine("[x] milk")!.name, "milk", "Checkbox checked")
    checkEqual(parseListLine("3. bananas")!.name, "bananas", "Numbered list")
}

func testParseNilCases() {
    check(parseListLine("") == nil, "Blank line nil")
    check(parseListLine("   ") == nil, "Whitespace nil")
    check(parseListLine("DAIRY") == nil, "Category header nil")
}

func testParseMultiLineText() {
    let text = "milk\n2 cans tomatoes\n- eggs\n3 lb chicken breast\n\nDAIRY\ncheese"
    let items = parseShoppingListText(text)
    checkEqual(items.count, 5, "Multi-line: 5 items")
    checkEqual(items[1].unit, "can", "Multi-line: unit parsed")
}

func testParseFusedUnits() {
    let cases: [(String, Double, String, String)] = [
        ("150g flour", 150, "g", "flour"),
        ("60ml vegetable oil", 60, "ml", "vegetable oil"),
        ("8oz cream cheese", 8, "oz", "cream cheese"),
        ("150g (1 cup) White Self Raising Flour, sifted", 150, "g", ""),
        ("375g, zucchini, grated", 375, "g", ""),
    ]
    for (input, qty, unit, _) in cases {
        let r = parseListLine(input)!
        checkEqual(r.quantity, qty, "Fused '\(input)' qty")
        checkEqual(r.unit, unit, "Fused '\(input)' unit")
    }
    // Edge cases
    let bare = parseListLine("2 g sugar")!
    checkEqual(bare.unit, "g", "Space-separated g is unit")
    let nonFused = parseListLine("grams of truth")!
    checkEqual(nonFused.unit, "g", "'grams' canonicalized to g")
}

func testCompoundFractions() {
    let cases: [(String, Double, String)] = [
        ("1 1/2 cups flour", 1.5, "cup"),
        ("1 and 1/2 cups flour", 1.5, "cup"),
        ("1\u{00BD} tbsp sugar", 1.5, "tbsp"),
        ("2\u{00BC} cups all-purpose flour", 2.25, "cup"),
    ]
    for (input, qty, unit) in cases {
        let r = parseListLine(input)!
        checkEqual(r.quantity, qty, "Compound '\(input)' qty")
        checkEqual(r.unit, unit, "Compound '\(input)' unit")
    }
}

func testTrailingPunctuation() {
    checkEqual(parseListLine("bread,")!.name, "bread", "Trailing comma stripped")
    checkEqual(parseListLine("eggs.")!.name, "eggs", "Trailing period stripped")
}

func testUnicodeFraction() {
    checkEqual(parseQuantityToken("\u{00BD}")!, 0.5, "Unicode 1/2")
}

// MARK: - Test Runner

func runListParserTests() -> Bool {
    print("\n=== List Line Parser Tests ===")

    testParseBasicVariants()
    testParseSpecialPrefixes()
    testParseNilCases()
    testParseMultiLineText()
    testParseFusedUnits()
    testCompoundFractions()
    testTrailingPunctuation()
    testUnicodeFraction()

    return printTestSummary("List Parser Tests")
}
