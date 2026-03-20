import SwiftUI
import SwiftData

struct RecipeEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var recipe: Recipe?

    @State private var name = ""
    @State private var summary = ""
    @State private var instructions = ""
    @State private var prepTime = 0
    @State private var cookTime = 0
    @State private var servings = 1
    @State private var ingredientRows: [(name: String, quantity: String, unit: String)] = []

    var isEditing: Bool { recipe != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Recipe Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Time & Servings") {
                    Stepper("Prep: \(prepTime) min", value: $prepTime, in: 0...480, step: 5)
                    Stepper("Cook: \(cookTime) min", value: $cookTime, in: 0...480, step: 5)
                    Stepper("Servings: \(servings)", value: $servings, in: 1...50)
                }

                Section("Ingredients") {
                    ForEach(ingredientRows.indices, id: \.self) { index in
                        HStack {
                            TextField("Qty", text: $ingredientRows[index].quantity)
                                .frame(width: 50)
                                .keyboardType(.decimalPad)
                            TextField("Unit", text: $ingredientRows[index].unit)
                                .frame(width: 60)
                            TextField("Ingredient", text: $ingredientRows[index].name)
                        }
                    }
                    .onDelete { indices in
                        ingredientRows.remove(atOffsets: indices)
                    }
                    Button("Add Ingredient") {
                        ingredientRows.append((name: "", quantity: "", unit: ""))
                    }
                }

                Section("Instructions") {
                    TextField("Step-by-step instructions", text: $instructions, axis: .vertical)
                        .lineLimit(5...20)
                }
            }
            .navigationTitle(isEditing ? "Edit Recipe" : "New Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        guard let recipe else { return }
        name = recipe.name
        summary = recipe.summary
        instructions = recipe.instructions
        prepTime = recipe.prepTimeMinutes
        cookTime = recipe.cookTimeMinutes
        servings = recipe.servings
        ingredientRows = recipe.ingredients.map {
            (name: $0.name, quantity: "\($0.quantity)", unit: $0.unit)
        }
    }

    private func save() {
        let target = recipe ?? Recipe(name: name)
        target.name = name
        target.summary = summary
        target.instructions = instructions
        target.prepTimeMinutes = prepTime
        target.cookTimeMinutes = cookTime
        target.servings = servings
        target.updatedAt = Date()

        if isEditing {
            for old in target.ingredients {
                modelContext.delete(old)
            }
        }

        let newIngredients = ingredientRows.compactMap { row -> Ingredient? in
            guard !row.name.isEmpty else { return nil }
            return Ingredient(
                name: row.name,
                quantity: Double(row.quantity) ?? 0,
                unit: row.unit
            )
        }
        target.ingredients = newIngredients

        if !isEditing {
            modelContext.insert(target)
        }
        dismiss()
    }
}
