import Foundation
import SwiftData

@Observable
class ShoppingViewModel {
    /// Store-aisle category order for sorting grocery items in the shopping list.
    static let categoryOrder: [String] = [
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

    /// Returns the sort index for a category. Unknown categories sort after all known ones.
    static func categorySortIndex(_ category: String) -> Int {
        if let index = categoryOrder.firstIndex(of: category) {
            return index
        }
        return categoryOrder.count
    }

    /// Groups items by category, sorted by store-aisle order.
    /// Checked items sink to the bottom within their category.
    func categorizedItems(from list: GroceryList) -> [(String, [GroceryItem])] {
        let allItems = list.items ?? []
        let grouped = Dictionary(grouping: allItems) { $0.category }
        let sortedKeys = grouped.keys.sorted {
            Self.categorySortIndex($0) < Self.categorySortIndex($1)
        }
        return sortedKeys.map { key in
            let items = grouped[key]!.sorted { a, b in
                if a.isChecked != b.isChecked { return !a.isChecked }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            return (key, items)
        }
    }

    /// Stamps a new GroceryList from a ShoppingTemplate.
    func stampList(
        from template: ShoppingTemplate,
        name: String?,
        context: ModelContext
    ) -> GroceryList {
        let listName = name ?? template.name
        let list = GroceryList(name: listName)
        context.insert(list)

        let sortedItems = (template.items ?? []).sorted { $0.sortOrder < $1.sortOrder }
        for templateItem in sortedItems {
            let item = GroceryItem(
                name: templateItem.name,
                quantity: templateItem.quantity,
                unit: templateItem.unit,
                category: templateItem.category
            )
            item.groceryList = list
            context.insert(item)
        }
        return list
    }

    /// Archives a grocery list by setting its archivedAt date.
    func archive(_ list: GroceryList) {
        list.archivedAt = Date()
    }

    /// Merges items from source lists into the target list, then archives the sources.
    /// Duplicate items (same name + unit, case-insensitive) are consolidated by summing quantities.
    func mergeLists(_ sources: [GroceryList], into target: GroceryList, context: ModelContext) {
        var existingByKey: [String: GroceryItem] = [:]
        for item in target.items ?? [] {
            let key = "\(item.name.lowercased())|\(item.unit.lowercased())"
            existingByKey[key] = item
        }

        for source in sources where source.persistentModelID != target.persistentModelID {
            for item in source.items ?? [] {
                let key = "\(item.name.lowercased())|\(item.unit.lowercased())"
                if let existing = existingByKey[key] {
                    existing.quantity += item.quantity
                    if !item.isChecked { existing.isChecked = false }
                } else {
                    let merged = GroceryItem(
                        name: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        category: item.category,
                        sourceRecipeName: item.sourceRecipeName,
                        sourceRecipeId: item.sourceRecipeId
                    )
                    merged.isChecked = item.isChecked
                    merged.groceryList = target
                    context.insert(merged)
                    existingByKey[key] = merged
                }
            }
            archive(source)
        }
    }

    /// Restores an archived list by clearing its archivedAt date.
    func restore(_ list: GroceryList) {
        list.archivedAt = nil
    }
}
