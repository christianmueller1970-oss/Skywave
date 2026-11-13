import Foundation
import WinlinkKit

/// Woher die Koordinaten einer Positionsmeldung kommen.
enum PositionSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case locator
    case manual
    case locationService

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .locator: "Locator"
        case .manual: String(localized: "Manuell")
        case .locationService: String(localized: "Standortdienst")
        }
    }
}

/// Eine aufgelöste Position samt Hinweis, wie genau sie ist — der
/// Nutzer soll sehen, ob er einen Zellen-Mittelpunkt oder einen
/// echten Fix meldet.
struct ResolvedPosition: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracyText: String
    /// Messzeitpunkt eines Fixes; nil, wenn die Position nicht gemessen
    /// wurde (Locator, Handeingabe) — dann gilt «jetzt».
    var timestamp: Date? = nil

    /// «47.5000° N, 9.3000° E»
    var coordinateText: String {
        let lat = String(format: "%.4f° %@", abs(latitude), latitude < 0 ? "S" : "N")
        let lon = String(format: "%.4f° %@", abs(longitude), longitude < 0 ? "W" : "E")
        return "\(lat), \(lon)"
    }
}

/// Reine Logik des Positionsdialogs: Quelle → Koordinaten + Genauigkeit,
/// und daraus die Winlink-Meldung. Ohne UI, damit es sich testen lässt.
enum PositionResolver {

    /// Mittelpunkt der Locator-Zelle; der Hinweis nennt die Zellgrösse,
    /// damit klar ist, dass das keine GPS-Koordinate ist.
    static func fromLocator(_ locator: String) -> ResolvedPosition? {
        guard let grid = try? Maidenhead(locator: locator) else { return nil }
        let (widthKm, heightKm) = cellSizeKm(locator: grid.locator, latitude: grid.latitude)
        return ResolvedPosition(
            latitude: grid.latitude, longitude: grid.longitude,
            accuracyText: String(localized:
                "Mittelpunkt von \(grid.locator), Zelle ca. \(swiss(widthKm)) × \(swiss(heightKm)) km"))
    }

    /// Von Hand eingegebene Dezimalgrade; Komma oder Punkt, Bereich
    /// ±90 / ±180.
    static func fromManual(latitude: String, longitude: String) -> ResolvedPosition? {
        guard let lat = parseDegrees(latitude), let lon = parseDegrees(longitude),
            (-90...90).contains(lat), (-180...180).contains(lon)
        else { return nil }
        return ResolvedPosition(latitude: lat, longitude: lon, accuracyText: String(localized: "Wie eingegeben"))
    }

    /// Fix des Standortdienstes mit seiner gemeldeten Unsicherheit.
    static func fromService(
        latitude: Double, longitude: Double, accuracyMeters: Double, timestamp: Date
    ) -> ResolvedPosition {
        let accuracy =
            accuracyMeters >= 1000
            ? "± \(swiss(accuracyMeters / 1000)) km"
            : "± \(Int(accuracyMeters.rounded())) m"
        let age = Date().timeIntervalSince(timestamp)
        let ageText = age >= 120 ? String(localized: ", \(Int(age / 60)) min alt") : ""
        return ResolvedPosition(
            latitude: latitude, longitude: longitude,
            accuracyText: String(localized: "Standortdienst (WLAN/IP-Ortung), \(accuracy)\(ageText)"),
            timestamp: timestamp)
    }

    /// Die fertige Meldung. DATE ist der Messzeitpunkt des Fixes —
    /// ein älterer Standort darf bei Winlink nicht als aktuell
    /// erscheinen; ohne Messung gilt «jetzt». Der Kommentar wird auf
    /// die 80 Zeichen des Formats gekürzt.
    static func report(
        position: ResolvedPosition, comment: String, now: Date = Date()
    ) -> PositionReport {
        PositionReport(
            date: position.timestamp ?? now,
            latitude: position.latitude, longitude: position.longitude,
            comment: String(
                comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(PositionReport.commentLimit)))
    }

    /// Breite × Höhe der Locator-Zelle in km (4, 6 oder 8 Zeichen).
    static func cellSizeKm(locator: String, latitude: Double) -> (Double, Double) {
        let (lonDeg, latDeg): (Double, Double) =
            switch locator.count {
            case ..<6: (2, 1)
            case 6, 7: (2.0 / 24, 1.0 / 24)
            default: (2.0 / 240, 1.0 / 240)
            }
        let kmPerDegree = 111.2
        return (lonDeg * kmPerDegree * cos(latitude * .pi / 180), latDeg * kmPerDegree)
    }

    static func parseDegrees(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "°", with: "")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    /// 6,3 statt 6.3.
    private static func swiss(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
