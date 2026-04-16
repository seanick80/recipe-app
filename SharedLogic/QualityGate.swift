import Foundation

/// Image quality assessment and handwriting detection for OCR scans.
/// Pure Swift — no Apple frameworks.
///
/// On iOS, VNRecognizedTextObservation provides per-line confidence and
/// bounding boxes. This module works with simplified versions of those
/// so it can be tested on Windows without Vision framework.

/// A single line of OCR output with position and confidence metadata.
struct OCRLine: Codable, Equatable {
    var text: String
    var confidence: Double  // 0.0–1.0
    var boundingBox: NormalizedBox  // normalized 0..1 coordinates

    init(text: String, confidence: Double, boundingBox: NormalizedBox = .zero) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Normalized bounding box (0..1 coordinates, origin at bottom-left to match Vision).
struct NormalizedBox: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let zero = NormalizedBox(x: 0, y: 0, width: 0, height: 0)

    /// Center x coordinate.
    var midX: Double { x + width / 2 }
    /// Center y coordinate.
    var midY: Double { y + height / 2 }
    /// Right edge.
    var maxX: Double { x + width }
    /// Top edge.
    var maxY: Double { y + height }
}

/// Result of assessing overall image quality for OCR.
struct ImageQualityAssessment: Codable, Equatable {
    var medianConfidence: Double
    var lowConfidenceRatio: Double  // fraction of lines below 0.5
    var isAcceptable: Bool
    var reason: String

    var shouldRetake: Bool { !isAcceptable }
}

// MARK: - Quality Assessment

/// Minimum median confidence to accept an image.
private let minMedianConfidence = 0.35

/// Maximum ratio of low-confidence lines before rejecting.
private let maxLowConfidenceRatio = 0.6

/// Confidence threshold below which a line is "low confidence".
private let lowConfidenceThreshold = 0.5

/// Assesses overall image quality from OCR line results.
///
/// Checks:
///   - Median OCR confidence (below 0.35 = blurry/bad lighting)
///   - Ratio of low-confidence lines (>60% = widespread problems)
///
/// - Parameter lines: OCR results with per-line confidence scores.
/// - Returns: Quality assessment with accept/reject decision.
func assessImageQuality(lines: [OCRLine]) -> ImageQualityAssessment {
    guard !lines.isEmpty else {
        return ImageQualityAssessment(
            medianConfidence: 0.0,
            lowConfidenceRatio: 1.0,
            isAcceptable: false,
            reason: "No text detected — page may be blank or image too dark"
        )
    }

    let confidences = lines.map(\.confidence).sorted()
    let medianConf = median(confidences)
    let lowCount = confidences.filter { $0 < lowConfidenceThreshold }.count
    let lowRatio = Double(lowCount) / Double(confidences.count)

    var reasons: [String] = []

    if medianConf < minMedianConfidence {
        let pct = Int(medianConf * 100)
        reasons.append("Very low OCR confidence (\(pct)%) — image may be blurry or poorly lit")
    }

    if lowRatio > maxLowConfidenceRatio {
        let pct = Int(lowRatio * 100)
        reasons.append("\(pct)% of text lines have low confidence — widespread readability issues")
    }

    return ImageQualityAssessment(
        medianConfidence: medianConf,
        lowConfidenceRatio: lowRatio,
        isAcceptable: reasons.isEmpty,
        reason: reasons.joined(separator: "; ")
    )
}

// MARK: - Handwriting Detection

/// Minimum absolute confidence for printed text.
private let handwritingConfidenceThreshold = 0.35

/// Page edge margin (5% from each edge).
private let edgeMarginRatio = 0.05

/// Detects whether an OCR line is likely handwritten based on multiple signals.
///
/// Requires 3+ signals to flag, preventing false positives on normal
/// printed text that happens to have low OCR confidence:
///   - Very low absolute confidence (< 0.35)
///   - Confidence well below page median (< 60% of median)
///   - Position in page margins (outer 5%)
///   - Line height very different from median (>80% bigger or <50% smaller)
///
/// - Parameters:
///   - line: The OCR line to check.
///   - medianConfidence: Median confidence across all lines on the page.
///   - medianHeight: Median line height (boundingBox.height) across the page.
/// - Returns: True if the line is likely handwritten.
func isLikelyHandwritten(
    line: OCRLine,
    medianConfidence: Double,
    medianHeight: Double
) -> Bool {
    var signals = 0

    // Very low absolute confidence.
    if line.confidence < handwritingConfidenceThreshold {
        signals += 1
    }

    // Confidence well below page median.
    if medianConfidence > 0 && line.confidence < medianConfidence * 0.6 {
        signals += 1
    }

    // In page margins (left or right edge).
    let box = line.boundingBox
    if box.x < edgeMarginRatio || box.maxX > (1.0 - edgeMarginRatio) {
        signals += 1
    }

    // Line height very different from median.
    if medianHeight > 0 && box.height > 0 {
        let ratio = box.height / medianHeight
        if ratio > 1.8 || ratio < 0.5 {
            signals += 1
        }
    }

    return signals >= 3
}

/// Splits OCR lines into printed and handwritten groups.
///
/// - Parameter lines: All OCR lines from one page.
/// - Returns: Tuple of (printed lines, handwritten lines).
func separateHandwritten(
    lines: [OCRLine]
) -> (printed: [OCRLine], handwritten: [OCRLine]) {
    guard !lines.isEmpty else { return ([], []) }

    let confidences = lines.map(\.confidence).sorted()
    let medConf = median(confidences)
    let heights = lines.map(\.boundingBox.height).sorted()
    let medHeight = median(heights)

    var printed: [OCRLine] = []
    var handwritten: [OCRLine] = []

    for line in lines {
        if isLikelyHandwritten(
            line: line,
            medianConfidence: medConf,
            medianHeight: medHeight
        ) {
            handwritten.append(line)
        } else {
            printed.append(line)
        }
    }

    return (printed, handwritten)
}

// MARK: - Block Grouping

/// Groups OCR lines into vertically-adjacent blocks.
///
/// A new block starts when the vertical gap between a line and its predecessor
/// exceeds `gapFactor * medianHeight`. Used after `separateHandwritten` to
/// feed multi-line text into `classifyZone` (which expects coherent blocks,
/// not individual lines).
///
/// - Parameters:
///   - lines: OCR lines from one page (any order).
///   - gapFactor: Multiple of median line height that triggers a block break.
/// - Returns: Lines grouped into blocks, sorted top-to-bottom.
func groupLinesIntoBlocks(
    _ lines: [OCRLine],
    gapFactor: Double = 1.5
) -> [[OCRLine]] {
    guard !lines.isEmpty else { return [] }
    let sorted = lines.sorted { $0.boundingBox.y < $1.boundingBox.y }
    let heights = sorted.map(\.boundingBox.height).sorted()
    let medianHeight = median(heights)
    let gapThreshold = max(medianHeight * gapFactor, 0.005)

    var blocks: [[OCRLine]] = [[sorted[0]]]
    for line in sorted.dropFirst() {
        guard let previous = blocks[blocks.count - 1].last else { continue }
        let prevBottom = previous.boundingBox.maxY
        let gap = line.boundingBox.y - prevBottom
        if gap > gapThreshold {
            blocks.append([line])
        } else {
            blocks[blocks.count - 1].append(line)
        }
    }
    return blocks
}

// MARK: - Helpers

/// Median of a sorted array.
private func median(_ sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let mid = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
    return sorted[mid]
}
