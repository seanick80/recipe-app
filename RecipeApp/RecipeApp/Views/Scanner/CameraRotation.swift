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
/// The mapping logic is split into pure static functions (`videoRotationAngle(for:)`
/// and `cgImageOrientation(for:)`) so each can be unit-tested against every
/// interface orientation without needing a live UIWindowScene. The
/// no-argument variants read the current interface orientation off the main
/// actor and delegate to the pure mappers.
///
/// Consumers on a background queue (e.g. `AVCaptureVideoDataOutput` delegate
/// callbacks) cannot touch `UIApplication`, so they read a cached value — see
/// `CameraViewModel.currentBufferOrientation`.
enum CameraRotation {
    // MARK: - Pure mappers (testable)

    /// Maps a `UIInterfaceOrientation` to the rotation angle (in degrees)
    /// that should be written on a back-camera `AVCaptureConnection`.
    ///
    /// The back-camera sensor is mounted landscape-right relative to the device,
    /// so portrait display needs a 90° rotation, and the other three follow.
    /// `.unknown` falls back to portrait.
    static func videoRotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        default: return 90
        }
    }

    /// Maps a `UIInterfaceOrientation` to the `CGImagePropertyOrientation`
    /// that should be passed to `VNImageRequestHandler` for back-camera
    /// pixel buffers. `.unknown` falls back to `.right` (portrait).
    static func cgImageOrientation(
        for orientation: UIInterfaceOrientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        case .landscapeRight: return .up
        default: return .right
        }
    }

    // MARK: - Main-actor convenience wrappers

    @MainActor
    static func videoRotationAngle() -> CGFloat {
        videoRotationAngle(for: currentInterfaceOrientation())
    }

    @MainActor
    static func cgImageOrientation() -> CGImagePropertyOrientation {
        cgImageOrientation(for: currentInterfaceOrientation())
    }

    @MainActor
    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .interfaceOrientation ?? .portrait
    }
}

/// Small helper for the "hold the phone level" coaching. Extracted from
/// `CameraViewModel` so the tilt-detection math can be unit-tested without
/// spinning up CoreMotion.
enum CameraTilt {
    /// Returns how far (in radians) the given CoreMotion roll is from the
    /// nearest 90° multiple. Result is in `[0, π/4]` — zero means perfectly
    /// aligned with one of the four cardinal orientations; π/4 is maximally
    /// crooked (halfway between two cardinals).
    ///
    /// This is the replacement for `abs(roll) > threshold`, which was portrait-
    /// biased and fired continuously whenever the phone was rotated to
    /// landscape even when the user was holding it perfectly still.
    static func distanceFromCardinal(roll: Double) -> Double {
        let quarterTurn = Double.pi / 2
        let modulo = abs(roll.truncatingRemainder(dividingBy: quarterTurn))
        return min(modulo, quarterTurn - modulo)
    }
}
