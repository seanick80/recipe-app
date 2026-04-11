import Foundation
import SwiftData

@Model
final class Recipe {
    var id: UUID = UUID()
    var name: String = ""
    var summary: String = ""
    var instructions: String = ""
    var prepTimeMinutes: Int = 0
    var cookTimeMinutes: Int = 0
    var servings: Int = 1
    var imageData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient]?

    var totalTimeMinutes: Int {
        prepTimeMinutes + cookTimeMinutes
    }

    init(
        name: String = "",
        summary: String = "",
        instructions: String = "",
        prepTimeMinutes: Int = 0,
        cookTimeMinutes: Int = 0,
        servings: Int = 1,
        ingredients: [Ingredient] = []
    ) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.servings = servings
        self.ingredients = ingredients
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
