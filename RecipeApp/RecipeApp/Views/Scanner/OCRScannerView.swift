import SwiftData
import SwiftUI

/// Captures a photo and runs on-device OCR to extract text. Supports two modes:
/// - Shopping list import: OCR text → ListLineParser → grocery items
/// - Recipe import: OCR text → OCRParser → structured recipe
struct OCRScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var cameraVM = CameraViewModel()
    @State private var ocrVM = OCRViewModel()
    @State private var phase: ScanPhase = .camera
    @State private var parsedItems: [EditableItem] = []

    let mode: OCRScanMode
    let groceryList: GroceryList?

    enum OCRScanMode {
        case shoppingList
        case recipe
    }

    enum ScanPhase {
        case camera
        case processing
        case review
    }

    struct EditableItem: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var unit: String
        var category: String
        var included: Bool = true
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .camera:
                    cameraPhaseView
                case .processing:
                    processingView
                case .review:
                    reviewPhaseView
                }
            }
            .navigationTitle(mode == .shoppingList ? "Scan List" : "Scan Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                cameraVM.configure()
                cameraVM.startSession()
            }
            .onDisappear {
                cameraVM.stopSession()
            }
        }
    }

    // MARK: - Camera Phase

    private var cameraPhaseView: some View {
        ZStack {
            CameraPreviewView(session: cameraVM.session)
                .ignoresSafeArea()

            CameraCoachingOverlay(
                tiltWarning: cameraVM.tiltWarning,
                brightnessWarning: cameraVM.brightnessWarning,
                onCapture: {
                    Task { await captureAndProcess() }
                }
            )

            // Guide text
            VStack {
                Text(
                    mode == .shoppingList
                        ? "Photograph your shopping list"
                        : "Photograph the recipe"
                )
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 100)

                Spacer()
            }
        }
    }

    // MARK: - Processing Phase

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Recognizing text...")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Review Phase

    private var reviewPhaseView: some View {
        VStack {
            if parsedItems.isEmpty {
                ContentUnavailableView(
                    "No Items Found",
                    systemImage: "text.magnifyingglass",
                    description: Text("Could not parse any items from the photo. Try again with better lighting.")
                )
            } else {
                List {
                    Section("Found \(parsedItems.filter(\.included).count) items") {
                        ForEach($parsedItems) { $item in
                            HStack {
                                Toggle(isOn: $item.included) {
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                        if item.quantity != 1 || !item.unit.isEmpty {
                                            Text("\(formatQuantity(item.quantity)) \(item.unit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .tint(.accentColor)
                            }
                        }
                    }
                }

                HStack {
                    Button("Retake") {
                        phase = .camera
                        parsedItems = []
                        ocrVM.reset()
                        cameraVM.startSession()
                    }
                    .buttonStyle(.bordered)

                    Button("Add \(parsedItems.filter(\.included).count) Items") {
                        addItemsToList()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedItems.filter(\.included).isEmpty)
                }
                .padding()
            }
        }
    }

    // MARK: - Actions

    private func captureAndProcess() async {
        phase = .processing
        cameraVM.stopSession()

        guard let image = await cameraVM.capturePhoto() else {
            phase = .camera
            cameraVM.startSession()
            return
        }

        await ocrVM.recognizeText(from: image)

        let text = ocrVM.fullText
        guard !text.isEmpty else {
            phase = .camera
            cameraVM.startSession()
            return
        }

        switch mode {
        case .shoppingList:
            parseAsShoppingList(text)
        case .recipe:
            parseAsRecipe(text)
        }

        phase = .review
    }

    private func parseAsShoppingList(_ text: String) {
        // Use the pure Swift ListLineParser
        let lines = text.components(separatedBy: .newlines)
        parsedItems = lines.compactMap { line -> EditableItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Try structured parsing first
            if let parsed = parseListLinePure(trimmed) {
                return EditableItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: guessCategory(parsed.name)
                )
            }
            // Fallback: treat whole line as item name
            return EditableItem(name: trimmed, quantity: 1, unit: "", category: "Other")
        }
    }

    private func parseAsRecipe(_ text: String) {
        // For recipe mode, extract ingredients section
        // Full recipe parsing will be handled by the recipe import view
        let lines = text.components(separatedBy: .newlines)
        parsedItems = lines.compactMap { line -> EditableItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let parsed = parseListLinePure(trimmed) {
                return EditableItem(
                    name: parsed.name,
                    quantity: parsed.quantity,
                    unit: parsed.unit,
                    category: guessCategory(parsed.name)
                )
            }
            return EditableItem(name: trimmed, quantity: 1, unit: "", category: "Other")
        }
    }

    /// Wraps the pure Swift parseListLine to avoid name collision with any
    /// future iOS-specific parser.
    private func parseListLinePure(_ line: String) -> (name: String, quantity: Double, unit: String)? {
        // The pure Swift models are compiled into the app target.
        // ParsedListItem is defined in Models/ListLineParser.swift
        guard let parsed = parseListLine(line) else { return nil }
        return (parsed.name, parsed.quantity, parsed.unit)
    }

    /// Simple keyword-based category guess for OCR-parsed items.
    private func guessCategory(_ name: String) -> String {
        let lower = name.lowercased()
        let categoryKeywords: [(keywords: [String], category: String)] = [
            (["milk", "cheese", "yogurt", "butter", "cream", "egg"], "Dairy"),
            (["chicken", "beef", "pork", "fish", "meat", "salmon", "shrimp", "bacon", "sausage"], "Meat"),
            (
                [
                    "apple", "banana", "lettuce", "tomato", "onion", "potato", "carrot", "pepper", "garlic",
                    "avocado", "broccoli", "spinach", "cucumber", "celery", "mushroom", "grape", "berry",
                ], "Produce"
            ),
            (["bread", "bagel", "muffin", "roll", "bun", "croissant"], "Bakery"),
            (["rice", "pasta", "flour", "sugar", "oil", "can", "sauce", "soup", "bean", "cereal"], "Dry & Canned"),
            (["frozen", "ice cream", "pizza"], "Frozen"),
            (["chip", "cookie", "cracker", "candy", "chocolate", "snack", "nut"], "Snacks"),
            (["water", "juice", "soda", "coffee", "tea", "drink", "beer", "wine"], "Beverages"),
            (["ketchup", "mustard", "mayo", "dressing", "vinegar", "hot sauce", "soy sauce"], "Condiments"),
            (["paper", "towel", "soap", "detergent", "trash bag", "sponge", "cleaner"], "Household"),
        ]
        for (keywords, category) in categoryKeywords {
            for keyword in keywords {
                if lower.contains(keyword) { return category }
            }
        }
        return "Other"
    }

    private func addItemsToList() {
        guard let list = groceryList else { return }
        for item in parsedItems where item.included {
            let groceryItem = GroceryItem(
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category
            )
            groceryItem.groceryList = list
            modelContext.insert(groceryItem)
        }
    }

    private func formatQuantity(_ qty: Double) -> String {
        if qty == Double(Int(qty)) { return "\(Int(qty))" }
        return String(format: "%.1f", qty)
    }
}
