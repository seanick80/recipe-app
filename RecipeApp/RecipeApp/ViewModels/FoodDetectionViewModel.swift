import CoreML
import Foundation
import SwiftUI
import UIKit
import Vision

/// Runs food classification via CoreML on a captured image. Mirrors
/// ScanProcessor's state-machine pattern: idle -> detecting -> ready/failed.
@Observable
class FoodDetectionViewModel {
    enum State: Equatable {
        case idle
        case detecting
        case ready(results: [DetectionResult])
        case failed(message: String)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle): return true
            case (.detecting, .detecting): return true
            case (.ready(let a), .ready(let b)): return a == b
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    var state: State = .idle

    var isDetecting: Bool {
        if case .detecting = state { return true }
        return false
    }

    var hasResults: Bool {
        if case .ready = state { return true }
        return false
    }

    var detectionResults: [DetectionResult] {
        if case .ready(let results) = state { return results }
        return []
    }

    // MARK: - CoreML Model

    private var mlModel: VNCoreMLModel?

    /// Attempts to load the FoodClassifier CoreML model. Returns false if the
    /// model bundle is not present (expected during development before the
    /// .mlpackage is added to the Xcode project).
    @discardableResult
    func loadModel() -> Bool {
        if mlModel != nil { return true }

        guard
            let modelURL = Bundle.main.url(
                forResource: "FoodClassifier",
                withExtension: "mlmodelc"
            )
        else {
            return false
        }

        guard let underlying = try? MLModel(contentsOf: modelURL),
            let vnModel = try? VNCoreMLModel(for: underlying)
        else {
            return false
        }

        mlModel = vnModel
        return true
    }

    // MARK: - Detection

    /// Kicks off food detection on the provided image. Updates state
    /// asynchronously on the main actor.
    func detect(image: UIImage) {
        state = .detecting

        if !loadModel() {
            state = .failed(
                message: "Food detection model not available. "
                    + "Ensure FoodClassifier.mlpackage is included in the app bundle."
            )
            return
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            let result = await Self.runDetection(image: image, model: self?.mlModel)
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let detections):
                    if detections.isEmpty {
                        self.state = .failed(
                            message: "No food items detected. Try a clearer photo."
                        )
                    } else {
                        self.state = .ready(results: detections)
                    }
                case .failure(let error):
                    self.state = .failed(message: error.localizedDescription)
                }
            }
        }
    }

    func reset() {
        state = .idle
    }

    // MARK: - Background Inference

    private static func runDetection(
        image: UIImage,
        model: VNCoreMLModel?
    ) async -> Result<[DetectionResult], Error> {
        guard let cgImage = image.cgImage else {
            return .failure(DetectionError.invalidImage)
        }

        guard let vnModel = model else {
            return .failure(DetectionError.modelNotLoaded)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .centerCrop

        do {
            try handler.perform([request])
        } catch {
            return .failure(error)
        }

        guard let observations = request.results as? [VNClassificationObservation] else {
            return .success([])
        }

        // Convert Vision classifications to DetectionResult.
        // Filter out very-low-confidence noise (below reject threshold).
        let detections =
            observations
            .filter { $0.confidence > 0.1 }
            .map { observation in
                DetectionResult(
                    label: observation.identifier,
                    confidence: Double(observation.confidence),
                    source: .yolo
                )
            }

        return .success(detections)
    }

    // MARK: - Errors

    enum DetectionError: LocalizedError {
        case invalidImage
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not read the captured image."
            case .modelNotLoaded:
                return "Food detection model not available."
            }
        }
    }
}
