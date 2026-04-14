import Foundation
import SwiftData

@Model
final class PantryItem {
    var id: UUID = UUID()
    var name: String = ""
    var category: String = "Other"
    var quantity: Int = 1
    var unit: String = ""
    var confidence: Double = 0
    var detectionSource: String = ""
    var detectedAt: Date = Date()
    var expiryDate: Date?
    var notes: String = ""

    init(
        name: String = "",
        category: String = "Other",
        quantity: Int = 1,
        unit: String = "",
        confidence: Double = 0,
        detectionSource: String = "",
        detectedAt: Date = Date(),
        expiryDate: Date? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.category = category
        self.quantity = quantity
        self.unit = unit
        self.confidence = confidence
        self.detectionSource = detectionSource
        self.detectedAt = detectedAt
        self.expiryDate = expiryDate
        self.notes = notes
    }
}
