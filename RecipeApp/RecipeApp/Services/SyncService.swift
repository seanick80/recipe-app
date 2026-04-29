import Foundation
import SwiftData

@MainActor
@Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncError: String?
    private(set) var hasWriteFailures = false
    private(set) var conflictCount = 0

    private let apiClient: APIClient
    private var modelContext: ModelContext?

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Force Full Sync

    func forceFullSync() async {
        guard let modelContext else { return }
        do {
            let localRecipes = try fetchLocalRecipes(modelContext)
            for recipe in localRecipes {
                recipe.lastSyncedAt = nil
            }
            try modelContext.save()
        } catch {
            // Non-critical — sync will still work, just won't force re-download
        }
        await sync()
    }

    // MARK: - Main Entry Point

    func sync() async {
        guard !isSyncing else { return }
        guard KeychainService.loadToken() != nil else { return }
        guard let modelContext else { return }

        isSyncing = true
        conflictCount = 0
        var writeFailures = 0

        do {
            let serverList = try await apiClient.fetchRecipeList()
            let serverIDs = Set(serverList.map { $0.id })
            let serverMap = Dictionary(
                uniqueKeysWithValues: serverList.map { ($0.id, $0.updatedAt) }
            )

            let localRecipes = try fetchLocalRecipes(modelContext)

            // Detect first-sync condition
            let isFirstSync =
                serverList.isEmpty
                && localRecipes.contains(where: { $0.serverId == nil && !$0.locallyDeleted })

            if isFirstSync {
                writeFailures += await performFirstSync(
                    localRecipes: localRecipes,
                    modelContext: modelContext
                )
            } else {
                // Pull changes from server
                try await pullChanges(
                    serverList: serverList,
                    serverIDs: serverIDs,
                    serverMap: serverMap,
                    localRecipes: localRecipes,
                    modelContext: modelContext
                )

                // Push local changes to server
                writeFailures += await pushChanges(
                    localRecipes: localRecipes,
                    modelContext: modelContext
                )

                // Process deletions (both directions handled in pull + this)
                writeFailures += await processDeletions(
                    localRecipes: localRecipes,
                    modelContext: modelContext
                )
            }

            purgeExpiredDeletions(modelContext: modelContext)
            try modelContext.save()

            hasWriteFailures = writeFailures > 0
            if writeFailures > 0 {
                lastSyncError = "Could not sync \(writeFailures) recipe\(writeFailures == 1 ? "" : "s")"
            } else {
                lastSyncError = nil
            }
            lastSyncDate = Date()
        } catch let apiError as APIError where apiError == .unauthorized {
            lastSyncError = "Session expired — sign in again"
        } catch {
            lastSyncError = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - First Sync (Scenario 8)

    private func performFirstSync(
        localRecipes: [Recipe],
        modelContext: ModelContext
    ) async -> Int {
        var failures = 0
        let unsyncedRecipes = localRecipes.filter {
            $0.serverId == nil && !$0.locallyDeleted
        }

        for recipe in unsyncedRecipes {
            do {
                let dto = recipeToDTO(recipe)
                let response = try await apiClient.createRecipe(dto)
                if let serverID = response.id {
                    recipe.serverId = serverID.uuidString
                    recipe.lastSyncedAt = Date()
                    recipe.needsSync = false
                }
            } catch {
                failures += 1
            }
        }
        return failures
    }

    // MARK: - Pull Changes (Scenarios 3, 4, 5, 7)

    private func pullChanges(
        serverList: [RecipeListItemDTO],
        serverIDs: Set<UUID>,
        serverMap: [UUID: Date],
        localRecipes: [Recipe],
        modelContext: ModelContext
    ) async throws {
        let localByServerID: [UUID: Recipe] = Dictionary(
            uniqueKeysWithValues: localRecipes.compactMap { recipe in
                guard let sid = recipe.serverId, let uuid = UUID(uuidString: sid) else {
                    return nil
                }
                return (uuid, recipe)
            }
        )

        // Server-only recipes -> download (Scenario 3)
        for item in serverList {
            if localByServerID[item.id] == nil {
                do {
                    let dto = try await apiClient.fetchRecipe(id: item.id)
                    let recipe = dtoToRecipe(dto)
                    modelContext.insert(recipe)
                } catch {
                    // Read failure — silent, retry next sync
                }
            }
        }

        // Recipes that exist both locally and on server
        for (serverID, localRecipe) in localByServerID {
            guard serverIDs.contains(serverID) else {
                // Scenario 7: Server deleted this recipe
                if !localRecipe.locallyDeleted {
                    localRecipe.locallyDeleted = true
                    localRecipe.deletedAt = Date()
                }
                continue
            }

            guard let serverUpdatedAt = serverMap[serverID] else { continue }
            let localLastSynced = localRecipe.lastSyncedAt ?? .distantPast
            let serverIsNewer = serverUpdatedAt > localLastSynced

            if serverIsNewer && localRecipe.needsSync {
                // Scenario 5: Conflict — both sides changed
                do {
                    let dto = try await apiClient.fetchRecipe(id: serverID)
                    resolveConflict(
                        local: localRecipe,
                        serverDTO: dto,
                        modelContext: modelContext
                    )
                } catch {
                    // Read failure — skip conflict resolution, retry next sync
                }
            } else if serverIsNewer {
                // Scenario 4: Server newer, no local edits — overwrite
                do {
                    let dto = try await apiClient.fetchRecipe(id: serverID)
                    applyDTO(dto, to: localRecipe, modelContext: modelContext)
                } catch {
                    // Read failure — silent, retry next sync
                }
            }
        }
    }

    // MARK: - Push Changes (Scenarios 1, 2)

    private func pushChanges(
        localRecipes: [Recipe],
        modelContext: ModelContext
    ) async -> Int {
        var failures = 0
        let dirtyRecipes = localRecipes.filter {
            $0.needsSync && !$0.locallyDeleted
        }

        for recipe in dirtyRecipes {
            do {
                let dto = recipeToDTO(recipe)
                if let serverIDString = recipe.serverId,
                    let serverID = UUID(uuidString: serverIDString)
                {
                    // Scenario 2: Update existing
                    _ = try await apiClient.updateRecipe(
                        id: serverID,
                        dto
                    )
                    recipe.lastSyncedAt = Date()
                    recipe.needsSync = false
                } else {
                    // Scenario 1: Upload new
                    let response = try await apiClient.createRecipe(dto)
                    if let newID = response.id {
                        recipe.serverId = newID.uuidString
                        recipe.lastSyncedAt = Date()
                        recipe.needsSync = false
                    }
                }
            } catch {
                failures += 1
            }
        }
        return failures
    }

    // MARK: - Process Deletions (Scenario 6)

    private func processDeletions(
        localRecipes: [Recipe],
        modelContext: ModelContext
    ) async -> Int {
        var failures = 0
        let deletedRecipes = localRecipes.filter { $0.locallyDeleted }

        for recipe in deletedRecipes {
            if let serverIDString = recipe.serverId,
                let serverID = UUID(uuidString: serverIDString)
            {
                // Has server ID — push delete to server
                do {
                    try await apiClient.deleteRecipe(id: serverID)
                    modelContext.delete(recipe)
                } catch let error as APIError where error == .notFound {
                    // Already gone on server — clean up locally
                    modelContext.delete(recipe)
                } catch {
                    // Network error — leave for retry
                    failures += 1
                }
            } else {
                // Never synced — just hard-delete
                modelContext.delete(recipe)
            }
        }
        return failures
    }

    // MARK: - Conflict Resolution (Scenario 5)

    private func resolveConflict(
        local: Recipe,
        serverDTO: RecipeDTO,
        modelContext: ModelContext
    ) {
        // Save local version as conflicted copy
        let dateString = DateFormatter.conflictDate.string(from: Date())
        let copy = Recipe(name: "\(local.name) (conflicted copy \(dateString))")
        copy.summary = local.summary
        copy.instructions = local.instructions
        copy.prepTimeMinutes = local.prepTimeMinutes
        copy.cookTimeMinutes = local.cookTimeMinutes
        copy.servings = local.servings
        copy.cuisine = local.cuisine
        copy.course = local.course
        copy.tags = local.tags
        copy.sourceURL = local.sourceURL
        copy.difficulty = local.difficulty
        copy.isFavorite = local.isFavorite
        copy.isPublished = local.isPublished
        copy.isConflictedCopy = true
        copy.needsSync = true
        // serverId = nil — it's a new recipe

        // Copy ingredients
        let copiedIngredients = (local.ingredients ?? []).map { orig in
            Ingredient(
                name: orig.name,
                quantity: orig.quantity,
                unit: orig.unit,
                category: orig.category,
                displayOrder: orig.displayOrder,
                notes: orig.notes
            )
        }
        copy.ingredients = copiedIngredients
        modelContext.insert(copy)

        // Overwrite local recipe with server version
        applyDTO(serverDTO, to: local, modelContext: modelContext)
        conflictCount += 1
    }

    // MARK: - Purge Expired Deletions

    private func purgeExpiredDeletions(modelContext: ModelContext) {
        let thirtyDaysAgo = Calendar.current.date(
            byAdding: .day,
            value: -30,
            to: Date()
        )!
        do {
            let allRecipes = try fetchLocalRecipes(modelContext)
            for recipe in allRecipes where recipe.locallyDeleted {
                if let deletedAt = recipe.deletedAt, deletedAt < thirtyDaysAgo {
                    modelContext.delete(recipe)
                }
            }
        } catch {
            // Non-critical — will retry next sync
        }
    }

    // MARK: - DTO Mapping

    private func recipeToDTO(_ recipe: Recipe) -> RecipeDTO {
        let ingredientDTOs = (recipe.ingredients ?? [])
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { ing in
                IngredientDTO(
                    id: nil,
                    name: ing.name,
                    quantity: ing.quantity,
                    unit: ing.unit,
                    category: ing.category,
                    displayOrder: ing.displayOrder,
                    notes: ing.notes
                )
            }
        return RecipeDTO(
            id: nil,
            name: recipe.name,
            summary: recipe.summary,
            instructions: recipe.instructions,
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            servings: recipe.servings,
            cuisine: recipe.cuisine,
            course: recipe.course,
            tags: recipe.tags,
            sourceURL: recipe.sourceURL,
            difficulty: recipe.difficulty,
            isFavorite: recipe.isFavorite,
            isPublished: recipe.isPublished,
            ingredients: ingredientDTOs,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func dtoToRecipe(_ dto: RecipeDTO) -> Recipe {
        let recipe = Recipe(name: dto.name)
        recipe.summary = dto.summary
        recipe.instructions = dto.instructions
        recipe.prepTimeMinutes = dto.prepTimeMinutes
        recipe.cookTimeMinutes = dto.cookTimeMinutes
        recipe.servings = dto.servings
        recipe.cuisine = dto.cuisine
        recipe.course = dto.course
        recipe.tags = dto.tags
        recipe.sourceURL = dto.sourceURL
        recipe.difficulty = dto.difficulty
        recipe.isFavorite = dto.isFavorite
        recipe.isPublished = dto.isPublished
        if let createdAt = dto.createdAt { recipe.createdAt = createdAt }
        if let updatedAt = dto.updatedAt { recipe.updatedAt = updatedAt }
        recipe.serverId = dto.id?.uuidString
        recipe.lastSyncedAt = Date()
        recipe.needsSync = false

        let ingredients = dto.ingredients.map { ingDTO in
            Ingredient(
                name: ingDTO.name,
                quantity: ingDTO.quantity,
                unit: ingDTO.unit,
                category: ingDTO.category,
                displayOrder: ingDTO.displayOrder,
                notes: ingDTO.notes
            )
        }
        recipe.ingredients = ingredients
        return recipe
    }

    private func applyDTO(
        _ dto: RecipeDTO,
        to recipe: Recipe,
        modelContext: ModelContext
    ) {
        recipe.name = dto.name
        recipe.summary = dto.summary
        recipe.instructions = dto.instructions
        recipe.prepTimeMinutes = dto.prepTimeMinutes
        recipe.cookTimeMinutes = dto.cookTimeMinutes
        recipe.servings = dto.servings
        recipe.cuisine = dto.cuisine
        recipe.course = dto.course
        recipe.tags = dto.tags
        recipe.sourceURL = dto.sourceURL
        recipe.difficulty = dto.difficulty
        recipe.isFavorite = dto.isFavorite
        recipe.isPublished = dto.isPublished
        if let createdAt = dto.createdAt { recipe.createdAt = createdAt }
        if let updatedAt = dto.updatedAt { recipe.updatedAt = updatedAt }

        // Replace ingredients
        for old in recipe.ingredients ?? [] {
            modelContext.delete(old)
        }
        let newIngredients = dto.ingredients.map { ingDTO in
            Ingredient(
                name: ingDTO.name,
                quantity: ingDTO.quantity,
                unit: ingDTO.unit,
                category: ingDTO.category,
                displayOrder: ingDTO.displayOrder,
                notes: ingDTO.notes
            )
        }
        recipe.ingredients = newIngredients

        recipe.lastSyncedAt = Date()
        recipe.needsSync = false
    }

    // MARK: - Helpers

    private func fetchLocalRecipes(_ modelContext: ModelContext) throws -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>()
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - APIError Equatable

extension APIError: Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.notFound, .notFound): return true
        case (.serverError(let a), .serverError(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Date Formatter

extension DateFormatter {
    static let conflictDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f
    }()
}
