import Foundation
import SwiftData

/// Checks the shared App Group container for recipe files dropped by the
/// Share Extension and imports them into SwiftData.
@Observable
class PendingImportService {
    var pendingRecipe: ImportedRecipe?
    var showingImportReview = false

    private let log = DebugLog.shared
    private var pendingFileURL: URL?

    func checkForPendingImports() {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: DebugLog.appGroupID
            )
        else {
            log.log(category: "import.error", message: "App Group container URL is nil — group not provisioned?")
            return
        }

        let pendingDir = containerURL.appendingPathComponent("PendingImports", isDirectory: true)
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: pendingDir,
                includingPropertiesForKeys: nil
            )
        else {
            log.log(category: "import", message: "No PendingImports directory yet", details: ["path": pendingDir.path])
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        log.log(category: "import", message: "Checking pending imports", details: ["fileCount": "\(jsonFiles.count)"])

        // Process the first pending file
        for file in jsonFiles {
            do {
                let data = try Data(contentsOf: file)
                let recipe = try JSONDecoder().decode(ImportedRecipe.self, from: data)
                log.log(
                    category: "import",
                    message: "Found pending recipe",
                    details: ["title": recipe.title, "file": file.lastPathComponent]
                )
                pendingRecipe = recipe
                pendingFileURL = file
                showingImportReview = true
                return
            } catch {
                log.log(
                    category: "import.error",
                    message: "Corrupt pending import, removing",
                    details: ["file": file.lastPathComponent, "error": "\(error)"]
                )
                try? FileManager.default.removeItem(at: file)
                continue
            }
        }
    }

    func confirmImport(context: ModelContext) {
        guard let imported = pendingRecipe else {
            log.log(category: "import.error", message: "confirmImport called with no pending recipe")
            return
        }

        let recipe = Recipe()
        recipe.name = imported.title
        recipe.instructions = imported.instructions.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n\n")
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

        // Log normalizations that were applied during import
        logNormalizations(imported)

        log.log(
            category: "import",
            message: "Recipe imported to SwiftData",
            details: ["title": imported.title, "ingredients": "\(imported.ingredients.count)"]
        )
        cleanup()
    }

    func cancelImport() {
        log.log(category: "import", message: "Import cancelled")
        cleanup()
    }

    // MARK: - Normalization Logging

    private func logNormalizations(_ imported: ImportedRecipe) {
        guard !imported.ingredientNormalizations.isEmpty else { return }

        // Log each normalization locally
        for norm in imported.ingredientNormalizations {
            log.log(
                category: "import.normalize",
                message: "Ingredient cleaned: \(norm.type)",
                details: [
                    "original": norm.original,
                    "cleaned": norm.cleaned,
                    "source": imported.sourceURL,
                ]
            )
        }

        log.log(
            category: "import.normalize",
            message: "Total normalizations applied",
            details: [
                "count": "\(imported.ingredientNormalizations.count)",
                "source": imported.sourceURL,
            ]
        )

        // Queue for server reporting if user has opted in
        if ImprovementReporting.isEnabled {
            queueForServerReport(imported)
        }
    }

    private func queueForServerReport(_ imported: ImportedRecipe) {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: DebugLog.appGroupID
            )
        else { return }

        let reportDir = containerURL.appendingPathComponent("PendingReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)

        let entries = imported.ingredientNormalizations.map { norm -> [String: String] in
            [
                "source_url": imported.sourceURL,
                "original_text": norm.original,
                "cleaned_text": norm.cleaned,
                "normalization_type": norm.type,
            ]
        }

        let payload: [String: Any] = ["entries": entries]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let filename = "normalize-\(UUID().uuidString).json"
        let fileURL = reportDir.appendingPathComponent(filename)
        try? data.write(to: fileURL)

        log.log(
            category: "import.report",
            message: "Normalization report queued",
            details: ["file": filename, "entries": "\(entries.count)"]
        )
    }

    // MARK: - Private

    private func cleanup() {
        if let url = pendingFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingRecipe = nil
        pendingFileURL = nil
        showingImportReview = false
    }
}
