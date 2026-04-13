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
    let result = parseOpenFoodFactsJSON(json)
    check(result != nil, "Valid OFF response parses")
    checkEqual(result!.barcode, "3017620422003", "OFF barcode")
    checkEqual(result!.name, "Nutella", "OFF product name")
    checkEqual(result!.brand, "Ferrero", "OFF brand")
    checkEqual(result!.quantity, "750 g", "OFF quantity")
}

func testParseOFFNotFound() {
    let json: [String: Any] = [
        "status": 0,
        "code": "0000000000000",
    ]
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
    let result = parseOpenFoodFactsJSON(json)
    check(result != nil, "Fallback name parses")
    checkEqual(result!.name, "Lait Entier", "Falls back to product_name")
}

func testMapOFFCategoryDairy() {
    let tags = ["en:dairies", "en:milks", "en:whole-milks"]
    checkEqual(mapOFFCategory(tags), "Dairy", "Dairy category mapping")
}

func testMapOFFCategoryProduce() {
    let tags = ["en:fruits", "en:fresh-fruits", "en:apples"]
    checkEqual(mapOFFCategory(tags), "Produce", "Produce category mapping")
}

func testMapOFFCategoryMeat() {
    let tags = ["en:meats", "en:poultry", "en:chicken"]
    checkEqual(mapOFFCategory(tags), "Meat", "Meat category mapping")
}

func testMapOFFCategoryFrozen() {
    let tags = ["en:frozen", "en:frozen-pizzas"]
    checkEqual(mapOFFCategory(tags), "Frozen", "Frozen category mapping")
}

func testMapOFFCategorySnacks() {
    let tags = ["en:snacks", "en:chips"]
    checkEqual(mapOFFCategory(tags), "Snacks", "Snacks category mapping")
}

func testMapOFFCategoryBeverages() {
    let tags = ["en:beverages", "en:juices"]
    checkEqual(mapOFFCategory(tags), "Beverages", "Beverages category mapping")
}

func testMapOFFCategoryUnknown() {
    let tags = ["en:some-unknown-thing"]
    checkEqual(mapOFFCategory(tags), "Other", "Unknown category → Other")
}

func testMapOFFCategoryEmpty() {
    checkEqual(mapOFFCategory([]), "Other", "Empty tags → Other")
}

func testFormatProductDisplay() {
    checkEqual(
        formatProductDisplay(name: "Whole Milk", brand: "Horizon"),
        "Horizon Whole Milk",
        "Brand prepended"
    )
    checkEqual(
        formatProductDisplay(name: "Horizon Whole Milk", brand: "Horizon"),
        "Horizon Whole Milk",
        "Brand already in name — not duplicated"
    )
    checkEqual(
        formatProductDisplay(name: "Eggs", brand: ""),
        "Eggs",
        "Empty brand — name only"
    )
    checkEqual(
        formatProductDisplay(name: "Yogurt", brand: "  "),
        "Yogurt",
        "Whitespace brand — name only"
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
    testMapOFFCategoryDairy()
    testMapOFFCategoryProduce()
    testMapOFFCategoryMeat()
    testMapOFFCategoryFrozen()
    testMapOFFCategorySnacks()
    testMapOFFCategoryBeverages()
    testMapOFFCategoryUnknown()
    testMapOFFCategoryEmpty()
    testFormatProductDisplay()
    testProductLookupResultCodable()

    return printTestSummary("Barcode Mapper Tests")
}
