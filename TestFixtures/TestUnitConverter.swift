import Foundation

// MARK: - UnitConverter Tests

/// True when `m` is non-nil, has the given unit, and a quantity within `tol`.
private func ucMatches(
    _ m: ConvertedMeasure?,
    _ quantity: Double,
    _ unit: String,
    tol: Double = 0.02
) -> Bool {
    guard let m else { return false }
    return m.unit == unit && abs(m.quantity - quantity) < tol
}

func testUnitConverterVolumeToMetric() {
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "cup", to: .metric), 240, "ml"), "1 cup → 240 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "tbsp", to: .metric), 15, "ml"), "1 tbsp → 15 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "tsp", to: .metric), 5, "ml"), "1 tsp → 5 ml")
    check(ucMatches(UnitConverter.convert(quantity: 2, unit: "cups", to: .metric), 470, "ml"), "2 cups → 470 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "fl oz", to: .metric), 30, "ml"), "1 fl oz → 30 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "gallon", to: .metric), 3.79, "L", tol: 0.05), "1 gallon → ~3.79 L")
}

func testUnitConverterWeightToMetric() {
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "lb", to: .metric), 450, "g"), "1 lb → 450 g")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "oz", to: .metric), 30, "g"), "1 oz → 30 g")
    check(ucMatches(UnitConverter.convert(quantity: 2, unit: "lb", to: .metric), 910, "g"), "2 lb → 910 g")
    check(ucMatches(UnitConverter.convert(quantity: 8, unit: "oz", to: .metric), 230, "g"), "8 oz → 230 g")
    check(ucMatches(UnitConverter.convert(quantity: 3, unit: "lb", to: .metric), 1.36, "kg", tol: 0.05), "3 lb → ~1.36 kg")
}

func testUnitConverterMetricStaysMetric() {
    check(ucMatches(UnitConverter.convert(quantity: 500, unit: "ml", to: .metric), 500, "ml", tol: 0.5), "500 ml → 500 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1500, unit: "ml", to: .metric), 1.5, "L", tol: 0.01), "1500 ml → 1.5 L")
    check(ucMatches(UnitConverter.convert(quantity: 250, unit: "g", to: .metric), 250, "g", tol: 0.5), "250 g → 250 g")
}

func testUnitConverterToImperial() {
    check(ucMatches(UnitConverter.convert(quantity: 240, unit: "ml", to: .imperial), 1.01, "cup"), "240 ml → ~1 cup")
    check(ucMatches(UnitConverter.convert(quantity: 15, unit: "ml", to: .imperial), 1.01, "tbsp"), "15 ml → ~1 tbsp")
    check(ucMatches(UnitConverter.convert(quantity: 5, unit: "ml", to: .imperial), 1.01, "tsp"), "5 ml → ~1 tsp")
    check(ucMatches(UnitConverter.convert(quantity: 1000, unit: "g", to: .imperial), 2.2, "lb"), "1000 g → ~2.2 lb")
}

func testUnitConverterNonMeasureReturnsNil() {
    check(UnitConverter.convert(quantity: 2, unit: "clove", to: .metric) == nil, "clove → nil")
    check(UnitConverter.convert(quantity: 1, unit: "", to: .metric) == nil, "empty unit → nil")
    check(UnitConverter.convert(quantity: 3, unit: "egg", to: .metric) == nil, "egg → nil")
    check(UnitConverter.convert(quantity: 1, unit: "pinch", to: .metric) == nil, "pinch → nil")
}

func testUnitConverterAliasesAndFormatting() {
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "TBSP.", to: .metric), 15, "ml"), "TBSP. → 15 ml (case + period)")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "Teaspoons", to: .metric), 5, "ml"), "Teaspoons → 5 ml")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "Pound", to: .metric), 450, "g"), "Pound → 450 g")
    check(ucMatches(UnitConverter.convert(quantity: 1, unit: "  cup  ", to: .metric), 240, "ml"), "whitespace trimmed → 240 ml")
}

func runUnitConverterTests() -> Bool {
    print("\n=== UnitConverter Tests ===")

    testUnitConverterVolumeToMetric()
    testUnitConverterWeightToMetric()
    testUnitConverterMetricStaysMetric()
    testUnitConverterToImperial()
    testUnitConverterNonMeasureReturnsNil()
    testUnitConverterAliasesAndFormatting()

    return printTestSummary("UnitConverter Tests")
}
