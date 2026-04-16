import Foundation

// MARK: - Detection Classifier Tests

func testClassifyAutoAdd() {
    let result = DetectionResult(label: "apple", confidence: 0.95, source: .yolo)
    checkEqual(classifyDetection(result), .autoAdd, "0.95 YOLO → autoAdd")
}

func testClassifyConfirm() {
    let result = DetectionResult(label: "apple", confidence: 0.70, source: .yolo)
    checkEqual(classifyDetection(result), .confirm, "0.70 YOLO → confirm")
}

func testClassifyReject() {
    let result = DetectionResult(label: "apple", confidence: 0.30, source: .yolo)
    checkEqual(classifyDetection(result), .reject, "0.30 YOLO → reject")
}

func testClassifyBoundaryAutoAdd() {
    let result = DetectionResult(label: "milk", confidence: 0.85, source: .yolo)
    checkEqual(classifyDetection(result), .autoAdd, "0.85 YOLO = autoAdd boundary")
}

func testClassifyBoundaryConfirm() {
    let result = DetectionResult(label: "milk", confidence: 0.55, source: .yolo)
    checkEqual(classifyDetection(result), .confirm, "0.55 YOLO = confirm boundary")
}

func testClassifyBelowConfirm() {
    let result = DetectionResult(label: "milk", confidence: 0.54, source: .yolo)
    checkEqual(classifyDetection(result), .reject, "0.54 YOLO → reject")
}

func testBarcodeThresholds() {
    // Barcode has higher thresholds: autoAdd=0.95, confirm=0.80
    let high = DetectionResult(label: "item", confidence: 0.96, source: .barcode)
    checkEqual(classifyDetection(high), .autoAdd, "0.96 barcode → autoAdd")

    let mid = DetectionResult(label: "item", confidence: 0.88, source: .barcode)
    checkEqual(classifyDetection(mid), .confirm, "0.88 barcode → confirm")

    let low = DetectionResult(label: "item", confidence: 0.70, source: .barcode)
    checkEqual(classifyDetection(low), .reject, "0.70 barcode → reject")
}

func testOCRThresholds() {
    // OCR: autoAdd=0.80, confirm=0.50
    let high = DetectionResult(label: "item", confidence: 0.82, source: .ocr)
    checkEqual(classifyDetection(high), .autoAdd, "0.82 OCR → autoAdd")

    let mid = DetectionResult(label: "item", confidence: 0.60, source: .ocr)
    checkEqual(classifyDetection(mid), .confirm, "0.60 OCR → confirm")

    let low = DetectionResult(label: "item", confidence: 0.40, source: .ocr)
    checkEqual(classifyDetection(low), .reject, "0.40 OCR → reject")
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

func testDeduplicateDetections() {
    let results = [
        DetectionResult(label: "Apple", confidence: 0.80, source: .yolo),
        DetectionResult(label: "apple", confidence: 0.95, source: .yolo),
        DetectionResult(label: "Banana", confidence: 0.70, source: .yolo),
    ]
    let deduped = deduplicateDetections(results)
    checkEqual(deduped.count, 2, "Dedup: 2 unique items")
    // Find the apple entry
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

func testTriageEmpty() {
    let (autoAdd, confirm, reject) = triageDetections([])
    checkEqual(autoAdd.count, 0, "Empty triage: no autoAdd")
    checkEqual(confirm.count, 0, "Empty triage: no confirm")
    checkEqual(reject.count, 0, "Empty triage: no reject")
}

// MARK: - Test Runner

func runDetectionTests() -> Bool {
    print("\n=== Detection Classifier Tests ===")

    testClassifyAutoAdd()
    testClassifyConfirm()
    testClassifyReject()
    testClassifyBoundaryAutoAdd()
    testClassifyBoundaryConfirm()
    testClassifyBelowConfirm()
    testBarcodeThresholds()
    testOCRThresholds()
    testCustomThresholds()
    testTriageDetections()
    testDeduplicateDetections()
    testDetectionResultCodable()
    testDetectionThresholdsCodable()
    testTriageEmpty()

    return printTestSummary("Detection Classifier Tests")
}
