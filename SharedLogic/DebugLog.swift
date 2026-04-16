import Foundation

/// On-device debug log with size-based rotation.
///
/// Writes newline-delimited JSON ("JSONL") to a file on disk. Each entry is
/// a compact JSON object: `{"ts":"...","cat":"...","msg":"...","details":{...}}`.
///
/// When the active file exceeds `maxBytes`, it is renamed to `<file>.1`
/// (overwriting any previous archive) and a new empty active file is started.
/// Total on-disk footprint is bounded to roughly `2 * maxBytes`.
///
/// Thread-safe: all mutations go through an internal lock. Writes are
/// synchronous (tiny appends — bounded cost), so callers do not need to await.
///
/// Pure Swift — no Apple framework dependencies, Windows-testable.
final class DebugLog {

    /// Shared instance writing to `Documents/debug.jsonl` on iOS. On non-iOS
    /// platforms falls back to the system temp dir so Models tests can link.
    static let shared: DebugLog = {
        let fm = FileManager.default
        let baseDir: URL
        if let docs = try? fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            baseDir = docs
        } else {
            baseDir = fm.temporaryDirectory
        }
        return DebugLog(fileURL: baseDir.appendingPathComponent("debug.jsonl"))
    }()

    private let fileURL: URL
    private let archiveURL: URL
    private let maxBytes: Int
    private let lock = NSLock()

    /// - Parameters:
    ///   - fileURL: Path to the active log file.
    ///   - maxBytes: Byte threshold at which rotation occurs. Default 1 MB.
    init(fileURL: URL, maxBytes: Int = 1_000_000) {
        self.fileURL = fileURL
        self.archiveURL = fileURL.appendingPathExtension("1")
        self.maxBytes = maxBytes
    }

    /// Path to the active (current) log file.
    var activeFileURL: URL { fileURL }

    /// Byte size of the active log file, or 0 if it doesn't exist.
    var activeByteCount: Int {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    /// Records a debug event.
    ///
    /// - Parameters:
    ///   - category: Short dotted tag like "ocr.vision" or "ocr.quality".
    ///   - message: Human-readable summary.
    ///   - details: Optional key/value payload. Values are stringified on write.
    func log(
        category: String,
        message: String,
        details: [String: String] = [:]
    ) {
        let line = Self.encode(
            timestamp: Date(),
            category: category,
            message: message,
            details: details
        )
        lock.lock()
        defer { lock.unlock() }
        append(line: line)
        if activeByteCountLocked() > maxBytes {
            rotateLocked()
        }
    }

    /// Deletes both the active log and any archive. Idempotent.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: archiveURL)
    }

    /// Returns the full contents of the active log as a string. Empty if no
    /// log exists yet. Does NOT include the archive (by design — the export
    /// UI includes both via `export()`).
    func readActive() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Returns the last `n` lines of the active log. Useful for showing a
    /// recent tail in the debug UI without loading the whole file.
    func tail(lines n: Int) -> [String] {
        let content = readActive()
        let all = content.split(separator: "\n", omittingEmptySubsequences: true)
        let start = max(0, all.count - n)
        return all[start..<all.count].map(String.init)
    }

    /// Writes archive + active concatenated to a temporary file and returns
    /// its URL. Intended for the iOS `ShareLink` export flow. Returns nil if
    /// nothing has been logged yet.
    func export() -> URL? {
        lock.lock()
        defer { lock.unlock() }

        var combined = Data()
        if let data = try? Data(contentsOf: archiveURL) {
            combined.append(data)
            if !combined.isEmpty && combined.last != 0x0A {
                combined.append(0x0A)
            }
        }
        if let data = try? Data(contentsOf: fileURL) {
            combined.append(data)
        }
        guard !combined.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("debug-\(stamp).jsonl")
        do {
            try combined.write(to: outURL)
            return outURL
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func activeByteCountLocked() -> Int {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
    }

    private func append(line: String) {
        let toWrite = line + "\n"
        guard let data = toWrite.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            // Ensure parent exists.
            let parent = fileURL.deletingLastPathComponent()
            try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
            _ = fm.createFile(atPath: fileURL.path, contents: data, attributes: nil)
            return
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private func rotateLocked() {
        let fm = FileManager.default
        try? fm.removeItem(at: archiveURL)
        try? fm.moveItem(at: fileURL, to: archiveURL)
    }

    /// Builds one JSONL line for the given event. Internal, exposed for tests.
    static func encode(
        timestamp: Date,
        category: String,
        message: String,
        details: [String: String]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var dict: [String: Any] = [
            "ts": formatter.string(from: timestamp),
            "cat": category,
            "msg": message,
        ]
        if !details.isEmpty {
            dict["details"] = details
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: dict,
                options: [.sortedKeys]
            ),
            let str = String(data: data, encoding: .utf8)
        else {
            return
                "{\"ts\":\"\(formatter.string(from: timestamp))\",\"cat\":\"log.encodeError\",\"msg\":\"\(category)\"}"
        }
        return str
    }
}
