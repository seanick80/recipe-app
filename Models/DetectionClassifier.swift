import Foundation

/// Confidence-based triage for vision detection results. Pure Swift — no
/// Apple frameworks.
///
/// Items detected by YOLO, OCR, or barcode scanning are triaged into three
/// buckets based on confidence score:
///   - Auto-add (≥ 0.85): high confidence, add directly to inventory
///   - Confirm  (0.55–0.85): medium confidence, show user for review
///   - Reject   (< 0.55): low confidence, discard or offer cloud fallback

/// Confidence triage thresholds. Adjustable per-source.
struct DetectionThresholds: Codable, Equatable {
    var autoAdd: Double
    var confirm: Double

    init(autoAdd: Double = 0.85, confirm: Double = 0.55) {
        self.autoAdd = autoAdd
        self.confirm = confirm
    }

    static let `default` = DetectionThresholds()
    static let barcode = DetectionThresholds(autoAdd: 0.95, confirm: 0.80)
    static let ocr = DetectionThresholds(autoAdd: 0.80, confirm: 0.50)
    static let yolo = DetectionThresholds(autoAdd: 0.85, confirm: 0.55)
}

/// Triage result for a single detection.
enum DetectionTriage: String, Codable, Equatable {
    case autoAdd
    case confirm
    case reject
}

/// A single detection result from any vision source.
struct DetectionResult: Codable, Equatable {
    var label: String
    var confidence: Double
    var source: DetectionSource
    var boundingBox: BoundingBox?

    init(
        label: String,
        confidence: Double,
        source: DetectionSource,
        boundingBox: BoundingBox? = nil
    ) {
        self.label = label
        self.confidence = confidence
        self.source = source
        self.boundingBox = boundingBox
    }
}

enum DetectionSource: String, Codable, Equatable {
    case barcode
    case ocr
    case yolo
    case cloudLLM
}

/// Normalized bounding box (0..1 coordinates relative to image dimensions).
struct BoundingBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// Classifies a detection result into a triage bucket.
func classifyDetection(
    _ result: DetectionResult,
    thresholds: DetectionThresholds? = nil
) -> DetectionTriage {
    let t = thresholds ?? thresholdsForSource(result.source)
    if result.confidence >= t.autoAdd {
        return .autoAdd
    } else if result.confidence >= t.confirm {
        return .confirm
    } else {
        return .reject
    }
}

/// Returns default thresholds for a given detection source.
func thresholdsForSource(_ source: DetectionSource) -> DetectionThresholds {
    switch source {
    case .barcode: return .barcode
    case .ocr: return .ocr
    case .yolo: return .yolo
    case .cloudLLM: return .default
    }
}

/// Triages an array of detection results, returning them grouped by triage bucket.
/// Within each bucket, results are sorted by confidence (highest first).
func triageDetections(
    _ results: [DetectionResult],
    thresholds: DetectionThresholds? = nil
) -> (autoAdd: [DetectionResult], confirm: [DetectionResult], reject: [DetectionResult]) {
    var autoAdd: [DetectionResult] = []
    var confirm: [DetectionResult] = []
    var reject: [DetectionResult] = []

    for result in results {
        switch classifyDetection(result, thresholds: thresholds) {
        case .autoAdd: autoAdd.append(result)
        case .confirm: confirm.append(result)
        case .reject: reject.append(result)
        }
    }

    autoAdd.sort { $0.confidence > $1.confidence }
    confirm.sort { $0.confidence > $1.confidence }
    reject.sort { $0.confidence > $1.confidence }

    return (autoAdd, confirm, reject)
}

/// Deduplicates detections that likely refer to the same item.
/// Two detections are considered duplicates if they have the same label
/// (case-insensitive). The one with higher confidence wins.
func deduplicateDetections(_ results: [DetectionResult]) -> [DetectionResult] {
    var best: [String: DetectionResult] = [:]
    for result in results {
        let key = result.label.lowercased()
        if let existing = best[key] {
            if result.confidence > existing.confidence {
                best[key] = result
            }
        } else {
            best[key] = result
        }
    }
    return Array(best.values).sorted { $0.label.lowercased() < $1.label.lowercased() }
}
