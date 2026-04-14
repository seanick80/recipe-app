import Foundation
import SwiftUI
import UIKit
import Vision

/// Processes OCR scans in the background. Lives at the ScannerTabView level so
/// it survives the camera sheet dismissal. After capture, the camera sheet
/// dismisses immediately and processing continues here.
@Observable
class ScanProcessor {
    enum State: Equatable {
        case idle
        case processing
        case ready(items: [ParsedItem])
        case failed(message: String)
    }

    struct ParsedItem: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        var category: String
        var included: Bool = true

        static func == (lhs: ParsedItem, rhs: ParsedItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    var state: State = .idle

    var isProcessing: Bool {
        if case .processing = state { return true }
        return false
    }

    var hasResults: Bool {
        if case .ready = state { return true }
        return false
    }

    var parsedItems: [ParsedItem] {
        if case .ready(let items) = state { return items }
        return []
    }

    /// Which scan produced the current results — affects review sheet behavior.
    enum ScanMode {
        case shoppingList
        case recipe
    }

    var scanMode: ScanMode = .shoppingList

    /// Kick off background OCR for a shopping list. Returns immediately.
    func processShoppingList(image: UIImage) {
        scanMode = .shoppingList
        state = .processing

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.runOCRAndParseList(image: image)
            await MainActor.run {
                guard let self else { return }
                self.finishProcessing(result)
            }
        }
    }

    /// Kick off background OCR for a recipe. Returns immediately.
    func processRecipe(image: UIImage) {
        scanMode = .recipe
        state = .processing

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.runOCRAndParseRecipe(image: image)
            await MainActor.run {
                guard let self else { return }
                self.finishProcessing(result)
            }
        }
    }

    private func finishProcessing(_ result: Result<[ParsedItem], Error>) {
        switch result {
        case .success(let items):
            self.state =
                items.isEmpty
                ? .failed(message: "No items found. Try again with better lighting.")
                : .ready(items: items)
        case .failure(let error):
            self.state = .failed(message: error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
    }

    /// Updates inclusion state for an item by ID.
    func toggleItem(id: UUID) {
        guard case .ready(var items) = state,
            let index = items.firstIndex(where: { $0.id == id })
        else { return }
        items[index].included.toggle()
        state = .ready(items: items)
    }

    /// Updates the name of an item by ID.
    func updateItemName(id: UUID, name: String) {
        guard case .ready(var items) = state,
            let index = items.firstIndex(where: { $0.id == id })
        else { return }
        items[index].name = name
        state = .ready(items: items)
    }

    // MARK: - Background OCR (off main thread)

    private static func runOCR(image: UIImage) throws -> [String] {
        guard let cgImage = image.cgImage else {
            throw ScanError.invalidImage
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        try handler.perform([request])

        guard let observations = request.results else { return [] }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    private static func runOCRAndParseList(image: UIImage) async -> Result<[ParsedItem], Error> {
        let lines: [String]
        do {
            lines = try runOCR(image: image)
        } catch {
            return .failure(error)
        }

        let items = lines.compactMap { line -> ParsedItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let parsed = parseListLine(trimmed) {
                return ParsedItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: categorizeGroceryItem(parsed.name)
                )
            }
            return ParsedItem(name: trimmed, quantity: 1, unit: "", category: categorizeGroceryItem(trimmed))
        }

        return .success(items)
    }

    private static func runOCRAndParseRecipe(image: UIImage) async -> Result<[ParsedItem], Error> {
        let lines: [String]
        do {
            lines = try runOCR(image: image)
        } catch {
            return .failure(error)
        }

        let fullText = lines.joined(separator: "\n")
        let parsed = parseRecipeText(fullText)

        // Convert parsed recipe ingredients to ParsedItems for review
        var items: [ParsedItem] = []

        // Add title as a non-ingredient marker if found
        if !parsed.title.isEmpty {
            items.append(
                ParsedItem(
                    name: "Recipe: \(parsed.title)",
                    quantity: 0,
                    unit: "",
                    category: "Recipe"
                )
            )
        }

        for ingredient in parsed.ingredients {
            items.append(
                ParsedItem(
                    name: ingredient.name,
                    quantity: ingredient.quantity,
                    unit: ingredient.unit,
                    category: categorizeGroceryItem(ingredient.name)
                )
            )
        }

        // Add instructions as a single item if present
        if !parsed.instructions.isEmpty {
            items.append(
                ParsedItem(
                    name: "Instructions (\(parsed.instructions.count) steps)",
                    quantity: 0,
                    unit: "",
                    category: "Recipe"
                )
            )
        }

        return .success(items)
    }

    enum ScanError: LocalizedError {
        case invalidImage
        var errorDescription: String? { "Could not read the captured image." }
    }
}
