import Foundation

/// One dialable RMS-gateway channel for the connect dialog's picker and
/// the gateway window.
///
/// Comes either from the built-in starter list (`GatewayDirectory`) or
/// from the Winlink web service. `id` must stay stable across both:
/// `settings.ardopChannelID` and every favourite reference it.
struct GatewayChannel: Identifiable, Hashable, Codable, Sendable {
    let gateway: String
    let grid: String
    let kind: RadioTransportKind
    /// Winlink lists CENTER frequencies.
    let centerHz: Int
    /// ARDOP: maximum bandwidth (500/2000); VARA HF: bandwidth in Hz.
    /// nil when the web service reported nothing usable — the UI then
    /// leaves the user's bandwidth setting alone instead of guessing.
    let bandwidthHz: Int?

    // Everything below arrives with the web service and has a default,
    // so the built-in list keeps its short initialiser.

    var serviceCode: String = "PUBLIC"
    /// Great-circle distance from the operator's locator, computed
    /// locally so it survives a change of locator.
    var distanceKm: Int?
    var headingDegrees: Int?
    var source: Source = .builtin

    enum Source: String, Codable, Sendable {
        case builtin
        case webService
    }

    init(
        gateway: String, grid: String, kind: RadioTransportKind, centerHz: Int,
        bandwidthHz: Int?, serviceCode: String = "PUBLIC", distanceKm: Int? = nil,
        headingDegrees: Int? = nil, source: Source = .builtin
    ) {
        self.gateway = gateway
        self.grid = grid
        self.kind = kind
        self.centerHz = centerHz
        self.bandwidthHz = bandwidthHz
        self.serviceCode = serviceCode
        self.distanceKm = distanceKm
        self.headingDegrees = headingDegrees
        self.source = source
    }

    var id: String { "\(gateway)/\(kind.rawValue)/\(centerHz)" }

    /// What the rig display must show: SSB data modes sit 1.5 kHz
    /// below the center (USB-D); FM dials the center directly.
    var dialHz: Int { kind == .varaFM ? centerHz : centerHz - 1500 }

    var band: String { Self.band(forHz: centerHz) }

    /// Amateurfunkband zu einer Frequenz; alles über 30 MHz ist «UKW».
    static func band(forHz centerHz: Int) -> String {
        switch centerHz {
        case ..<2_000_000: "160 m"
        case ..<4_000_000: "80 m"
        case ..<5_500_000: "60 m"
        case ..<7_300_000: "40 m"
        case ..<10_200_000: "30 m"
        case ..<14_400_000: "20 m"
        case ..<18_200_000: "17 m"
        case ..<21_500_000: "15 m"
        case ..<25_100_000: "12 m"
        case ..<30_000_000: "10 m"
        default: String(localized: "UKW")
        }
    }

    // MARK: Sortierschlüssel für die Tabelle
    //
    // `Int?` ist in Swift nicht `Comparable`, taugt also nicht als
    // `TableColumn(value:)`. Ohne Schlüssel bleibt eine Spalte stumm —
    // der Kopf lässt sich anklicken, es passiert nur nichts. Unbekanntes
    // sortiert ans Ende, nicht an den Anfang.

    var transportSortKey: String { kind.rawValue }
    var distanceSortKey: Int { distanceKm ?? .max }
    var headingSortKey: Int { headingDegrees ?? .max }
    var bandwidthSortKey: Int { bandwidthHz ?? .max }
    var sourceSortKey: String { source.rawValue }

    /// Menu row: "HB9MM · 40 m · Dial 7'051,5 kHz".
    var menuLabel: String {
        "\(gateway) · \(band) · Dial \(Self.kilohertz(dialHz)) kHz"
    }

    /// Menu row with what the web service adds:
    /// "HB9AK · 40 m · Dial 7'051,5 kHz · 168 km · 246°".
    var detailLabel: String {
        var text = menuLabel
        if let distanceKm {
            text += " · \(distanceKm) km"
        }
        if let headingDegrees {
            text += String(format: " · %03d°", headingDegrees)
        }
        return text
    }

    /// Swiss-format kHz with one decimal: 7'051,5.
    static func kilohertz(_ hz: Int) -> String {
        let tenths = hz / 100
        var digits = Array(String(tenths / 10))
        var index = digits.count - 3
        while index > 0 {
            digits.insert("'", at: index)
            index -= 3
        }
        return String(digits) + "," + String(tenths % 10)
    }
}
