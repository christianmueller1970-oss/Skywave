import Foundation
import Observation

/// Eine gespeicherte Abfrage: Empfänger, Betreff und Anfragetext, wie
/// sie an INQUIRY oder Saildocs gehen — das Wetterbulletin für die
/// Region, der GRIB-Ausschnitt fürs Wochenende, die Webseite mit den
/// Bandbedingungen. Öffnet ein vorbefülltes Compose-Fenster.
struct SavedQuery: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name = String(localized: "Abfrage")
    var to = ""
    var subject = ""
    var body = ""
}

/// Die gespeicherten Abfragen, als JSON im Datenordner (`queries.json`).
/// Jede Änderung speichert sofort — gleiches Muster wie `SignatureStore`.
@MainActor @Observable final class SavedQueryStore {
    private(set) var queries: [SavedQuery] = []

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    /// Adressen, deren Antworten als «Antwort auf Abfrage» gelten.
    static let queryAddresses: Set<String> = ["INQUIRY", "SERVICE", "QUERY@SAILDOCS.COM"]

    /// Ob eine Adresse ein Abfragedienst ist (INQUIRY, Saildocs).
    static func isQueryAddress(_ address: String) -> Bool {
        let normalized = address.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: "SMTP:", with: "")
        return queryAddresses.contains(normalized) || normalized.hasSuffix("@SAILDOCS.COM")
    }

    /// Legt eine Abfrage an; ein leerer Name wird «Abfrage», «Abfrage 2», …
    @discardableResult
    func add(name: String = "", to: String = "", subject: String = "", body: String = "") -> SavedQuery {
        var query = SavedQuery(to: to, subject: subject, body: body)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        query.name = trimmed.isEmpty ? uniqueName(String(localized: "Abfrage")) : trimmed
        queries.append(query)
        save()
        return query
    }

    func update(_ query: SavedQuery) {
        guard let index = queries.firstIndex(where: { $0.id == query.id }) else { return }
        queries[index] = query
        save()
    }

    func remove(_ query: SavedQuery) {
        queries.removeAll { $0.id == query.id }
        save()
    }

    func query(id: SavedQuery.ID) -> SavedQuery? {
        queries.first { $0.id == id }
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(queries.map(\.name))
        guard names.contains(base) else { return base }
        var counter = 2
        while names.contains("\(base) \(counter)") { counter += 1 }
        return "\(base) \(counter)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([SavedQuery].self, from: data)
        else { return }
        queries = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(queries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
