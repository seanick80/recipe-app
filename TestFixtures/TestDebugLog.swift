import Foundation

// MARK: - Debug Log Tests

/// Creates a DebugLog at a unique temp path. Caller is responsible for cleaning up.
private func makeTempLog(maxBytes: Int = 1_000_000) -> (DebugLog, URL) {
    let tempDir = FileManager.default.temporaryDirectory
    let unique = "debuglog-test-\(UUID().uuidString).jsonl"
    let url = tempDir.appendingPathComponent(unique)
    // Ensure no leftover from a previous failed test run.
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: url.appendingPathExtension("1"))
    return (DebugLog(fileURL: url, maxBytes: maxBytes), url)
}

private func cleanupLog(at url: URL) {
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: url.appendingPathExtension("1"))
}

func testDebugLogWritesJSONL() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    log.log(category: "ocr.vision", message: "first scan", details: ["lines": "4"])

    let content = log.readActive()
    check(content.contains("\"cat\":\"ocr.vision\""), "Log contains category")
    check(content.contains("\"msg\":\"first scan\""), "Log contains message")
    check(content.contains("\"lines\":\"4\""), "Log contains details")
    check(content.hasSuffix("\n"), "Log ends with newline (JSONL format)")
}

func testDebugLogMultipleEntries() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    log.log(category: "a", message: "one")
    log.log(category: "b", message: "two")
    log.log(category: "c", message: "three")

    let lines = log.readActive().split(separator: "\n")
    checkEqual(lines.count, 3, "Three log entries produce three JSONL lines")
    check(String(lines[0]).contains("\"msg\":\"one\""), "First line is 'one'")
    check(String(lines[2]).contains("\"msg\":\"three\""), "Third line is 'three'")
}

func testDebugLogRotationAtSizeCap() {
    // Tiny cap forces rotation after a handful of writes.
    let (log, url) = makeTempLog(maxBytes: 200)
    defer { cleanupLog(at: url) }

    for i in 0..<20 {
        log.log(category: "spam", message: "entry \(i) with padding padding padding")
    }

    // After 20 writes at ~100+ bytes each into a 200-byte cap, an archive
    // should exist and the active file should be smaller than the archive
    // (or at least bounded).
    let archiveURL = url.appendingPathExtension("1")
    check(FileManager.default.fileExists(atPath: archiveURL.path), "Archive file created after rotation")
    check(log.activeByteCount <= 200 + 200, "Active file bounded to roughly cap + last entry")
}

func testDebugLogClearRemovesFiles() {
    let (log, url) = makeTempLog(maxBytes: 100)
    defer { cleanupLog(at: url) }

    for i in 0..<15 {
        log.log(category: "x", message: "message number \(i) goes here")
    }
    let archiveURL = url.appendingPathExtension("1")
    check(FileManager.default.fileExists(atPath: archiveURL.path), "Archive exists before clear")

    log.clear()
    check(!FileManager.default.fileExists(atPath: url.path), "Active file gone after clear")
    check(!FileManager.default.fileExists(atPath: archiveURL.path), "Archive gone after clear")
    checkEqual(log.readActive(), "", "readActive returns empty after clear")
}

func testDebugLogTail() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    for i in 0..<10 {
        log.log(category: "n", message: "line \(i)")
    }

    let last3 = log.tail(lines: 3)
    checkEqual(last3.count, 3, "tail(3) returns 3 lines")
    check(last3[0].contains("\"msg\":\"line 7\""), "First of tail is line 7")
    check(last3[2].contains("\"msg\":\"line 9\""), "Last of tail is line 9")
}

func testDebugLogTailMoreThanAvailable() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    log.log(category: "n", message: "only one")

    let tail = log.tail(lines: 10)
    checkEqual(tail.count, 1, "tail(10) returns 1 when only 1 line exists")
}

func testDebugLogExportIncludesArchive() {
    // Cap sized to trigger exactly one rotation across the run, so the
    // archive keeps early entries while later entries sit in the active file.
    let (log, url) = makeTempLog(maxBytes: 600)
    defer { cleanupLog(at: url) }

    for i in 0..<10 {
        log.log(category: "r", message: "entry \(i) padding padding padding")
    }

    // Sanity: rotation occurred (archive exists).
    let archiveURL = url.appendingPathExtension("1")
    check(FileManager.default.fileExists(atPath: archiveURL.path), "Archive created")

    guard let exportURL = log.export() else {
        check(false, "export() returned nil after writing entries")
        return
    }
    defer { try? FileManager.default.removeItem(at: exportURL) }

    let exported = (try? String(contentsOf: exportURL, encoding: .utf8)) ?? ""
    let activeContent = log.readActive()
    let archiveContent = (try? String(contentsOf: archiveURL, encoding: .utf8)) ?? ""
    let expectedLines =
        activeContent.split(separator: "\n").count
        + archiveContent.split(separator: "\n").count
    let actualLines = exported.split(separator: "\n").count
    checkEqual(actualLines, expectedLines, "Export contains archive + active combined")
}

func testDebugLogExportEmptyReturnsNil() {
    let (log, url) = makeTempLog()
    defer { cleanupLog(at: url) }

    let result = log.export()
    check(result == nil, "export() returns nil when no events have been logged")
}

func testDebugLogEncodeDetails() {
    let now = Date(timeIntervalSince1970: 0)
    let line = DebugLog.encode(
        timestamp: now,
        category: "ocr.blocks",
        message: "block 1",
        details: ["label": "ingredients", "conf": "0.85"]
    )
    check(line.contains("\"cat\":\"ocr.blocks\""), "Encoded category")
    check(line.contains("\"msg\":\"block 1\""), "Encoded message")
    check(line.contains("\"ts\":\"1970-"), "Encoded timestamp")
    check(line.contains("\"label\":\"ingredients\""), "Encoded detail key label")
    check(line.contains("\"conf\":\"0.85\""), "Encoded detail key conf")
}

func testDebugLogEncodeNoDetails() {
    let line = DebugLog.encode(
        timestamp: Date(),
        category: "x",
        message: "no details",
        details: [:]
    )
    check(!line.contains("\"details\""), "Empty details omitted from output")
    check(line.contains("\"cat\":\"x\""), "Still encodes category")
}

// MARK: - Test Runner

func runDebugLogTests() -> Bool {
    print("\n=== Debug Log Tests ===")

    testDebugLogWritesJSONL()
    testDebugLogMultipleEntries()
    testDebugLogRotationAtSizeCap()
    testDebugLogClearRemovesFiles()
    testDebugLogTail()
    testDebugLogTailMoreThanAvailable()
    testDebugLogExportIncludesArchive()
    testDebugLogExportEmptyReturnsNil()
    testDebugLogEncodeDetails()
    testDebugLogEncodeNoDetails()

    return printTestSummary("Debug Log Tests")
}
