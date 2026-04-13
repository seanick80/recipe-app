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

                // Coaching overlay
                CameraCoachingOverlay(
                    tiltWarning: cameraVM.tiltWarning,
                    brightnessWarning: cameraVM.brightnessWarning,
                    onCapture: {}  // Barcode scanning is automatic, no manual capture
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
                cameraVM.configure()
                cameraVM.startSession()
                startBarcodeDetection()
            }
            .onDisappear {
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

    /// Starts continuous barcode detection on the video feed.
    private func startBarcodeDetection() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(
            BarcodeScanDelegate(viewModel: barcodeVM),
            queue: DispatchQueue(label: "barcode.scan")
        )
        if cameraVM.session.canAddOutput(videoOutput) {
            cameraVM.session.addOutput(videoOutput)
        }
    }
}

/// Delegate that runs barcode detection on each video frame.
class BarcodeScanDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let viewModel: BarcodeViewModel
    private lazy var request = viewModel.makeBarcodeRequest()

    init(viewModel: BarcodeViewModel) {
        self.viewModel = viewModel
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try? handler.perform([request])
    }
}
