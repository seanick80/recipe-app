import Foundation

// MARK: - Debug Log Tests

private func makeTempLog(maxBytes: Int = 1_000_000) -> (DebugLog, URL) {
    let tempDir = FileManager.default.temporaryDirectory
    let unique = "debuglog-test-\(UUID().uuidString).jsonl"
    let url = tempDir.appendingPathComponent(unique)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: url.appendingPathExtension("1"))
    return (DebugLog(fileURL: url, maxBytes: maxBytes), url)
}

private func cleanupLog(at url: URL) {
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: url.appendingPathExtension("1"))
}

func testDebugLogWriteAndRead() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    log.log(category: "ocr.vision", message: "first scan", details: ["lines": "4"])
    log.log(category: "b", message: "two")
    log.log(category: "c", message: "three")

    let content = log.readActive()
    check(content.contains("\"cat\":\"ocr.vision\""), "Contains category")
    check(content.contains("\"lines\":\"4\""), "Contains details")

    let lines = content.split(separator: "\n")
    checkEqual(lines.count, 3, "Three JSONL lines")
}

func testDebugLogRotation() {
    let (log, url) = makeTempLog(maxBytes: 200)
    defer { cleanupLog(at: url) }

    for i in 0..<20 {
        log.log(category: "spam", message: "entry \(i) with padding padding padding")
    }

    let archiveURL = url.appendingPathExtension("1")
    check(FileManager.default.fileExists(atPath: archiveURL.path), "Archive created after rotation")
}

func testDebugLogClearAndTail() {
    let (log, url) = makeTempLog(maxBytes: 100)
    defer { cleanupLog(at: url) }

    for i in 0..<15 {
        log.log(category: "x", message: "message number \(i) goes here")
    }
    log.clear()
    checkEqual(log.readActive(), "", "Empty after clear")

    // Tail
    let (log2, url2) = makeTempLog()
    defer { cleanupLog(at: url2) }
    for i in 0..<10 {
        log2.log(category: "n", message: "line \(i)")
    }
    let last3 = log2.tail(lines: 3)
    checkEqual(last3.count, 3, "tail(3) returns 3")
    check(last3[2].contains("\"msg\":\"line 9\""), "Last of tail is line 9")
}

func testDebugLogEncode() {
    let line = DebugLog.encode(
        timestamp: Date(timeIntervalSince1970: 0),
        category: "ocr.blocks",
        message: "block 1",
        details: ["label": "ingredients"]
    )
    check(line.contains("\"cat\":\"ocr.blocks\""), "Encoded category")
    check(line.contains("\"label\":\"ingredients\""), "Encoded detail")

    let noDetails = DebugLog.encode(timestamp: Date(), category: "x", message: "no details", details: [:])
    check(!noDetails.contains("\"details\""), "Empty details omitted")
}

// MARK: - Test Runner

func runDebugLogTests() -> Bool {
    print("\n=== Debug Log Tests ===")

    testDebugLogWriteAndRead()
    testDebugLogRotation()
    testDebugLogClearAndTail()
    testDebugLogEncode()

    return printTestSummary("Debug Log Tests")
}
