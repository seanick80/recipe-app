import Foundation

struct RecipeModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var instructions: String
    var prepTimeMinutes: Int
    var cookTimeMinutes: Int
    var servings: Int
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
        ingredients: [IngredientModel] = []
    ) {
        self.id = id
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

struct IngredientModel: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var quantity: Double
    var unit: String

    init(id: UUID = UUID(), name: String, quantity: Double = 0, unit: String = "") {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }
}
