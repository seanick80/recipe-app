import SwiftData
import SwiftUI

struct GenerateGroceryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.name) private var recipes: [Recipe]
    @Query(
        filter: #Predicate<GroceryList> { $0.archivedAt == nil },
        sort: \GroceryList.createdAt,
        order: .reverse
    ) private var existingLists: [GroceryList]

    @State private var selectedRecipes: Set<UUID> = []
    @State private var listName = ""
    @State private var userEditedName = false
    @State private var addToExisting = false
    @State private var selectedList: GroceryList?

    var body: some View {
        NavigationStack {
            Form {
                Section("Destination") {
                    Toggle("Add to existing list", isOn: $addToExisting)
                        .disabled(existingLists.isEmpty)
                    if addToExisting {
                        Picker("List", selection: $selectedList) {
                            Text("Select a list").tag(nil as GroceryList?)
                            ForEach(existingLists) { list in
                                Text("\(list.name) (\(list.items?.count ?? 0) items)")
                                    .tag(list as GroceryList?)
                            }
                        }
                    } else {
                        TextField(
                            "e.g. Weekly Groceries",
                            text: Binding(
                                get: { listName },
                                set: { newValue in
                                    listName = newValue
                                    userEditedName = true
                                }
                            )
                        )
                    }
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
            .onChange(of: selectedRecipes) {
                guard !userEditedName else { return }
                let names = recipes.filter { selectedRecipes.contains($0.id) }
                    .map(\.name)
                    .sorted()
                listName = names.joined(separator: ", ")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Generate") { generate() }
                        .disabled(
                            selectedRecipes.isEmpty
                                || (addToExisting ? selectedList == nil : listName.isEmpty)
                        )
                }
            }
        }
    }

    private func generate() {
        let chosen = recipes.filter { selectedRecipes.contains($0.id) }

        // Resolve or create the target list
        let list: GroceryList
        if addToExisting, let existing = selectedList {
            list = existing
        } else {
            list = GroceryList(name: listName)
            modelContext.insert(list)
        }

        // Index existing items for duplicate merging (GM-25)
        var existingByKey: [String: GroceryItem] = [:]
        for item in list.items ?? [] {
            let key = "\(item.name.lowercased())|\(item.unit.lowercased())"
            existingByKey[key] = item
        }

        // Consolidate ingredients across selected recipes
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

        // Merge into list, incrementing existing items when name+unit match
        for (name, info) in consolidated {
            let mergeKey = "\(name)|\(info.unit.lowercased())"
            if let existing = existingByKey[mergeKey] {
                existing.quantity += info.quantity
                if !existing.sourceRecipeName.isEmpty {
                    existing.sourceRecipeName += ", "
                }
                existing.sourceRecipeName += info.recipeNames.joined(separator: ", ")
                if !existing.sourceRecipeId.isEmpty {
                    existing.sourceRecipeId += ", "
                }
                existing.sourceRecipeId += info.recipeIds.joined(separator: ", ")
            } else {
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
                existingByKey[mergeKey] = item
            }
        }

        dismiss()
    }
}
