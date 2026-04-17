import SwiftData
import SwiftUI

struct GenerateGroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    @State private var selectedRecipes: Set<UUID> = []
    @State private var listName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("List Name") {
                    TextField("e.g. Weekly Groceries", text: $listName)
                }

                Section("Select Recipes") {
                    ForEach(recipes) { recipe in
                        Button {
                            if selectedRecipes.contains(recipe.id) {
                                selectedRecipes.remove(recipe.id)
                            } else {
                                selectedRecipes.insert(recipe.id)
                            }
                        } label: {
                            HStack {
                                Image(
                                    systemName: selectedRecipes.contains(recipe.id)
                                        ? "checkmark.circle.fill" : "circle"
                                )
                                .foregroundStyle(
                                    selectedRecipes.contains(recipe.id)
                                        ? .blue : .gray
                                )
                                VStack(alignment: .leading) {
                                    Text(recipe.name)
                                        .foregroundStyle(.primary)
                                    Text("\(recipe.ingredients?.count ?? 0) ingredients")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Generate Grocery List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generate() }
                        .disabled(listName.isEmpty || selectedRecipes.isEmpty)
                }
            }
        }
    }

    private func generate() {
        let chosen = recipes.filter { selectedRecipes.contains($0.id) }
        let list = GroceryList(name: listName)

        struct ConsolidatedItem {
            var quantity: Double
            var unit: String
            var category: String
            var recipeNames: [String]
            var recipeIds: [String]
        }

        var consolidated: [String: ConsolidatedItem] = [:]
        for recipe in chosen {
            for ingredient in recipe.ingredients ?? [] {
                let stripped = stripPrepNotes(ingredient.name)
                let cleanName = stripped.name.isEmpty ? ingredient.name : stripped.name
                let key = cleanName.lowercased()
                if var existing = consolidated[key] {
                    if existing.unit == ingredient.unit {
                        existing.quantity += ingredient.quantity
                    }
                    if !existing.recipeNames.contains(recipe.name) {
                        existing.recipeNames.append(recipe.name)
                        existing.recipeIds.append(recipe.id.uuidString)
                    }
                    consolidated[key] = existing
                } else {
                    consolidated[key] = ConsolidatedItem(
                        quantity: ingredient.quantity,
                        unit: ingredient.unit,
                        category: ingredient.category.isEmpty
                            ? categorizeGroceryItem(cleanName) : ingredient.category,
                        recipeNames: [recipe.name],
                        recipeIds: [recipe.id.uuidString]
                    )
                }
            }
        }

        for (name, info) in consolidated {
            let item = GroceryItem(
                name: name.capitalized,
                quantity: info.quantity,
                unit: info.unit,
                category: info.category,
                sourceRecipeName: info.recipeNames.joined(separator: ", "),
                sourceRecipeId: info.recipeIds.joined(separator: ", ")
            )
            item.groceryList = list
            modelContext.insert(item)
        }

        modelContext.insert(list)
        dismiss()
    }
}
