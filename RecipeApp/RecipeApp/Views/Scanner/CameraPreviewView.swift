import AVFoundation
import SwiftUI
import UIKit

/// UIViewRepresentable that displays the live camera feed from an AVCaptureSession.
///
/// Observes `UIDevice.orientationDidChangeNotification` and keeps the preview
/// connection's `videoRotationAngle` in sync with the interface orientation so
/// the feed rotates with the device instead of locking to portrait.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        context.coordinator.applyCurrentRotation(to: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private var observer: NSObjectProtocol?
        private weak var view: PreviewUIView?

        func attach(to view: PreviewUIView) {
            self.view = view
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            applyCurrentRotation(to: view)
            // NotificationCenter's closure is nonisolated `@Sendable`, but the
            // observer is registered on `.main`, so the body runs on the main
            // thread. `MainActor.assumeIsolated` is the correct escape hatch
            // for calling back into our main-actor Coordinator from that
            // closure without spawning a Task hop.
            observer = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let view = self.view else { return }
                    self.applyCurrentRotation(to: view)
                }
            }
        }

        func detach() {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
            observer = nil
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            view = nil
        }

        func applyCurrentRotation(to view: PreviewUIView) {
            guard let connection = view.previewLayer.connection else { return }
            let angle = CameraRotation.videoRotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
