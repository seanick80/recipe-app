import Foundation

// MARK: - Detection Classifier Tests

func testClassifyThresholds() {
    // Representative cases across sources and triage buckets
    let cases: [(DetectionSource, Double, DetectionTriage, String)] = [
        (.yolo, 0.95, .autoAdd, "YOLO autoAdd"),
        (.yolo, 0.70, .confirm, "YOLO confirm"),
        (.yolo, 0.30, .reject, "YOLO reject"),
        (.barcode, 0.96, .autoAdd, "barcode autoAdd"),
        (.barcode, 0.70, .reject, "barcode reject"),
        (.ocr, 0.82, .autoAdd, "OCR autoAdd"),
        (.ocr, 0.40, .reject, "OCR reject"),
    ]
    for (source, confidence, expected, desc) in cases {
        let result = DetectionResult(label: "item", confidence: confidence, source: source)
        checkEqual(classifyDetection(result), expected, desc)
    }
}

func testTriageAndDedup() {
    let results = [
        DetectionResult(label: "apple", confidence: 0.95, source: .yolo),
        DetectionResult(label: "milk", confidence: 0.70, source: .yolo),
        DetectionResult(label: "unknown", confidence: 0.30, source: .yolo),
    ]
    let (autoAdd, confirm, reject) = triageDetections(results)
    checkEqual(autoAdd.count, 1, "Triage: 1 autoAdd")
    checkEqual(confirm.count, 1, "Triage: 1 confirm")
    checkEqual(reject.count, 1, "Triage: 1 reject")

    // Dedup: higher confidence kept
    let dupes = [
        DetectionResult(label: "Apple", confidence: 0.80, source: .yolo),
        DetectionResult(label: "apple", confidence: 0.95, source: .yolo),
    ]
    let deduped = deduplicateDetections(dupes)
    checkEqual(deduped.count, 1, "Dedup: 1 unique")
    checkEqual(deduped[0].confidence, 0.95, "Dedup: higher conf kept")
}

func testDetectionCodable() {
    checkCodableRoundTrip(
        DetectionResult(
            label: "apple",
            confidence: 0.92,
            source: .yolo,
            boundingBox: BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        ),
        "DetectionResult Codable"
    )
}

// MARK: - Test Runner

func runDetectionTests() -> Bool {
    print("\n=== Detection Classifier Tests ===")

    testClassifyThresholds()
    testTriageAndDedup()
    testDetectionCodable()

    return printTestSummary("Detection Classifier Tests")
}
