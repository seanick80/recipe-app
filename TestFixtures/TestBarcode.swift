import Foundation

// MARK: - Barcode Product Mapper Tests

func testParseOFFResponse() {
    // Valid response
    let json: [String: Any] = [
        "status": 1, "code": "3017620422003",
        "product": [
            "product_name_en": "Nutella", "brands": "Ferrero",
            "categories_tags": ["en:breakfasts", "en:spreads"],
        ] as [String: Any],
    ]
    let result = parseOpenFoodFactsJSON(json)!
    checkEqual(result.name, "Nutella", "OFF product name")
    checkEqual(result.brand, "Ferrero", "OFF brand")

    // Not found
    check(parseOpenFoodFactsJSON(["status": 0, "code": "0"]) == nil, "Status 0 nil")

    // Fallback name
    let fallback: [String: Any] = [
        "status": 1, "code": "456",
        "product": ["product_name_en": "", "product_name": "Lait", "brands": "X"] as [String: Any],
    ]
    checkEqual(parseOpenFoodFactsJSON(fallback)!.name, "Lait", "Fallback to product_name")
}

func testMapOFFCategories() {
    let cases: [([String], String)] = [
        (["en:dairies"], "Dairy"),
        (["en:fruits"], "Produce"),
        (["en:meats"], "Meat"),
        ([], "Other"),
    ]
    for (tags, expected) in cases {
        checkEqual(mapOFFCategory(tags), expected, "\(tags.first ?? "empty") -> \(expected)")
    }
}

func testFormatAndCodable() {
    checkEqual(formatProductDisplay(name: "Milk", brand: "Horizon"), "Horizon Milk", "Brand prepended")
    checkEqual(formatProductDisplay(name: "Eggs", brand: ""), "Eggs", "No brand")
    checkCodableRoundTrip(
        ProductLookupResult(barcode: "123", name: "Test", brand: "B", category: "Dairy", quantity: "1L"),
        "ProductLookupResult Codable"
    )
}

// MARK: - Test Runner

func runBarcodeTests() -> Bool {
    print("\n=== Barcode Product Mapper Tests ===")

    testParseOFFResponse()
    testMapOFFCategories()
    testFormatAndCodable()

    return printTestSummary("Barcode Mapper Tests")
}
