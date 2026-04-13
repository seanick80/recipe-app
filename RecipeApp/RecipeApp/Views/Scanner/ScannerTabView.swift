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

    private var activeList: GroceryList? { activeLists.first }

    var body: some View {
        NavigationStack {
            List {
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
                    if activeList == nil {
                        Text(
                            "Create a shopping list first to add scanned items."
                        )
                    }
                }

                if !activeLists.isEmpty {
                    Section("Active List") {
                        if let list = activeList {
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
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .sheet(isPresented: $showingBarcodeScanner) {
                BarcodeScannerView(groceryList: activeList)
            }
            .sheet(isPresented: $showingListScanner) {
                OCRScannerView(mode: .shoppingList, groceryList: activeList)
            }
            .sheet(isPresented: $showingRecipeScanner) {
                OCRScannerView(mode: .recipe, groceryList: activeList)
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
