import Foundation
import SwiftData
import SwiftUI

/// Orchestrates the detection-to-pantry pipeline: takes raw detection results,
/// triages them via confidence thresholds, maps labels to pantry items, merges
/// duplicates, and provides grouped lists for the review UI.
@Observable
class PantryViewModel {
    // MARK: - Triaged Item Groups

    /// Items above the auto-add threshold — will be saved without user review.
    var autoAddItems: [PantryItemModel] = []

    /// Items in the confirm range — shown to the user for approval.
    var confirmItems: [PantryItemModel] = []

    /// Items below the reject threshold — hidden by default.
    var rejectedItems: [PantryItemModel] = []

    var isProcessing: Bool = false

    var hasResults: Bool {
        !autoAddItems.isEmpty || !confirmItems.isEmpty
    }

    var itemsToSaveCount: Int {
        autoAddItems.count
    }

    // MARK: - Process Detections

    /// Takes raw detection results from FoodDetectionViewModel, runs triage,
    /// maps labels to pantry items, merges duplicates, and populates the
    /// three item groups.
    func processDetections(_ results: [DetectionResult]) {
        let triaged = triageDetections(results)

        autoAddItems = mapAndMerge(triaged.autoAdd)
        confirmItems = mapAndMerge(triaged.confirm)
        rejectedItems = mapAndMerge(triaged.reject)
    }

    // MARK: - User Actions

    /// Moves an item to auto-add (user approved). Works across all groups.
    func confirmItem(id: UUID) {
        if let index = confirmItems.firstIndex(where: { $0.id == id }) {
            let item = confirmItems.remove(at: index)
            autoAddItems.append(item)
        } else if let index = rejectedItems.firstIndex(where: { $0.id == id }) {
            let item = rejectedItems.remove(at: index)
            autoAddItems.append(item)
        }
        autoAddItems.sort { $0.name < $1.name }
    }

    /// Moves an item to rejected (user declined). Works across all groups.
    func rejectItem(id: UUID) {
        if let index = confirmItems.firstIndex(where: { $0.id == id }) {
            let item = confirmItems.remove(at: index)
            rejectedItems.append(item)
        } else if let index = autoAddItems.firstIndex(where: { $0.id == id }) {
            let item = autoAddItems.remove(at: index)
            rejectedItems.append(item)
        }
        rejectedItems.sort { $0.name < $1.name }
    }

    /// Edits the display name of an item across any group.
    func editItemName(id: UUID, newName: String) {
        if let index = autoAddItems.firstIndex(where: { $0.id == id }) {
            autoAddItems[index].name = newName
            return
        }
        if let index = confirmItems.firstIndex(where: { $0.id == id }) {
            confirmItems[index].name = newName
            return
        }
        if let index = rejectedItems.firstIndex(where: { $0.id == id }) {
            rejectedItems[index].name = newName
            return
        }
    }

    /// Resets all state, discarding any pending results.
    func reset() {
        autoAddItems.removeAll()
        confirmItems.removeAll()
        rejectedItems.removeAll()
        isProcessing = false
    }

    // MARK: - Persistence

    /// Saves all auto-add items as PantryItem SwiftData objects.
    func saveToStore(modelContext: ModelContext) {
        for item in autoAddItems {
            let pantryItem = PantryItem(
                name: item.name,
                category: item.category,
                quantity: item.quantity,
                unit: item.unit,
                confidence: item.confidence,
                detectionSource: DetectionSource.yolo.rawValue,
                detectedAt: item.detectedAt
            )
            modelContext.insert(pantryItem)
        }
        autoAddItems.removeAll()
        confirmItems.removeAll()
        rejectedItems.removeAll()
    }

    // MARK: - Private Helpers

    /// Maps detection results to pantry items and merges duplicates.
    private func mapAndMerge(_ detections: [DetectionResult]) -> [PantryItemModel] {
        let items = detections.compactMap { detection in
            mapYOLOLabel(detection.label, confidence: detection.confidence)
        }
        return mergePantryDetections(items)
    }
}
