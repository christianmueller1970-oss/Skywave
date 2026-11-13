import Foundation

/// Persists each exchange's session log to a timestamped file so it
/// survives app restarts and can be reviewed or copied later. The live
/// `ExchangeController.log` array still drives the UI; this just mirrors
/// every line to disk under Application Support/Skywave/Logs.
@MainActor final class SessionLogStore {
    private var handle: FileHandle?

    /// Folder that holds the per-session log files. Inside the app's
    /// sandbox container, so it is always writable without a bookmark.
    static var logsDirectory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Skywave/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
        return base
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    private static let lineStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Funkbezogene Zeiten stehen in UTC.
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Opens a fresh log file for a new exchange, closing the previous one.
    func startNewSession() {
        try? handle?.close()
        handle = nil
        let now = Date()
        let url = Self.logsDirectory
            .appendingPathComponent("session-\(Self.fileStamp.string(from: now)).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        writeRaw(String(localized: "=== Skywave-Sitzung \(Self.fileStamp.string(from: now)) (Ortszeit) — Zeilen in UTC ==="))
    }

    /// Appends one log line with a timestamp.
    func append(_ line: String) {
        writeRaw("[\(Self.lineStamp.string(from: Date()))] \(line)")
    }

    private func writeRaw(_ text: String) {
        guard let handle, let data = (text + "\n").data(using: .utf8) else { return }
        try? handle.write(contentsOf: data)
    }
}
