import AVFoundation
import SwiftData
import SwiftUI

/// Hub view for all scanning features: barcode, shopping list OCR, recipe OCR.
/// Shows as a tab in the main app, launches the appropriate scanner as a sheet.
struct ScannerTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<GroceryList> { $0.archivedAt == nil },
        sort: \GroceryList.createdAt,
        order: .reverse
    )
    private var activeLists: [GroceryList]

    @State private var showingBarcodeScanner = false
    @State private var showingListScanner = false
    @State private var showingRecipeScanner = false
    @State private var showingCameraPermissionAlert = false
    @State private var scanProcessor = ScanProcessor()
    @State private var showingScanReview = false
    @State private var selectedListID: PersistentIdentifier?

    private var selectedList: GroceryList? {
        if let id = selectedListID {
            return activeLists.first { $0.persistentModelID == id }
        }
        return activeLists.first
    }

    var body: some View {
        NavigationStack {
            List {
                // Processing / results banner
                if scanProcessor.isProcessing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(
                                scanProcessor.scanMode == .recipe
                                    ? "Scanning recipe..."
                                    : "Scanning your list..."
                            )
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                if case .failed(let message) = scanProcessor.state {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(message)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Dismiss") { scanProcessor.reset() }
                                .font(.caption)
                        }
                    }
                }

                Section {
                    scanButton(
                        title: "Scan Barcode",
                        subtitle: "Point at a product barcode to look it up",
                        icon: "barcode.viewfinder",
                        color: .blue
                    ) {
                        checkCameraAndPresent { showingBarcodeScanner = true }
                    }

                    scanButton(
                        title: "Scan Shopping List",
                        subtitle: "Photograph a handwritten or printed list",
                        icon: "doc.text.viewfinder",
                        color: .green
                    ) {
                        checkCameraAndPresent { showingListScanner = true }
                    }

                    scanButton(
                        title: "Scan Recipe",
                        subtitle: "Photograph a recipe to extract ingredients",
                        icon: "text.viewfinder",
                        color: .orange
                    ) {
                        checkCameraAndPresent { showingRecipeScanner = true }
                    }
                } header: {
                    Text("Scan")
                } footer: {
                    if selectedList == nil {
                        Text(
                            "Create a shopping list first to add scanned items."
                        )
                    }
                }

                if !activeLists.isEmpty {
                    Section("Add To") {
                        if activeLists.count == 1, let list = activeLists.first {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(list.name)
                                        .font(.headline)
                                    let total = list.items?.count ?? 0
                                    let checked = list.items?.filter(\.isChecked).count ?? 0
                                    Text("\(checked)/\(total) items checked")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "cart.fill")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Picker("List", selection: $selectedListID) {
                                ForEach(activeLists) { list in
                                    Text(list.name)
                                        .tag(Optional(list.persistentModelID))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView(groceryList: selectedList)
            }
            .sheet(isPresented: $showingListScanner) {
                OCRScannerView(
                    mode: .shoppingList,
                    groceryList: selectedList,
                    scanProcessor: scanProcessor
                )
            }
            .sheet(isPresented: $showingRecipeScanner) {
                OCRScannerView(
                    mode: .recipe,
                    groceryList: selectedList,
                    scanProcessor: scanProcessor
                )
            }
            .sheet(isPresented: $showingScanReview) {
                ScanReviewSheet(
                    processor: scanProcessor,
                    groceryList: selectedList
                )
            }
            .onChange(of: scanProcessor.hasResults) { _, hasResults in
                if hasResults {
                    showingScanReview = true
                }
            }
            .onAppear {
                if selectedListID == nil, let first = activeLists.first {
                    selectedListID = first.persistentModelID
                }
            }
            .alert("Camera Access Required", isPresented: $showingCameraPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please enable camera access in Settings to use scanning features.")
            }
        }
    }

    private func scanButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private func checkCameraAndPresent(_ action: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            action()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    Task { @MainActor in action() }
                }
            }
        default:
            showingCameraPermissionAlert = true
        }
    }
}

// MARK: - Scan Review Sheet

/// Presented automatically when background OCR finishes.
/// Shows parsed items with toggles; user confirms to add to grocery list or save as recipe.
struct ScanReviewSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var processor: ScanProcessor
    let groceryList: GroceryList?

    private var isRecipeMode: Bool { processor.scanMode == .recipe }

    private var ingredientItems: [ScanProcessor.ParsedItem] {
        processor.parsedItems.filter { $0.category != "Recipe" }
    }

    private var recipeTitle: String {
        processor.parsedItems.first { $0.name.hasPrefix("Recipe: ") }?
            .name.replacingOccurrences(of: "Recipe: ", with: "") ?? ""
    }

    private var hasInstructions: Bool {
        processor.parsedItems.contains { $0.name.hasPrefix("Instructions (") }
    }

    var body: some View {
        NavigationStack {
            VStack {
                let items = isRecipeMode ? ingredientItems : processor.parsedItems
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Items Found",
                        systemImage: "text.magnifyingglass",
                        description: Text("Could not parse any items from the photo.")
                    )
                } else {
                    if isRecipeMode && !recipeTitle.isEmpty {
                        Text(recipeTitle)
                            .font(.title3.bold())
                            .padding(.top)
                    }

                    List {
                        Section("Found \(items.filter(\.included).count) items") {
                            ForEach(items) { item in
                                HStack {
                                    Button {
                                        processor.toggleItem(id: item.id)
                                    } label: {
                                        Image(systemName: item.included ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(item.included ? Color.accentColor : .gray)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading) {
                                        TextField(
                                            "Item name",
                                            text: Binding(
                                                get: { item.name },
                                                set: { processor.updateItemName(id: item.id, name: $0) }
                                            )
                                        )
                                        if item.quantity > 0 && (item.quantity != 1 || !item.unit.isEmpty) {
                                            Text("\(formatQuantity(item.quantity)) \(item.unit)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if isRecipeMode {
                        Button("Save Recipe") {
                            saveRecipe(items.filter(\.included))
                            processor.reset()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(items.filter(\.included).isEmpty)
                        .padding()
                    } else {
                        Button("Add \(items.filter(\.included).count) Items") {
                            addGroceryItems(items.filter(\.included))
                            processor.reset()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(items.filter(\.included).isEmpty)
                        .padding()
                    }
                }
            }
            .navigationTitle(isRecipeMode ? "Scanned Recipe" : "Scanned Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        processor.reset()
                        dismiss()
                    }
                }
            }
        }
    }

    private func addGroceryItems(_ items: [ScanProcessor.ParsedItem]) {
        guard let list = groceryList else { return }
        for item in items {
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

    private func saveRecipe(_ items: [ScanProcessor.ParsedItem]) {
        let ingredients = items.enumerated().map { index, item in
            Ingredient(
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                category: item.category,
                displayOrder: index
            )
        }
        let recipe = Recipe(
            name: recipeTitle.isEmpty ? "Scanned Recipe" : recipeTitle,
            instructions: processor.parsedInstructions,
            ingredients: ingredients
        )
        modelContext.insert(recipe)
    }

    private func formatQuantity(_ qty: Double) -> String {
        if qty == Double(Int(qty)) { return "\(Int(qty))" }
        return String(format: "%.1f", qty)
    }
}
