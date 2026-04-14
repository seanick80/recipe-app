import SwiftUI

/// Captures a photo and hands off to ScanProcessor for background OCR.
/// Dismisses immediately after capture — user returns to the app while
/// processing runs in the background.
struct OCRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraVM = CameraViewModel()

    let mode: OCRScanMode
    let groceryList: GroceryList?

    /// Shared processor for async background OCR. Passed in from ScannerTabView
    /// so it survives this sheet's dismissal.
    var scanProcessor: ScanProcessor?

    enum OCRScanMode {
        case shoppingList
        case recipe
    }

    var body: some View {
        NavigationStack {
            cameraPhaseView
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

    // MARK: - Capture

    private func captureAndProcess() async {
        guard let image = await cameraVM.capturePhoto() else {
            return
        }

        cameraVM.stopSession()

        // Hand off to background processor and dismiss immediately
        switch mode {
        case .shoppingList:
            scanProcessor?.processShoppingList(image: image)
        case .recipe:
            scanProcessor?.processRecipe(image: image)
        }
        dismiss()
    }
}
