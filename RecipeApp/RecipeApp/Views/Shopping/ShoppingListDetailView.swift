import AVFoundation
import SwiftData
import SwiftUI

/// Displays the active shopping list grouped by store-aisle category order.
/// Checked items sink to the bottom of their category.
struct ShoppingListDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var groceryList: GroceryList
    var viewModel: ShoppingViewModel
    @State private var showingAddItem = false
    @State private var showingListScanner = false
    @State private var showingScanReview = false
    @State private var scanProcessor = ScanProcessor()
    @State private var showingCameraPermissionAlert = false
    @State private var showingClearAllConfirmation = false
    @State private var editingItem: GroceryItem?

    var body: some View {
        List {
            ForEach(viewModel.categorizedItems(from: groceryList), id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        GroceryItemRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingItem = item
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(items[index])
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    checkCameraAndPresent { showingListScanner = true }
                } label: {
                    Label("Scan", systemImage: "doc.text.viewfinder")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingAddItem = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    removeCheckedItems()
                } label: {
                    Label("Remove Checked", systemImage: "trash")
                }
                .disabled((groceryList.items ?? []).filter(\.isChecked).isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    for item in groceryList.items ?? [] {
                        item.isChecked = false
                    }
                } label: {
                    Label("Uncheck All", systemImage: "arrow.uturn.backward")
                }
                .disabled((groceryList.items ?? []).filter(\.isChecked).isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    showingClearAllConfirmation = true
                } label: {
                    Label("Clear All", systemImage: "xmark.bin")
                }
                .disabled((groceryList.items ?? []).isEmpty)
            }
        }
        .confirmationDialog("Clear All Items?", isPresented: $showingClearAllConfirmation, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                clearAllItems()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all items from the list.")
        }
        .sheet(isPresented: $showingAddItem) {
            AddGroceryItemView(groceryList: groceryList)
        }
        .sheet(isPresented: $showingListScanner) {
            OCRScannerView(
                mode: .shoppingList,
                groceryList: groceryList,
                scanProcessor: scanProcessor
            )
        }
        .sheet(isPresented: $showingScanReview) {
            ScanReviewSheet(
                processor: scanProcessor
            )
        }
        .onChange(of: scanProcessor.hasResults) { _, hasResults in
            if hasResults {
                showingScanReview = true
            }
        }
        .sheet(item: $editingItem) { item in
            EditGroceryItemView(item: item)
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
        .overlay {
            if (groceryList.items ?? []).isEmpty {
                ContentUnavailableView(
                    "No Items",
                    systemImage: "cart",
                    description: Text("Tap + to add items or scan a list.")
                )
            }
        }
    }

    private func removeCheckedItems() {
        let checked = (groceryList.items ?? []).filter(\.isChecked)
        for item in checked {
            modelContext.delete(item)
        }
    }

    private func clearAllItems() {
        for item in groceryList.items ?? [] {
            modelContext.delete(item)
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
