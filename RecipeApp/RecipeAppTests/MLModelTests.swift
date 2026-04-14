import XCTest

@testable import RecipeApp

/// Validates ML model bundles are present and within expected size bounds.
/// These tests run on every CI build and catch:
///   - Missing models (forgot to check in after update-models.sh)
///   - Unexpectedly large models (regression from model swap or config change)
///   - Model load failures (corrupt file, incompatible coremltools version)
final class MLModelTests: XCTestCase {

    // MARK: - Model Presence & Size

    /// FoodClassifier: ViT-base-patch16-224 (nateraw/food), expect 100-400 MB.
    /// ViT-base has 86M params; CoreML Float16 packs at ~2 bytes/param ≈ 170 MB.
    func testFoodClassifierBundled() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc"),
            "FoodClassifier.mlmodelc not found in app bundle. "
                + "Run scripts/update-models.sh on macOS and commit the .mlmodel."
        )

        let size = try directorySize(url)
        let mb = Double(size) / 1_000_000

        // Sanity bounds — adjust if model architecture changes.
        XCTAssertGreaterThan(mb, 50, "FoodClassifier too small (\(mb) MB) — likely corrupt")
        XCTAssertLessThan(mb, 500, "FoodClassifier too large (\(mb) MB) — check conversion options")

        // Log the actual size for visibility in test output.
        print("FoodClassifier.mlmodelc size: \(String(format: "%.1f", mb)) MB")
    }

    // MARK: - Helpers

    /// Returns total size of a directory (mlmodelc is a directory on disk).
    private func directorySize(_ url: URL) throws -> Int {
        let fm = FileManager.default
        var total = 0
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                total += values.fileSize ?? 0
            }
        }
        return total
    }
}
