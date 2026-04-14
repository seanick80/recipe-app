import SwiftData
import SwiftUI

/// Tab for pantry inventory management. Users photograph their fridge/pantry
/// and the app detects food items via CoreML, then presents results for review.
struct PantryTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PantryItem.detectedAt, order: .reverse)
    private var pantryItems: [PantryItem]

    @State private var showingCamera = false
    @State private var showingCameraPermissionAlert = false
    @State private var showingDetectionReview = false
    @State private var foodDetection = FoodDetectionViewModel()
    @State private var pantryVM = PantryViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if pantryItems.isEmpty && !pantryVM.hasResults {
                    emptyState
                } else {
                    pantryList
                }
            }
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        checkCameraAndPresent { showingCamera = true }
                    } label: {
                        Label("Scan Pantry", systemImage: "camera.fill")
                    }
                }
            }
            .sheet(isPresented: $showingCamera) {
                PantryCaptureView(
                    foodDetection: foodDetection
                )
            }
            .sheet(isPresented: $showingDetectionReview) {
                DetectionReviewSheet(
                    pantryVM: pantryVM,
                    modelContext: modelContext
                )
            }
            .onChange(of: foodDetection.hasResults) { _, hasResults in
                if hasResults {
                    if case .ready(let results) = foodDetection.state {
                        pantryVM.processDetections(results)
                        foodDetection.reset()
                        showingDetectionReview = true
                    }
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
                Text("Please enable camera access in Settings to scan your pantry.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Pantry Items", systemImage: "refrigerator")
        } description: {
            Text("Take a photo of your fridge or pantry to automatically detect items.")
        } actions: {
            Button("Scan Pantry") {
                checkCameraAndPresent { showingCamera = true }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Pantry List

    private var pantryList: some View {
        List {
            if pantryVM.isProcessing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Detecting items...")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            ForEach(groupedItems, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        PantryItemRow(item: item)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(items[index])
                        }
                    }
                }
            }
        }
    }

    private var groupedItems: [(String, [PantryItem])] {
        let grouped = Dictionary(grouping: pantryItems) { $0.category }
        return grouped.keys.sorted().map { key in
            (key, grouped[key]!.sorted { $0.name < $1.name })
        }
    }

    // MARK: - Camera Permission

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

// MARK: - Pantry Item Row

struct PantryItemRow: View {
    let item: PantryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                HStack(spacing: 8) {
                    if item.quantity > 1 {
                        Text("×\(item.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.confidence > 0 {
                        Text("\(Int(item.confidence * 100))%")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(confidenceColor.opacity(0.15))
                            .foregroundStyle(confidenceColor)
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer()
            Image(systemName: categoryIcon)
                .foregroundStyle(.secondary)
        }
    }

    private var confidenceColor: Color {
        if item.confidence >= 0.85 { return .green }
        if item.confidence >= 0.55 { return .orange }
        return .red
    }

    private var categoryIcon: String {
        switch item.category {
        case "Produce": return "leaf"
        case "Dairy": return "cup.and.saucer"
        case "Meat": return "flame"
        case "Bakery": return "birthday.cake"
        case "Dry & Canned": return "shippingbox"
        case "Frozen": return "snowflake"
        case "Snacks": return "popcorn"
        case "Beverages": return "mug"
        case "Condiments": return "takeoutbag.and.cup.and.straw"
        default: return "basket"
        }
    }
}
