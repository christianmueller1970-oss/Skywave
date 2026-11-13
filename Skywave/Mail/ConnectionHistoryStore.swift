import Foundation
import Observation

/// Ein Verbindungsversuch — über Funk zu einem Gateway oder über
/// Internet zum CMS — mit dem, was unterwegs wichtig ist: wann, wie
/// lange, wie viel ging durch, hat es geklappt.
struct ConnectionRecord: Identifiable, Hashable, Codable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case success
        case failed
        case aborted
    }

    var id = UUID()
    /// Beginn des Versuchs (UTC in der Datei).
    var date: Date
    /// Gateway-Rufzeichen; beim CMS der Host.
    var gateway: String
    /// nil = Internet (Telnet).
    var kind: RadioTransportKind?
    /// Center-Frequenz des Kanals, wenn aus dem Verzeichnis gewählt.
    var centerHz: Int?
    var durationSeconds: TimeInterval
    var bytesSent: Int
    var bytesReceived: Int
    var sent: Int
    var received: Int
    var outcome: Outcome
    var errorText: String?

    var band: String? { centerHz.map(GatewayChannel.band(forHz:)) }

    /// Nachrichten-Bytes je Sekunde über die ganze Sitzung — inklusive
    /// Verbindungsaufbau, darum eher pessimistisch, aber vergleichbar.
    var bytesPerSecond: Double? {
        let bytes = bytesSent + bytesReceived
        guard bytes > 0, durationSeconds > 0 else { return nil }
        return Double(bytes) / durationSeconds
    }

    /// «4 min» / «48 s».
    var durationText: String {
        durationSeconds < 90
            ? "\(Int(durationSeconds.rounded())) s"
            : "\(Int((durationSeconds / 60).rounded())) min"
    }

    /// «180 B/s» — nil ohne Nutzdaten.
    var rateText: String? {
        bytesPerSecond.map { "\(Int($0.rounded())) B/s" }
    }

    /// «18.07. 21:14 UTC · 4 min · 180 B/s» bzw. mit Fehlerhinweis.
    var summaryLine: String {
        var parts = [Self.stamp.string(from: date) + " UTC"]
        switch outcome {
        case .success:
            parts.append(durationText)
            if let rateText { parts.append(rateText) }
        case .aborted:
            parts.append(String(localized: "abgebrochen"))
        case .failed:
            parts.append(String(localized: "fehlgeschlagen"))
        }
        return parts.joined(separator: " · ")
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd.MM. HH:mm"
        return f
    }()
}

/// Verbindungs-Historie als JSON im Datenordner (`connection-history.json`),
/// neueste zuerst, auf `limit` Einträge begrenzt. Die Gateway-Liste und
/// der Verbindungsdialog zeigen daraus den letzten Kontakt je Kanal.
@MainActor @Observable final class ConnectionHistoryStore {
    private(set) var records: [ConnectionRecord] = []

    static let limit = 500

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func record(_ record: ConnectionRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit {
            records.removeLast(records.count - Self.limit)
        }
        save()
    }

    /// Alle Versuche zu einem Gateway über einen Weg, neueste zuerst.
    func records(gateway: String, kind: RadioTransportKind?) -> [ConnectionRecord] {
        let call = gateway.uppercased()
        return records.filter { $0.gateway.uppercased() == call && $0.kind == kind }
    }

    func last(gateway: String, kind: RadioTransportKind?) -> ConnectionRecord? {
        records(gateway: gateway, kind: kind).first
    }

    func lastSuccess(gateway: String, kind: RadioTransportKind?) -> ConnectionRecord? {
        records(gateway: gateway, kind: kind).first { $0.outcome == .success }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? Self.decoder.decode([ConnectionRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
