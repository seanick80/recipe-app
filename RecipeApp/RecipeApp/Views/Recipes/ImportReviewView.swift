import SwiftData
import SwiftUI

/// Shows a preview of a recipe imported via the Share Extension,
/// allowing the user to confirm or discard before saving.
struct ImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let recipe: ImportedRecipe
    var importService: PendingImportService

    var body: some View {
        NavigationStack {
            List {
                Section("Recipe") {
                    LabeledContent("Name", value: recipe.title)
                    if !recipe.cuisine.isEmpty {
                        LabeledContent("Cuisine", value: recipe.cuisine)
                    }
                    if !recipe.course.isEmpty {
                        LabeledContent("Course", value: recipe.course)
                    }
                    if let servings = recipe.servings {
                        LabeledContent("Servings", value: "\(servings)")
                    }
                    if let prep = recipe.prepTimeMinutes {
                        LabeledContent("Prep Time", value: "\(prep) min")
                    }
                    if let cook = recipe.cookTimeMinutes {
                        LabeledContent("Cook Time", value: "\(cook) min")
                    }
                    if !recipe.sourceURL.isEmpty {
                        LabeledContent("Source", value: recipe.sourceURL)
                            .lineLimit(1)
                    }
                }

                Section("Ingredients (\(recipe.ingredients.count))") {
                    ForEach(recipe.ingredients, id: \.self) { ingredient in
                        Text(ingredient)
                    }
                }

                if !recipe.instructions.isEmpty {
                    Section("Instructions (\(recipe.instructions.count) steps)") {
                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(step)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        importService.cancelImport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importService.confirmImport(context: modelContext)
                        dismiss()
                    }
                }
            }
        }
    }
}
