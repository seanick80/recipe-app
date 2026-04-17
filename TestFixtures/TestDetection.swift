import Foundation

// MARK: - Detection Classifier Tests

func testClassifyThresholds() {
    // Data-driven: (source, confidence, expected classification)
    let cases: [(DetectionSource, Double, DetectionTriage, String)] = [
        // YOLO thresholds
        (.yolo, 0.95, .autoAdd, "0.95 YOLO -> autoAdd"),
        (.yolo, 0.85, .autoAdd, "0.85 YOLO = autoAdd boundary"),
        (.yolo, 0.70, .confirm, "0.70 YOLO -> confirm"),
        (.yolo, 0.55, .confirm, "0.55 YOLO = confirm boundary"),
        (.yolo, 0.54, .reject, "0.54 YOLO -> reject"),
        (.yolo, 0.30, .reject, "0.30 YOLO -> reject"),
        // Barcode thresholds (higher: autoAdd=0.95, confirm=0.80)
        (.barcode, 0.96, .autoAdd, "0.96 barcode -> autoAdd"),
        (.barcode, 0.88, .confirm, "0.88 barcode -> confirm"),
        (.barcode, 0.70, .reject, "0.70 barcode -> reject"),
        // OCR thresholds (autoAdd=0.80, confirm=0.50)
        (.ocr, 0.82, .autoAdd, "0.82 OCR -> autoAdd"),
        (.ocr, 0.60, .confirm, "0.60 OCR -> confirm"),
        (.ocr, 0.40, .reject, "0.40 OCR -> reject"),
    ]
    for (source, confidence, expected, desc) in cases {
        let result = DetectionResult(label: "item", confidence: confidence, source: source)
        checkEqual(classifyDetection(result), expected, desc)
    }
}

func testCustomThresholds() {
    let custom = DetectionThresholds(autoAdd: 0.90, confirm: 0.60)
    let result = DetectionResult(label: "item", confidence: 0.85, source: .yolo)
    checkEqual(classifyDetection(result, thresholds: custom), .confirm, "Custom thresholds: 0.85 < 0.90")
}

func testTriageDetections() {
    let results = [
        DetectionResult(label: "apple", confidence: 0.95, source: .yolo),
        DetectionResult(label: "milk", confidence: 0.70, source: .yolo),
        DetectionResult(label: "unknown", confidence: 0.30, source: .yolo),
        DetectionResult(label: "banana", confidence: 0.90, source: .yolo),
        DetectionResult(label: "cheese", confidence: 0.60, source: .yolo),
    ]
    let (autoAdd, confirm, reject) = triageDetections(results)
    checkEqual(autoAdd.count, 2, "Triage: 2 autoAdd")
    checkEqual(confirm.count, 2, "Triage: 2 confirm")
    checkEqual(reject.count, 1, "Triage: 1 reject")
    checkEqual(autoAdd[0].label, "apple", "Triage: autoAdd sorted by confidence desc")
    checkEqual(autoAdd[1].label, "banana", "Triage: autoAdd second")
}

func testTriageEmpty() {
    let (autoAdd, confirm, reject) = triageDetections([])
    checkEqual(autoAdd.count + confirm.count + reject.count, 0, "Empty triage: all buckets empty")
}

func testDeduplicateDetections() {
    let results = [
        DetectionResult(label: "Apple", confidence: 0.80, source: .yolo),
        DetectionResult(label: "apple", confidence: 0.95, source: .yolo),
        DetectionResult(label: "Banana", confidence: 0.70, source: .yolo),
    ]
    let deduped = deduplicateDetections(results)
    checkEqual(deduped.count, 2, "Dedup: 2 unique items")
    let apple = deduped.first { $0.label.lowercased() == "apple" }
    check(apple != nil, "Dedup: apple exists")
    checkEqual(apple!.confidence, 0.95, "Dedup: higher confidence kept")
}

func testDetectionResultCodable() {
    let result = DetectionResult(
        label: "apple",
        confidence: 0.92,
        source: .yolo,
        boundingBox: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    )
    checkCodableRoundTrip(result, "DetectionResult Codable round-trip")
}

func testDetectionThresholdsCodable() {
    let thresholds = DetectionThresholds(autoAdd: 0.90, confirm: 0.60)
    checkCodableRoundTrip(thresholds, "DetectionThresholds Codable round-trip")
}

// MARK: - Test Runner

func runDetectionTests() -> Bool {
    print("\n=== Detection Classifier Tests ===")

    testClassifyThresholds()
    testCustomThresholds()
    testTriageDetections()
    testTriageEmpty()
    testDeduplicateDetections()
    testDetectionResultCodable()
    testDetectionThresholdsCodable()

    return printTestSummary("Detection Classifier Tests")
}
