import Foundation
import UIKit
import Vision

/// Runs on-device OCR on captured images using Apple's VNRecognizeTextRequest.
/// Returns structured text with per-line confidence scores.
@Observable
class OCRViewModel {
    var recognizedLines: [RecognizedLine] = []
    var isProcessing = false
    var errorMessage: String?

    /// A single line of recognized text with its confidence score.
    struct RecognizedLine: Identifiable {
        let id = UUID()
        let text: String
        let confidence: Float
        let boundingBox: CGRect
    }

    /// Runs OCR on a UIImage and populates recognizedLines.
    @MainActor
    func recognizeText(from image: UIImage) async {
        guard let cgImage = image.cgImage else {
            errorMessage = "Invalid image"
            return
        }

        isProcessing = true
        errorMessage = nil
        recognizedLines = []

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        do {
            try handler.perform([request])

            guard let observations = request.results else {
                errorMessage = "No text found"
                isProcessing = false
                return
            }

            var lines: [RecognizedLine] = []
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let line = RecognizedLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
                lines.append(line)
            }

            recognizedLines = lines
        } catch {
            errorMessage = "OCR failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }

    /// Returns all recognized text as a single multi-line string
    /// (suitable for feeding into the pure Swift parsers).
    var fullText: String {
        recognizedLines.map(\.text).joined(separator: "\n")
    }

    /// Returns lines above a confidence threshold.
    func highConfidenceLines(threshold: Float = 0.5) -> [RecognizedLine] {
        recognizedLines.filter { $0.confidence >= threshold }
    }

    func reset() {
        recognizedLines = []
        isProcessing = false
        errorMessage = nil
    }
}
