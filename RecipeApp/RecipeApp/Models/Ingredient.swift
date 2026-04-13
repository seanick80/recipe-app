import Foundation
import SwiftData

@Model
final class Ingredient {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 0
    var unit: String = ""
    var category: String = "Other"
    var displayOrder: Int = 0
    var notes: String = ""
    var recipe: Recipe?

    init(
        name: String = "",
        quantity: Double = 0,
        unit: String = "",
        category: String = "Other",
        displayOrder: Int = 0,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.displayOrder = displayOrder
        self.notes = notes
    }
}
