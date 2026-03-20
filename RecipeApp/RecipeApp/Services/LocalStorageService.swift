import Foundation
import SwiftData

struct LocalStorageService {
    let modelContext: ModelContext

    func allRecipes() throws -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func allGroceryLists() throws -> [GroceryList] {
        let descriptor = FetchDescriptor<GroceryList>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    func save() throws {
        try modelContext.save()
    }
}
