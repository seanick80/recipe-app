import Foundation
import SwiftUI
import UIKit
import Vision

/// Processes OCR scans in the background. Lives at the ScannerTabView level so
/// it survives the camera sheet dismissal. After capture, the camera sheet
/// dismisses immediately and processing continues here.
///
/// The pipeline delegates algorithms to pure-Swift modules in `SharedLogic/`:
///   VNRecognizeTextRequest -> [OCRLine]
///     -> assessImageQuality  (retake gate)
///     -> separateHandwritten (drop margin notes)
///     -> sectionFromHeader   (recipe mode: route each line by section header)
///     -> parseListLine / parseIngredientLine
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
        /// Fuzzy-match suggestion for OCR misreads (nil if name looks correct).
        var suggestion: String?

        static func == (lhs: ParsedItem, rhs: ParsedItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    var state: State = .idle

    /// Instructions text extracted from a recipe scan. Populated only in recipe
    /// mode when zone classification finds instruction blocks; the review sheet
    /// reads this to save into `Recipe.instructions`.
    var parsedInstructions: String = ""

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

    /// Set to true when a shopping-list scan detects recipe content. The
    /// review sheet reads this to suggest switching to recipe mode.
    var detectedRecipeInListScan: Bool = false

    /// Kick off background OCR for a shopping list. Returns immediately.
    func processShoppingList(image: UIImage) {
        scanMode = .shoppingList
        parsedInstructions = ""
        state = .processing

        let scanID = Self.newScanID()
        DebugLog.shared.log(
            category: "ocr.start",
            message: "shopping list scan",
            details: ["scanID": scanID, "imgSize": "\(Int(image.size.width))x\(Int(image.size.height))"]
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            let (recipeDetected, result) = await Self.runOCRAndParseList(image: image, scanID: scanID)
            await MainActor.run {
                guard let self else { return }
                self.detectedRecipeInListScan = recipeDetected
                self.finishProcessing(result, instructions: "")
            }
        }
    }

    /// Kick off background OCR for a recipe. Returns immediately.
    func processRecipe(image: UIImage) {
        scanMode = .recipe
        parsedInstructions = ""
        state = .processing

        let scanID = Self.newScanID()
        DebugLog.shared.log(
            category: "ocr.start",
            message: "recipe scan",
            details: ["scanID": scanID, "imgSize": "\(Int(image.size.width))x\(Int(image.size.height))"]
        )

        Task.detached(priority: .userInitiated) { [weak self] in
            let (result, instructions) = await Self.runOCRAndParseRecipe(image: image, scanID: scanID)
            await MainActor.run {
                guard let self else { return }
                self.finishProcessing(result, instructions: instructions)
            }
        }
    }

    /// Short correlation ID included on every event from a single scan so
    /// that one scan's log lines can be filtered out of a busy log.
    private static func newScanID() -> String {
        String(UUID().uuidString.prefix(8))
    }

    private func finishProcessing(
        _ result: Result<[ParsedItem], Error>,
        instructions: String
    ) {
        switch result {
        case .success(let items):
            self.parsedInstructions = instructions
            self.state =
                items.isEmpty
                ? .failed(message: "No items found. Try again with better lighting.")
                : .ready(items: items)
        case .failure(let error):
            self.parsedInstructions = ""
            self.state = .failed(message: error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        parsedInstructions = ""
        detectedRecipeInListScan = false
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

    // MARK: - Vision OCR -> OCRLine

    /// Runs Vision text recognition and maps each observation to the pure-Swift
    /// `OCRLine` value used by QualityGate and ZoneClassifier.
    ///
    /// Vision's `boundingBox` uses normalized coordinates with origin at the
    /// *bottom-left*. `NormalizedBox` uses origin at the top-left (matches
    /// typical image coords), so we flip the y-axis here.
    private static func runOCR(image: UIImage, scanID: String) throws -> [OCRLine] {
        guard let cgImage = image.cgImage else {
            DebugLog.shared.log(
                category: "ocr.error",
                message: "invalidImage",
                details: ["scanID": scanID, "stage": "vision"]
            )
            throw ScanError.invalidImage
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        try handler.perform([request])

        guard let observations = request.results else {
            DebugLog.shared.log(
                category: "ocr.vision",
                message: "no observations",
                details: ["scanID": scanID, "lines": "0"]
            )
            return []
        }
        let lines = observations.compactMap { observation -> OCRLine? in
            guard let top = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            let normBox = NormalizedBox(
                x: Double(box.origin.x),
                y: Double(1.0 - box.origin.y - box.size.height),
                width: Double(box.size.width),
                height: Double(box.size.height)
            )
            return OCRLine(
                text: top.string,
                confidence: Double(top.confidence),
                boundingBox: normBox
            )
        }

        let confs = lines.map(\.confidence).sorted()
        let medianConf = confs.isEmpty ? 0 : confs[confs.count / 2]
        DebugLog.shared.log(
            category: "ocr.vision",
            message: "recognized text",
            details: [
                "scanID": scanID,
                "lines": "\(lines.count)",
                "medianConf": String(format: "%.3f", medianConf),
                "text": lines.map(\.text).joined(separator: "\n"),
            ]
        )
        return lines
    }

    /// Applies the quality gate and handwriting separation. Returns the printed
    /// lines if the image is acceptable, or throws `ScanError.lowQuality` with
    /// a user-friendly reason otherwise.
    private static func gatedOCR(image: UIImage, scanID: String) throws -> [OCRLine] {
        let lines = try runOCR(image: image, scanID: scanID)
        let quality = assessImageQuality(lines: lines)
        DebugLog.shared.log(
            category: "ocr.quality",
            message: quality.isAcceptable ? "acceptable" : "rejected",
            details: [
                "scanID": scanID,
                "acceptable": quality.isAcceptable ? "true" : "false",
                "reason": quality.reason,
            ]
        )
        guard quality.isAcceptable else {
            throw ScanError.lowQuality(reason: quality.reason)
        }
        let (printed, handwritten) = separateHandwritten(lines: lines)
        DebugLog.shared.log(
            category: "ocr.handwriting",
            message: "separated printed vs handwritten",
            details: [
                "scanID": scanID,
                "printed": "\(printed.count)",
                "handwritten": "\(handwritten.count)",
                "handwrittenText": handwritten.map(\.text).joined(separator: " | "),
            ]
        )
        return printed
    }

    // MARK: - Shopping list path

    private static func runOCRAndParseList(
        image: UIImage,
        scanID: String
    ) async -> (recipeDetected: Bool, result: Result<[ParsedItem], Error>) {
        let printed: [OCRLine]
        do {
            printed = try gatedOCR(image: image, scanID: scanID)
        } catch {
            DebugLog.shared.log(
                category: "ocr.error",
                message: error.localizedDescription,
                details: ["scanID": scanID, "stage": "list"]
            )
            return (false, .failure(error))
        }

        // Check if the scanned content looks like a recipe rather than a list.
        let allText = printed.map(\.text).joined(separator: "\n")
        let contentType = detectContentType(allText)
        let isRecipeContent = contentType == .recipe

        if isRecipeContent {
            DebugLog.shared.log(
                category: "ocr.detect",
                message: "recipe content detected in shopping list scan",
                details: ["scanID": scanID]
            )
        }

        let vocab = groceryVocabulary()

        let items = printed.compactMap { line -> ParsedItem? in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let parsed = parseListLine(trimmed) {
                let suggestion = suggestCorrection(parsed.name, vocabulary: vocab)
                return ParsedItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: categorizeGroceryItem(suggestion ?? parsed.name),
                    suggestion: suggestion
                )
            }
            let suggestion = suggestCorrection(trimmed, vocabulary: vocab)
            return ParsedItem(
                name: trimmed,
                quantity: 1,
                unit: "",
                category: categorizeGroceryItem(suggestion ?? trimmed),
                suggestion: suggestion
            )
        }

        DebugLog.shared.log(
            category: "ocr.parsed",
            message: "list parse complete",
            details: [
                "scanID": scanID,
                "mode": "list",
                "items": "\(items.count)",
                "itemNames": items.map(\.name).joined(separator: " | "),
                "recipeDetected": isRecipeContent ? "true" : "false",
                "corrections": items.compactMap(\.suggestion).joined(separator: " | "),
            ]
        )
        return (isRecipeContent, .success(items))
    }

    // MARK: - Recipe path (section-header routing)
    //
    // Earlier versions of this pipeline grouped lines into geometric blocks
    // (by y-coordinate gaps) and then content-classified each block. That
    // failed on dense web-recipe screenshots: everything fused into one
    // block, got classified as "instructions", and 0 ingredients survived.
    //
    // The current approach walks the OCR lines in Vision's natural reading
    // order and uses explicit section headers ("Ingredients", "Method",
    // "Step 1") to route each subsequent line to the correct bucket. If a
    // recipe has no headers (e.g. a cookbook page with just an ingredient
    // list), the final fallback below rescues well-structured ingredient
    // lines regardless of section.

    private static func runOCRAndParseRecipe(
        image: UIImage,
        scanID: String
    ) async -> (Result<[ParsedItem], Error>, String) {
        let printed: [OCRLine]
        do {
            printed = try gatedOCR(image: image, scanID: scanID)
        } catch {
            DebugLog.shared.log(
                category: "ocr.error",
                message: error.localizedDescription,
                details: ["scanID": scanID, "stage": "recipe"]
            )
            return (.failure(error), "")
        }

        var titleText = ""
        var ingredientItems: [ParsedItem] = []
        var instructionSteps: [String] = []
        var currentSection: RecipeSection = .intro
        var sectionTransitions: [String] = []

        for line in printed {
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // A section header consumes the line and switches our routing.
            if let section = sectionFromHeader(trimmed) {
                if currentSection != section {
                    sectionTransitions.append("\(currentSection) → \(section) @ \"\(trimmed)\"")
                    currentSection = section
                }
                continue
            }

            // Drop nutrition-widget leftovers like "270•", "615°", "160g.".
            if isLikelyMetadataJunk(trimmed) { continue }

            switch currentSection {
            case .intro:
                // First non-junk line of a recipe page is treated as the title.
                // Subsequent intro narrative is ignored (we don't want
                // "This particular zucchini slice recipe..." polluting
                // ingredients or instructions).
                if titleText.isEmpty {
                    titleText = cleanRecipeTitle(trimmed)
                }

            case .ingredients:
                if let parsed = parseIngredientLine(trimmed) {
                    ingredientItems.append(
                        ParsedItem(
                            name: parsed.name,
                            quantity: parsed.quantity,
                            unit: parsed.unit,
                            category: categorizeGroceryItem(parsed.name)
                        )
                    )
                }

            case .instructions:
                let cleaned = cleanInstructionLine(trimmed)
                if !cleaned.isEmpty {
                    instructionSteps.append(cleaned)
                }
            }
        }

        DebugLog.shared.log(
            category: "ocr.sections",
            message: "section routing complete",
            details: [
                "scanID": scanID,
                "finalSection": "\(currentSection)",
                "transitions": sectionTransitions.joined(separator: " | "),
                "ingredientCount": "\(ingredientItems.count)",
                "instructionCount": "\(instructionSteps.count)",
            ]
        )

        // Assemble review items: title marker, ingredients, instruction summary.
        var items: [ParsedItem] = []
        if !titleText.isEmpty {
            items.append(
                ParsedItem(
                    name: "Recipe: \(titleText)",
                    quantity: 0,
                    unit: "",
                    category: "Recipe"
                )
            )
        }
        items.append(contentsOf: ingredientItems)
        if !instructionSteps.isEmpty {
            items.append(
                ParsedItem(
                    name: "Instructions (\(instructionSteps.count) steps)",
                    quantity: 0,
                    unit: "",
                    category: "Recipe"
                )
            )
        }

        let instructionsText = instructionSteps.joined(separator: "\n")
        DebugLog.shared.log(
            category: "ocr.parsed",
            message: "recipe parse complete",
            details: [
                "scanID": scanID,
                "mode": "recipe",
                "title": titleText,
                "ingredients": "\(ingredientItems.count)",
                "steps": "\(instructionSteps.count)",
                "ingredientNames": ingredientItems.map(\.name).joined(separator: " | "),
                "instructionsText": instructionsText,
            ]
        )
        return (.success(items), instructionsText)
    }

    enum ScanError: LocalizedError {
        case invalidImage
        case lowQuality(reason: String)

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not read the captured image."
            case .lowQuality(let reason):
                let detail = reason.isEmpty ? "" : " (\(reason))"
                return
                    "Image looks too blurry or dim to read reliably\(detail)."
                    + " Try again with more light or a steadier shot."
            }
        }
    }
}
