import Foundation
import SwiftData

/// Checks the shared App Group container for recipe files dropped by the
/// Share Extension and imports them into SwiftData.
@Observable
class PendingImportService {
    var pendingRecipe: ImportedRecipe?
    var showingImportReview = false

    private var pendingFileURL: URL?

    func checkForPendingImports() {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.seanick80.recipeapp"
            )
        else { return }

        let pendingDir = containerURL.appendingPathComponent("PendingImports", isDirectory: true)
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: pendingDir,
                includingPropertiesForKeys: nil
            )
        else { return }

        // Process the first pending file
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let recipe = try? JSONDecoder().decode(ImportedRecipe.self, from: data)
            else {
                // Remove corrupt files
                try? FileManager.default.removeItem(at: file)
                continue
            }
            pendingRecipe = recipe
            pendingFileURL = file
            showingImportReview = true
            return
        }
    }

    func confirmImport(context: ModelContext) {
        guard let imported = pendingRecipe else { return }

        let recipe = Recipe()
        recipe.name = imported.title
        recipe.instructions = imported.instructions.joined(separator: "\n\n")
        recipe.servings = imported.servings ?? 1
        recipe.prepTimeMinutes = imported.prepTimeMinutes ?? 0
        recipe.cookTimeMinutes = imported.cookTimeMinutes ?? 0
        recipe.cuisine = imported.cuisine
        recipe.course = imported.course
        recipe.sourceURL = imported.sourceURL
        context.insert(recipe)

        for (index, ingredientText) in imported.ingredients.enumerated() {
            let parsed = parseListLine(ingredientText)
            let ingredient = Ingredient()
            ingredient.name = parsed?.name ?? ingredientText
            ingredient.quantity = parsed?.quantity ?? 1
            ingredient.unit = parsed?.unit ?? ""
            ingredient.displayOrder = index
            ingredient.category = categorizeGroceryItem(ingredient.name)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }

        cleanup()
    }

    func cancelImport() {
        cleanup()
    }

    private func cleanup() {
        if let url = pendingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingRecipe = nil
        pendingFileURL = nil
        showingImportReview = false
    }
}
