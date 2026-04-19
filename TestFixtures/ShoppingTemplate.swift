import Foundation

/// Canonical store-aisle category order. Used for sorting grocery items
/// and shopping templates by the order you encounter them in a typical store.
let defaultCategoryOrder: [String] = [
    "Produce",
    "Dairy",
    "Meat",
    "Dry & Canned",
    "Household",
    "Frozen",
    "Bakery",
    "Snacks",
    "Beverages",
    "Condiments",
    "Spices",
    "Other",
]

/// Returns the sort index for a category name. Unknown categories sort
/// after all known ones (alphabetically among themselves).
func categorySortIndex(_ category: String) -> Int {
    if let index = defaultCategoryOrder.firstIndex(of: category) {
        return index
    }
    return defaultCategoryOrder.count
}

/// Sorts items by store-aisle category order, then by sortOrder within category.
func sortedByStoreAisle<T>(
    _ items: [T],
    category: (T) -> String,
    sortOrder: (T) -> Int
) -> [T] {
    items.sorted { a, b in
        let catA = categorySortIndex(category(a))
        let catB = categorySortIndex(category(b))
        if catA != catB { return catA < catB }
        return sortOrder(a) < sortOrder(b)
    }
}

/// Groups items by category, sorted by store-aisle order.
/// Returns array of (categoryName, items) tuples.
func groupedByStoreAisle<T>(
    _ items: [T],
    category: (T) -> String,
    sortOrder: (T) -> Int
) -> [(String, [T])] {
    let grouped = Dictionary(grouping: items, by: category)
    let sortedKeys = grouped.keys.sorted { categorySortIndex($0) < categorySortIndex($1) }
    return sortedKeys.map { key in
        let sorted = grouped[key]!.sorted { sortOrder($0) < sortOrder($1) }
        return (key, sorted)
    }
}

struct ShoppingTemplateModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var items: [TemplateItemModel]

    init(
        id: UUID = UUID(),
        name: String = "",
        sortOrder: Int = 0,
        items: [TemplateItemModel] = []
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.items = items
    }

    /// Stamps a new GroceryListModel from this template's items.
    func stampGroceryList(name: String? = nil) -> GroceryListModel {
        let listName = name ?? self.name
        let groceryItems = items.map { templateItem in
            GroceryItemModel(
                name: templateItem.name,
                quantity: templateItem.quantity,
                unit: templateItem.unit,
                category: templateItem.category
            )
        }
        return GroceryListModel(name: listName, items: groceryItems)
    }
}

struct TemplateItemModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        quantity: Double = 1,
        unit: String = "",
        category: String = "Other",
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.sortOrder = sortOrder
    }
}
