import SwiftUI

/// Camera capture sheet for pantry scanning. Takes a photo of the fridge/pantry
/// and hands it off to FoodDetectionViewModel for CoreML inference.
/// Dismisses immediately after capture — detection runs in the background.
struct PantryCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraVM = CameraViewModel()

    var foodDetection: FoodDetectionViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreviewView(session: cameraVM.session)
                    .ignoresSafeArea()

                CameraCoachingOverlay(
                    tiltWarning: cameraVM.tiltWarning,
                    brightnessWarning: cameraVM.brightnessWarning,
                    onCapture: {
                        Task { await captureAndDetect() }
                    }
                )

                VStack {
                    Text("Photograph your fridge or pantry")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 100)
                    Spacer()
                }
            }
            .navigationTitle("Scan Pantry")
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

    private func captureAndDetect() async {
        guard let image = await cameraVM.capturePhoto() else {
            return
        }
        cameraVM.stopSession()
        foodDetection.detect(image: image)
        dismiss()
    }
}
