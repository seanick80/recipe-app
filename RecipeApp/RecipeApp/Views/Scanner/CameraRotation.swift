import ImageIO
import UIKit

/// Small helper that maps the current interface orientation onto the two
/// values the camera stack needs:
///
///   * `videoRotationAngle` — what to write on an `AVCaptureConnection` so
///     the preview / captured photo is oriented to match what the user sees.
///   * `cgImageOrientation` — what to pass to `VNImageRequestHandler` for
///     back-camera pixel buffers (which are always delivered in sensor-native
///     orientation, independent of any connection rotation).
///
/// Both helpers must be called on the main thread because `UIWindowScene`
/// state is main-actor-isolated. For consumers that run on a background
/// queue (e.g. `AVCaptureVideoDataOutput` delegate callbacks), capture the
/// orientation on the main actor when it changes and read the cached value
/// from the background — see `CameraViewModel.currentBufferOrientation`.
enum CameraRotation {
    @MainActor
    static func videoRotationAngle() -> CGFloat {
        // Back-camera sensor is mounted landscape-right relative to the device,
        // so portrait display needs a 90° rotation. The other three follow.
        switch currentInterfaceOrientation() {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return 90
        }
    }

    @MainActor
    static func cgImageOrientation() -> CGImagePropertyOrientation {
        switch currentInterfaceOrientation() {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }

    @MainActor
    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
    }
}
