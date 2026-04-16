import Foundation

/// Maps Open Food Facts API JSON responses to product info. Pure Swift — no
/// Apple frameworks.
///
/// The Open Food Facts API returns JSON at:
///   https://world.openfoodfacts.org/api/v2/product/{barcode}.json
///
/// This module parses that JSON into a structured product result that can be
/// used to populate pantry or grocery list items.

struct ProductLookupResult: Codable, Equatable {
    var barcode: String
    var name: String
    var brand: String
    var category: String
    var quantity: String
    var imageURL: String

    init(
        barcode: String = "",
        name: String = "",
        brand: String = "",
        category: String = "",
        quantity: String = "",
        imageURL: String = ""
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.category = category
        self.quantity = quantity
        self.imageURL = imageURL
    }
}

/// Parses an Open Food Facts API v2 JSON response into a `ProductLookupResult`.
/// Returns nil if the product was not found (status != 1).
func parseOpenFoodFactsResponse(_ jsonData: Data) -> ProductLookupResult? {
    guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        return nil
    }
    return parseOpenFoodFactsJSON(json)
}

/// Parses the already-deserialized JSON dictionary.
func parseOpenFoodFactsJSON(_ json: [String: Any]) -> ProductLookupResult? {
    // Check status field
    let status = json["status"] as? Int ?? 0
    guard status == 1 else { return nil }

    let product = json["product"] as? [String: Any] ?? [:]
    let barcode = json["code"] as? String ?? ""

    let name = bestProductName(from: product)
    let brand = product["brands"] as? String ?? ""
    let category = mapOFFCategory(product["categories_tags"] as? [String] ?? [])
    let quantity = product["quantity"] as? String ?? ""
    let imageURL = product["image_front_small_url"] as? String ?? ""

    guard !name.isEmpty else { return nil }

    return ProductLookupResult(
        barcode: barcode,
        name: name,
        brand: brand,
        category: category,
        quantity: quantity,
        imageURL: imageURL
    )
}

/// Picks the best available product name from OFF fields.
func bestProductName(from product: [String: Any]) -> String {
    // Prefer product_name_en, then product_name, then generic_name
    let candidates: [String] = [
        product["product_name_en"] as? String ?? "",
        product["product_name"] as? String ?? "",
        product["generic_name"] as? String ?? "",
    ]
    for candidate in candidates {
        let trimmed = candidate.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
    }
    return ""
}

/// Category mapping from Open Food Facts tags to our store-aisle categories.
private let offCategoryMapping: [(keywords: [String], category: String)] = [
    (["fruits", "vegetables", "legumes", "salads"], "Produce"),
    (["dairies", "milks", "cheeses", "yogurts", "eggs", "butters", "creams"], "Dairy"),
    (["meats", "poultry", "beef", "pork", "fish", "seafood", "lamb"], "Meat"),
    (["cereals", "pasta", "rice", "canned", "sauces", "oils", "flour", "sugar", "spices"], "Dry & Canned"),
    (["frozen", "ice-cream"], "Frozen"),
    (["breads", "bakery", "pastries"], "Bakery"),
    (["snacks", "chips", "crackers", "cookies", "candy", "chocolate"], "Snacks"),
    (["beverages", "drinks", "juices", "sodas", "waters", "coffee", "tea"], "Beverages"),
    (["condiments", "dressings", "ketchup", "mustard", "mayonnaise"], "Condiments"),
    (["cleaning", "household", "paper"], "Household"),
]

/// Maps Open Food Facts category tags (like "en:dairies", "en:milks") to a
/// store-aisle category string.
func mapOFFCategory(_ tags: [String]) -> String {
    // OFF tags look like "en:dairies", "en:whole-milks" etc.
    let normalized = tags.map { tag -> String in
        let parts = tag.split(separator: ":")
        return (parts.count > 1 ? String(parts[1]) : tag).lowercased()
    }

    for (keywords, category) in offCategoryMapping {
        for tag in normalized {
            for keyword in keywords {
                if tag.contains(keyword) {
                    return category
                }
            }
        }
    }
    return "Other"
}

/// Formats a product name with brand for display: "Brand Name Product" or
/// just "Product" if brand is empty or already in the name.
func formatProductDisplay(name: String, brand: String) -> String {
    let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
    guard !trimmedBrand.isEmpty else { return name }
    if name.lowercased().contains(trimmedBrand.lowercased()) { return name }
    return "\(trimmedBrand) \(name)"
}
