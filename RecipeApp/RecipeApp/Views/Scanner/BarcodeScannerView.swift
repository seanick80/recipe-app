import AVFoundation
import SwiftData
import SwiftUI
import Vision

/// Live barcode scanner: points camera at a product barcode, looks it up
/// in Open Food Facts, and offers to add the product to the active shopping list.
struct BarcodeScannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var cameraVM = CameraViewModel()
    @State private var barcodeVM = BarcodeViewModel()
    let groceryList: GroceryList?

    var body: some View {
        NavigationStack {
            ZStack {
                // Camera feed
                CameraPreviewView(session: cameraVM.session)
                    .ignoresSafeArea()

                // Coaching overlay (hit testing disabled — barcode scanning is automatic)
                CameraCoachingOverlay(
                    tiltWarning: cameraVM.tiltWarning,
                    brightnessWarning: cameraVM.brightnessWarning,
                    onCapture: {}
                )
                .allowsHitTesting(false)

                // Scan guide frame
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.6), lineWidth: 2)
                    .frame(width: 280, height: 160)

                // Result card at bottom
                VStack {
                    Spacer()
                    resultCard
                        .padding()
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                configureBarcodeDetection()
                cameraVM.configure()
                cameraVM.startSession()
            }
            .onDisappear {
                cameraVM.onVideoFrame = nil
                cameraVM.stopSession()
            }
        }
    }

    @ViewBuilder
    private var resultCard: some View {
        VStack(spacing: 12) {
            if barcodeVM.isLookingUp {
                HStack {
                    ProgressView()
                    Text("Looking up product...")
                        .foregroundStyle(.secondary)
                }
            } else if let product = barcodeVM.product {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.headline)
                    if !product.brand.isEmpty {
                        Text(product.brand)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(product.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .clipShape(Capsule())
                        if !product.quantity.isEmpty {
                            Text(product.quantity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if groceryList != nil {
                    Button("Add to Shopping List") {
                        addProductToList(product)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Scan Another") {
                    barcodeVM.reset()
                }
                .buttonStyle(.bordered)
            } else if let error = barcodeVM.errorMessage {
                Text(error)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    barcodeVM.reset()
                }
                .buttonStyle(.bordered)
            } else {
                Text("Point camera at a product barcode")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func addProductToList(_ product: BarcodeViewModel.ScannedProduct) {
        guard let list = groceryList else { return }
        let item = GroceryItem(
            name: product.brand.isEmpty
                ? product.name
                : "\(product.brand) \(product.name)",
            quantity: 1,
            unit: "",
            category: product.category
        )
        item.groceryList = list
        modelContext.insert(item)
        barcodeVM.reset()
    }

    /// Hooks barcode detection into the camera's existing video output
    /// via the frame observer callback — no second AVCaptureVideoDataOutput needed.
    ///
    /// The pixel buffer from `AVCaptureVideoDataOutput` is always in sensor-native
    /// orientation regardless of how the preview connection is rotated, so we
    /// have to tell Vision which way "up" is for the current device orientation.
    /// Without this the detector would miss barcodes as soon as the user rotated
    /// the phone out of portrait.
    private func configureBarcodeDetection() {
        let request = barcodeVM.makeBarcodeRequest()
        cameraVM.onVideoFrame = { [weak cameraVM] sampleBuffer in
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let orientation = cameraVM?.currentBufferOrientation ?? .right
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
            } catch {
                DebugLog.shared.log(
                    category: "barcode.error",
                    message: "Vision perform failed",
                    details: ["error": "\(error)"]
                )
            }
        }
    }
}
