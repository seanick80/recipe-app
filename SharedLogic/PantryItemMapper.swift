import Foundation

/// Maps YOLO detection labels (food class names) to structured pantry items.
/// Pure Swift — no Apple frameworks.
///
/// YOLO food detection models output labels like "apple", "banana",
/// "milk_carton", "bread". This module normalizes these labels and maps
/// them to store-aisle categories.

struct PantryItemModel: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var quantity: Int
    var unit: String
    var confidence: Double
    var detectedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "Other",
        quantity: Int = 1,
        unit: String = "",
        confidence: Double = 0,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.confidence = confidence
        self.detectedAt = detectedAt
    }
}

/// Known YOLO food labels mapped to (display name, category).
/// Labels come from common food detection models (e.g. BinhQuocNguyen,
/// COCO food subset, Food-101).
private let yoloFoodMap: [String: (name: String, category: String)] = [
    // Produce
    "apple": ("Apple", "Produce"),
    "banana": ("Banana", "Produce"),
    "orange": ("Orange", "Produce"),
    "lemon": ("Lemon", "Produce"),
    "lime": ("Lime", "Produce"),
    "tomato": ("Tomato", "Produce"),
    "potato": ("Potato", "Produce"),
    "onion": ("Onion", "Produce"),
    "carrot": ("Carrot", "Produce"),
    "broccoli": ("Broccoli", "Produce"),
    "lettuce": ("Lettuce", "Produce"),
    "cucumber": ("Cucumber", "Produce"),
    "pepper": ("Pepper", "Produce"),
    "bell_pepper": ("Bell Pepper", "Produce"),
    "garlic": ("Garlic", "Produce"),
    "avocado": ("Avocado", "Produce"),
    "grape": ("Grapes", "Produce"),
    "strawberry": ("Strawberries", "Produce"),
    "blueberry": ("Blueberries", "Produce"),
    "mushroom": ("Mushrooms", "Produce"),
    "corn": ("Corn", "Produce"),
    "celery": ("Celery", "Produce"),
    "spinach": ("Spinach", "Produce"),

    // Dairy
    "milk": ("Milk", "Dairy"),
    "milk_carton": ("Milk", "Dairy"),
    "cheese": ("Cheese", "Dairy"),
    "yogurt": ("Yogurt", "Dairy"),
    "butter": ("Butter", "Dairy"),
    "egg": ("Eggs", "Dairy"),
    "eggs": ("Eggs", "Dairy"),
    "cream": ("Cream", "Dairy"),
    "sour_cream": ("Sour Cream", "Dairy"),

    // Meat
    "chicken": ("Chicken", "Meat"),
    "beef": ("Beef", "Meat"),
    "pork": ("Pork", "Meat"),
    "fish": ("Fish", "Meat"),
    "salmon": ("Salmon", "Meat"),
    "shrimp": ("Shrimp", "Meat"),
    "sausage": ("Sausage", "Meat"),
    "bacon": ("Bacon", "Meat"),
    "ham": ("Ham", "Meat"),
    "steak": ("Steak", "Meat"),
    "ground_beef": ("Ground Beef", "Meat"),
    "turkey": ("Turkey", "Meat"),

    // Dry & Canned
    "rice": ("Rice", "Dry & Canned"),
    "pasta": ("Pasta", "Dry & Canned"),
    "bread": ("Bread", "Bakery"),
    "cereal": ("Cereal", "Dry & Canned"),
    "can": ("Canned Good", "Dry & Canned"),
    "canned_food": ("Canned Good", "Dry & Canned"),
    "flour": ("Flour", "Dry & Canned"),
    "sugar": ("Sugar", "Dry & Canned"),
    "oil": ("Cooking Oil", "Dry & Canned"),
    "olive_oil": ("Olive Oil", "Dry & Canned"),

    // Beverages
    "bottle": ("Bottle", "Beverages"),
    "water_bottle": ("Water", "Beverages"),
    "juice": ("Juice", "Beverages"),
    "soda": ("Soda", "Beverages"),
    "coffee": ("Coffee", "Beverages"),
    "tea": ("Tea", "Beverages"),
    "wine": ("Wine", "Beverages"),
    "beer": ("Beer", "Beverages"),

    // Frozen
    "ice_cream": ("Ice Cream", "Frozen"),
    "frozen_food": ("Frozen Food", "Frozen"),
    "pizza": ("Pizza", "Frozen"),

    // Snacks
    "chips": ("Chips", "Snacks"),
    "cookie": ("Cookies", "Snacks"),
    "crackers": ("Crackers", "Snacks"),
    "chocolate": ("Chocolate", "Snacks"),
    "candy": ("Candy", "Snacks"),
    "nuts": ("Nuts", "Snacks"),

    // Condiments
    "ketchup": ("Ketchup", "Condiments"),
    "mustard": ("Mustard", "Condiments"),
    "mayonnaise": ("Mayonnaise", "Condiments"),
    "hot_sauce": ("Hot Sauce", "Condiments"),
    "soy_sauce": ("Soy Sauce", "Condiments"),
]

/// Maps a YOLO detection label to a `PantryItemModel`.
/// Returns nil if the label is completely unknown.
func mapYOLOLabel(
    _ label: String,
    confidence: Double,
    quantity: Int = 1
) -> PantryItemModel? {
    let normalized = normalizeYOLOLabel(label)

    if let mapping = yoloFoodMap[normalized] {
        return PantryItemModel(
            name: mapping.name,
            category: mapping.category,
            quantity: quantity,
            confidence: confidence
        )
    }

    // Unknown label — still return an item with the raw label as name
    // so the user can correct it in the confirmation UI.
    let displayName =
        label
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        .joined(separator: " ")

    return PantryItemModel(
        name: displayName,
        category: "Other",
        quantity: quantity,
        confidence: confidence
    )
}

/// Normalizes a YOLO label for lookup: lowercase, trim, replace spaces/hyphens
/// with underscores.
func normalizeYOLOLabel(_ label: String) -> String {
    label
        .lowercased()
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: " ", with: "_")
        .replacingOccurrences(of: "-", with: "_")
}

/// Merges multiple detections of the same item into a single pantry item
/// with aggregated quantity and highest confidence.
func mergePantryDetections(_ items: [PantryItemModel]) -> [PantryItemModel] {
    var merged: [String: PantryItemModel] = [:]
    for item in items {
        let key = item.name.lowercased()
        if var existing = merged[key] {
            existing.quantity += item.quantity
            if item.confidence > existing.confidence {
                existing.confidence = item.confidence
            }
            merged[key] = existing
        } else {
            merged[key] = item
        }
    }
    return Array(merged.values).sorted { $0.name < $1.name }
}
