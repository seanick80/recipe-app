import Foundation
import SwiftData

@Model
final class ShoppingTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    // Sync metadata (mirrors Recipe). All optional/defaulted to stay CloudKit-safe.
    var updatedAt: Date = Date()
    var serverId: String? = nil
    var needsSync: Bool = false
    var lastSyncedAt: Date? = nil
    var locallyDeleted: Bool = false
    var pendingRemoteDelete: Bool = false
    var deletedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template)
    var items: [TemplateItem]?

    init(name: String = "", sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Flags the template for the next sync push and bumps its local
    /// modification time. Call at every mutation site (including item changes).
    func markDirty() {
        needsSync = true
        updatedAt = Date()
    }
}
