import Foundation
import Testing

/// Jeder Text im String-Katalog braucht eine fertige englische Fassung —
/// sonst steht auf Englisch mitten in der Oberfläche ein deutscher Satz.
struct CatalogCompletenessTests {
    /// Die Kataloge liegen im Quellbaum neben den Tests, nicht im Bundle
    /// (dort stecken nur die daraus erzeugten `.strings`).
    private static func catalogURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Skywave").appendingPathComponent(name)
    }

    private static func untranslated(in name: String) throws -> [String] {
        let data = try Data(contentsOf: catalogURL(name))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])
        return strings.compactMap { key, value in
            let entry = value as? [String: Any]
            let english = (entry?["localizations"] as? [String: Any])?["en"] as? [String: Any]
            if let unit = english?["stringUnit"] as? [String: Any] {
                return unit["state"] as? String == "translated" ? nil : key
            }
            // Mehrzahlformen und andere Varianten gelten als übersetzt,
            // sobald sie für Englisch angelegt sind.
            return english?["variations"] != nil ? nil : key
        }.sorted()
    }

    @Test func everyTextHasAnEnglishTranslation() throws {
        #expect(try Self.untranslated(in: "Localizable.xcstrings") == [])
    }

    @Test func everyInfoPlistTextHasAnEnglishTranslation() throws {
        #expect(try Self.untranslated(in: "InfoPlist.xcstrings") == [])
    }
}
