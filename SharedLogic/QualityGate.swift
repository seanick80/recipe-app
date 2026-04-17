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

// MARK: - Section Header Routing
//
// Recipe OCR produces lines in reading order. Rather than trust geometric
// block grouping (fragile on multi-column pages and dense web layouts),
// we walk the lines in order and use explicit section headers like
// "Ingredients", "Method", "Step 1" to route each subsequent line to the
// correct bucket. This is far more reliable than content-based block
// classification.

/// Semantic section of a recipe, identified from explicit headers in the OCR.
enum RecipeSection: String, Codable, Equatable {
    /// Title + narrative + nutrition widgets (before "Ingredients").
    case intro
    /// Between "Ingredients" and "Method".
    case ingredients
    /// After "Method" / "Step 1".
    case instructions
}

/// If the line is a standalone section header, returns the section it
/// introduces. Otherwise nil.
///
/// Matches whole-line headers only — phrases embedded in paragraphs don't
/// count, to avoid misreading body sentences that happen to contain the word
/// "ingredients".
func sectionFromHeader(_ line: String) -> RecipeSection? {
    let trimmed =
        line
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: ":.·•*"))
        .trimmingCharacters(in: .whitespaces)
        .lowercased()

    // Only short, header-like strings (< 30 chars keeps out paragraphs that
    // happen to mention "ingredients" in prose).
    guard trimmed.count >= 4, trimmed.count < 30 else { return nil }

    switch trimmed {
    case "ingredients", "ingredient list", "what you need", "what you'll need":
        return .ingredients
    case "method", "directions", "direction", "instructions", "instruction",
        "preparation", "procedure", "steps", "how to make", "how to make it":
        return .instructions
    default:
        // "Step 1", "Step 2", "step 3" — anywhere a step header appears,
        // we're in the instruction section.
        if trimmed.hasPrefix("step ") || trimmed.hasPrefix("step\t") {
            return .instructions
        }
        return nil
    }
}

/// True if the line is metadata noise with no real content — e.g. orphan
/// digits from nutrition widgets ("270•", "615°", "108."), bare unit tokens
/// ("160g."), or decorative symbols. These appear around recipe headers on
/// web pages and should be dropped before parsing.
func isLikelyMetadataJunk(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }

    // A line is junk if, after stripping digits / punctuation / common unit
    // suffixes, there's no alphabetic content left (or only a lone unit letter).
    let unitRegex = "(?i)\\b\\d+(\\.\\d+)?\\s*(g|kg|ml|l|oz|lb)\\b"
    let stripCharacters = CharacterSet(charactersIn: "0123456789.,°•·*:;×xX/\\-+()[] \t")
    let stripped =
        trimmed
        .replacingOccurrences(of: unitRegex, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
        .components(separatedBy: stripCharacters)
        .joined()

    // After stripping digits/units/punctuation, very short residue (<= 1
    // letter) means the line was essentially numeric.
    return stripped.count <= 1
}

// MARK: - Headerless Recipe Heuristics

/// True if the line looks like a numbered instruction step — e.g.
/// "1 Combine flours in large bowl" or "3 Serve fritters topped with..."
/// These start with a digit (1–9) immediately followed by a space and a
/// capital letter or verb, distinguishing them from ingredient lines like
/// "2 eggs" or "1 tablespoon olive oil".
func looksLikeNumberedInstruction(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 10 else { return false }

    // Must start with a single digit (1-9) followed by a space
    guard let first = trimmed.first, first.isNumber,
        trimmed.count > 2,
        trimmed[trimmed.index(after: trimmed.startIndex)] == " "
    else { return false }

    // The word after the number: if it's a cooking verb → instruction
    let afterNumber = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    let firstWord = afterNumber.prefix(while: { $0.isLetter }).lowercased()

    let cookingVerbs: Set<String> = [
        "heat", "combine", "cook", "add", "stir", "mix", "pour", "place",
        "bake", "serve", "preheat", "bring", "reduce", "cover", "remove",
        "transfer", "whisk", "fold", "season", "drain", "cut", "slice",
        "chop", "melt", "grease", "brush", "roll", "spread", "arrange",
        "return", "meanwhile", "fill", "sprinkle", "set", "let", "cool",
        "line", "soak", "blend", "process", "knead", "shape", "divide",
        "toss", "drizzle", "garnish", "top", "stand", "rest", "simmer",
        "boil", "fry", "roast", "grill", "broil", "sauté", "sear",
        "marinate", "refrigerate", "freeze", "thaw", "wrap", "discard",
        "squeeze", "strain", "rinse", "wash", "peel", "trim", "score",
        "thread", "skewer", "invert", "unmould", "unmold", "flip",
        "using", "in", "on", "working", "make", "prepare", "finish",
    ]

    return cookingVerbs.contains(firstWord)
}

/// True if the line starts with a quantity pattern typical of an ingredient
/// line — e.g. "½ cup", "2 tablespoons", "420g", "¼ cup (60ml)".
/// Used as a fallback when no section headers were found.
func looksLikeIngredientStart(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }

    // Must start with a digit, fraction character, or Unicode fraction
    let first = trimmed.unicodeScalars.first!
    let isASCIIScalar = first.value < 128
    let startsWithQuantity =
        isASCIIScalar
        ? (trimmed.first!.isNumber)
        : "½¼¾⅓⅔⅛⅜⅝⅞".unicodeScalars.contains(first)

    guard startsWithQuantity else { return false }

    // If it looks like a numbered instruction, it's not an ingredient
    if looksLikeNumberedInstruction(trimmed) { return false }

    // Short lines starting with a number are likely ingredients ("2 eggs")
    // Long lines (>100 chars) starting with a number are likely instructions
    if trimmed.count > 100 { return false }

    return true
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
