import Foundation

struct GroceryItemModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var isChecked: Bool
    var sourceRecipeName: String
    var sourceRecipeId: String

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 1,
        unit: String = "",
        category: String = "Other",
        isChecked: Bool = false,
        sourceRecipeName: String = "",
        sourceRecipeId: String = ""
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = isChecked
        self.sourceRecipeName = sourceRecipeName
        self.sourceRecipeId = sourceRecipeId
    }
}

struct GroceryListModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var items: [GroceryItemModel]
    var createdAt: Date
    var archivedAt: Date?

    var completedCount: Int { items.filter(\.isChecked).count }

    init(id: UUID = UUID(), name: String, items: [GroceryItemModel] = [], archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.items = items
        self.createdAt = Date()
        self.archivedAt = archivedAt
    }
}
