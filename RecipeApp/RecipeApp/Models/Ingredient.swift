import Foundation
import SwiftData

@Model
final class Ingredient {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var recipe: Recipe?

    init(name: String, quantity: Double = 0, unit: String = "") {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}
