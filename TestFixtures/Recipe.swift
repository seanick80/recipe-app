import Foundation

struct RecipeModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var instructions: String
    var prepTimeMinutes: Int
    var cookTimeMinutes: Int
    var servings: Int
    var cuisine: String
    var course: String
    var tags: String
    var sourceURL: String
    var difficulty: String
    /// User-scoped favorite. Works because recipes live in the private CloudKit
    /// zone. If a multi-user backend is added later, migrate to a join table.
    var isFavorite: Bool
    var isPublished: Bool
    var ingredients: [IngredientModel]
    var createdAt: Date
    var updatedAt: Date

    var totalTimeMinutes: Int { prepTimeMinutes + cookTimeMinutes }

    init(
        id: UUID = UUID(),
        name: String,
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
        ingredients: [IngredientModel] = []
    ) {
        self.id = id
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

struct IngredientModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: String
    var category: String
    var displayOrder: Int
    var notes: String

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double = 0,
        unit: String = "",
        category: String = "Other",
        displayOrder: Int = 0,
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.displayOrder = displayOrder
        self.notes = notes
    }
}
