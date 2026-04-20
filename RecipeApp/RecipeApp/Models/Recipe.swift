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
    var cuisine: String = ""
    var course: String = ""
    var tags: String = ""
    var sourceURL: String = ""
    var difficulty: String = ""
    /// User-scoped favorite. Works because recipes live in the private CloudKit
    /// zone. If a multi-user backend is added later, migrate to a join table.
    var isFavorite: Bool = false
    var isPublished: Bool = false
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
        cuisine: String = "",
        course: String = "",
        tags: String = "",
        sourceURL: String = "",
        difficulty: String = "",
        isFavorite: Bool = false,
        isPublished: Bool = false,
        ingredients: [Ingredient] = []
    ) {
        self.id = UUID()
        self.name = name
        self.summary = summary
        self.instructions = instructions
        self.prepTimeMinutes = prepTimeMinutes
        self.cookTimeMinutes = cookTimeMinutes
        self.servings = servings
        self.cuisine = cuisine
        self.course = course
        self.tags = tags
        self.sourceURL = sourceURL
        self.difficulty = difficulty
        self.isFavorite = isFavorite
        self.isPublished = isPublished
        self.ingredients = ingredients
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
