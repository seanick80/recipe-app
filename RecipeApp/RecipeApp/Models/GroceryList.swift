import Foundation
import SwiftData

@Model
final class GroceryList {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.groceryList)
    var items: [GroceryItem]?

    var completedCount: Int {
        (items ?? []).filter { $0.isChecked }.count
    }

    init(name: String = "", items: [GroceryItem] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.items = items
    }
}
