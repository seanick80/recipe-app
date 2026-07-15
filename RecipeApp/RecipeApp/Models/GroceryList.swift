import Foundation
import SwiftData

@Model
final class GroceryList {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var archivedAt: Date? = nil

    // Sync metadata (mirrors Recipe). `archivedAt` doubles as the server's
    // `archived_at`. All optional/defaulted to stay CloudKit-safe.
    var updatedAt: Date = Date()
    var serverId: String? = nil
    var needsSync: Bool = false
    var lastSyncedAt: Date? = nil
    var locallyDeleted: Bool = false
    var pendingRemoteDelete: Bool = false
    var deletedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \GroceryItem.groceryList)
    var items: [GroceryItem]?

    var completedCount: Int {
        (items ?? []).filter { $0.isChecked }.count
    }

    init(name: String = "", items: [GroceryItem] = []) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.items = items
    }

    /// Flags the list for the next sync push and bumps its local modification
    /// time. Call at every mutation site (including item add/edit/remove).
    func markDirty() {
        needsSync = true
        updatedAt = Date()
    }
}
