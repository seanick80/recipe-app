import ImageIO
import UIKit
import XCTest

@testable import RecipeApp

final class CameraRotationTests: XCTestCase {
    // MARK: - videoRotationAngle(for:)

    func testVideoRotationAngle_portrait() {
        XCTAssertEqual(CameraRotation.videoRotationAngle(for: .portrait), 90)
    }

    func testVideoRotationAngle_portraitUpsideDown() {
        XCTAssertEqual(CameraRotation.videoRotationAngle(for: .portraitUpsideDown), 270)
    }

    func testVideoRotationAngle_landscapeLeft() {
        XCTAssertEqual(CameraRotation.videoRotationAngle(for: .landscapeLeft), 180)
    }

    func testVideoRotationAngle_landscapeRight() {
        XCTAssertEqual(CameraRotation.videoRotationAngle(for: .landscapeRight), 0)
    }

    func testVideoRotationAngle_unknownFallsBackToPortrait() {
        XCTAssertEqual(CameraRotation.videoRotationAngle(for: .unknown), 90)
    }

    func testVideoRotationAngle_coversAllStandardOrientations() {
        // Regression guard: if Apple adds a new UIInterfaceOrientation case
        // we want a build-time signal rather than a silent fallback for real
        // orientations. The switch in CameraRotation has `default` for
        // `.unknown`, so this test just verifies the four we care about all
        // land on unique, non-portrait-default values.
        let angles: Set<CGFloat> = [
            CameraRotation.videoRotationAngle(for: .portrait),
            CameraRotation.videoRotationAngle(for: .portraitUpsideDown),
            CameraRotation.videoRotationAngle(for: .landscapeLeft),
            CameraRotation.videoRotationAngle(for: .landscapeRight),
        ]
        XCTAssertEqual(angles.count, 4, "All four cardinal orientations must map to distinct angles")
    }

    // MARK: - cgImageOrientation(for:)

    func testCGImageOrientation_portrait() {
        XCTAssertEqual(CameraRotation.cgImageOrientation(for: .portrait), .right)
    }

    func testCGImageOrientation_portraitUpsideDown() {
        XCTAssertEqual(CameraRotation.cgImageOrientation(for: .portraitUpsideDown), .left)
    }

    func testCGImageOrientation_landscapeLeft() {
        XCTAssertEqual(CameraRotation.cgImageOrientation(for: .landscapeLeft), .down)
    }

    func testCGImageOrientation_landscapeRight() {
        XCTAssertEqual(CameraRotation.cgImageOrientation(for: .landscapeRight), .up)
    }

    func testCGImageOrientation_unknownFallsBackToPortrait() {
        XCTAssertEqual(CameraRotation.cgImageOrientation(for: .unknown), .right)
    }

    func testCGImageOrientation_coversAllStandardOrientations() {
        let orientations: Set<CGImagePropertyOrientation> = [
            CameraRotation.cgImageOrientation(for: .portrait),
            CameraRotation.cgImageOrientation(for: .portraitUpsideDown),
            CameraRotation.cgImageOrientation(for: .landscapeLeft),
            CameraRotation.cgImageOrientation(for: .landscapeRight),
        ]
        XCTAssertEqual(orientations.count, 4, "All four cardinal orientations must map to distinct CGImage orientations")
    }
}

final class CameraTiltTests: XCTestCase {
    private let quarter = Double.pi / 2

    // MARK: - distanceFromCardinal

    func testTilt_perfectPortrait_isZero() {
        XCTAssertEqual(CameraTilt.distanceFromCardinal(roll: 0), 0, accuracy: 1e-9)
    }

    func testTilt_perfectLandscapeLeft_isZero() {
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: quarter),
            0,
            accuracy: 1e-9,
            "roll = +π/2 is a cardinal (landscape)")
    }

    func testTilt_perfectLandscapeRight_isZero() {
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: -quarter),
            0,
            accuracy: 1e-9,
            "roll = -π/2 is a cardinal (landscape)")
    }

    func testTilt_perfectUpsideDown_isZero() {
        // Roll wraps to ±π at upside-down; both should register as a
        // cardinal (distance 0).
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: .pi), 0, accuracy: 1e-9)
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: -.pi), 0, accuracy: 1e-9)
    }

    func testTilt_halfwayBetweenPortraitAndLandscape_isQuarterTurnOverTwo() {
        // roll = π/4 (45°) is the worst case — equidistant from portrait and
        // landscape. Expected distance = π/4.
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: .pi / 4), .pi / 4, accuracy: 1e-9)
    }

    func testTilt_smallPositiveTilt_nearPortrait() {
        // 0.2 rad ≈ 11° — under the 0.3 rad threshold → still "level".
        XCTAssertEqual(CameraTilt.distanceFromCardinal(roll: 0.2), 0.2, accuracy: 1e-9)
    }

    func testTilt_smallPositiveTilt_nearLandscape() {
        // 0.2 rad past landscape-left cardinal; should also return 0.2.
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: quarter + 0.2), 0.2, accuracy: 1e-9)
    }

    func testTilt_smallNegativeTilt_nearLandscapeRight() {
        XCTAssertEqual(
            CameraTilt.distanceFromCardinal(roll: -quarter + 0.15),
            0.15,
            accuracy: 1e-9)
    }

    func testTilt_neverExceedsQuarterTurnOverTwo() {
        // Property: for any roll, the distance to the nearest cardinal is
        // bounded by π/4 (maximum possible distance between two adjacent
        // 90° marks is π/2, so the farthest point is halfway = π/4).
        let samples: [Double] = stride(from: -2 * .pi, through: 2 * .pi, by: 0.1).map { $0 }
        let maxSeen = samples.map(CameraTilt.distanceFromCardinal(roll:)).max() ?? 0
        XCTAssertLessThanOrEqual(maxSeen, .pi / 4 + 1e-9)
    }

    func testTilt_symmetricAroundZero() {
        // distance(roll) == distance(-roll) for any roll not exactly on a
        // half-turn boundary.
        for roll in stride(from: 0.0, through: 1.2, by: 0.1) {
            XCTAssertEqual(
                CameraTilt.distanceFromCardinal(roll: roll),
                CameraTilt.distanceFromCardinal(roll: -roll),
                accuracy: 1e-9,
                "Tilt distance should be symmetric around zero at roll = \(roll)")
        }
    }
}
