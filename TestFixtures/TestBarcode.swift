import Foundation

// MARK: - Barcode Product Mapper Tests

func testParseValidOFFResponse() {
    let json: [String: Any] = [
        "status": 1,
        "code": "3017620422003",
        "product": [
            "product_name_en": "Nutella",
            "brands": "Ferrero",
            "categories_tags": ["en:breakfasts", "en:spreads", "en:chocolate-spreads"],
            "quantity": "750 g",
            "image_front_small_url": "https://example.com/nutella.jpg",
        ] as [String: Any],
    ]
    let result = parseOpenFoodFactsJSON(json)!
    checkEqual(result.barcode, "3017620422003", "OFF barcode")
    checkEqual(result.name, "Nutella", "OFF product name")
    checkEqual(result.brand, "Ferrero", "OFF brand")
}

func testParseOFFNotFound() {
    let json: [String: Any] = ["status": 0, "code": "0000000000000"]
    let result = parseOpenFoodFactsJSON(json)
    check(result == nil, "Status 0 returns nil")
}

func testParseOFFMissingName() {
    let json: [String: Any] = [
        "status": 1,
        "code": "123",
        "product": [
            "product_name_en": "",
            "product_name": "",
        ] as [String: Any],
    ]
    let result = parseOpenFoodFactsJSON(json)
    check(result == nil, "Empty name returns nil")
}

func testParseOFFFallbackName() {
    let json: [String: Any] = [
        "status": 1,
        "code": "456",
        "product": [
            "product_name_en": "",
            "product_name": "Lait Entier",
            "brands": "Lactel",
        ] as [String: Any],
    ]
    let result = parseOpenFoodFactsJSON(json)!
    checkEqual(result.name, "Lait Entier", "Falls back to product_name")
}

func testMapOFFCategories() {
    // Data-driven: (tags, expected category)
    let cases: [([String], String)] = [
        (["en:dairies", "en:milks"], "Dairy"),
        (["en:fruits", "en:fresh-fruits"], "Produce"),
        (["en:meats", "en:poultry"], "Meat"),
        (["en:frozen", "en:frozen-pizzas"], "Frozen"),
        (["en:snacks", "en:chips"], "Snacks"),
        (["en:beverages", "en:juices"], "Beverages"),
    ]
    for (tags, expected) in cases {
        checkEqual(mapOFFCategory(tags), expected, "\(tags[0]) -> \(expected)")
    }
}

func testMapOFFCategoryUnknownOrEmpty() {
    checkEqual(mapOFFCategory(["en:some-unknown-thing"]), "Other", "Unknown category -> Other")
    checkEqual(mapOFFCategory([]), "Other", "Empty tags -> Other")
}

func testFormatProductDisplay() {
    checkEqual(
        formatProductDisplay(name: "Whole Milk", brand: "Horizon"),
        "Horizon Whole Milk",
        "Brand prepended"
    )
    checkEqual(
        formatProductDisplay(name: "Eggs", brand: ""),
        "Eggs",
        "Empty brand — name only"
    )
}

func testProductLookupResultCodable() {
    let product = ProductLookupResult(
        barcode: "123",
        name: "Test",
        brand: "Brand",
        category: "Dairy",
        quantity: "1L"
    )
    checkCodableRoundTrip(product, "ProductLookupResult Codable round-trip")
}

// MARK: - Test Runner

func runBarcodeTests() -> Bool {
    print("\n=== Barcode Product Mapper Tests ===")

    testParseValidOFFResponse()
    testParseOFFNotFound()
    testParseOFFMissingName()
    testParseOFFFallbackName()
    testMapOFFCategories()
    testMapOFFCategoryUnknownOrEmpty()
    testFormatProductDisplay()
    testProductLookupResultCodable()

    return printTestSummary("Barcode Mapper Tests")
}
