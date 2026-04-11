import Foundation
import SwiftData

@Model
final class GroceryItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 1
    var unit: String = ""
    var category: String = "Other"
    var isChecked: Bool = false
    var groceryList: GroceryList?

    init(
        name: String = "",
        quantity: Double = 1,
        unit: String = "",
        category: String = "Other"
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.isChecked = false
    }
}
