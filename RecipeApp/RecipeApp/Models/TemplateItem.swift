import Foundation
import SwiftData

@Model
final class TemplateItem {
    var id: UUID = UUID()
    var name: String = ""
    var quantity: Double = 1
    var unit: String = ""
    var category: String = "Other"
    var sortOrder: Int = 0
    // Sync metadata: the server UUID once synced. Template items round-trip as
    // part of the parent template's aggregate (matches the RN client).
    var serverId: String? = nil
    var template: ShoppingTemplate?

    init(
        name: String = "",
        quantity: Double = 1,
        unit: String = "",
        category: String = "Other",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.category = category
        self.sortOrder = sortOrder
    }
}
