import Foundation

/// Über welchen Weg eine Nachricht im Postausgang raus darf. Ohne
/// Kennzeichnung («beliebig») geht sie beim nächsten Austausch mit,
/// egal ob Internet oder Funk — so wie bisher. Die anderen Werte
/// halten eine Nachricht für den passenden Weg zurück: eine für die
/// Funkübung vorbereitete Mail verschwindet dann nicht beim nächsten
/// Internet-Abruf aus dem Postausgang.
enum OutboxRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case any
    case internet
    case radio
    case hold

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: String(localized: "Beliebig")
        case .internet: String(localized: "Nur Internet")
        case .radio: String(localized: "Nur Funk")
        case .hold: String(localized: "Zurückhalten")
        }
    }

    /// Kurzform für das Etikett in der Liste; `any` zeigt keines.
    var tagLabel: String? {
        switch self {
        case .any: nil
        case .internet: String(localized: "Internet")
        case .radio: String(localized: "Funk")
        case .hold: String(localized: "Zurückgehalten")
        }
    }

    var symbol: String {
        switch self {
        case .any: "arrow.triangle.branch"
        case .internet: "network"
        case .radio: "antenna.radiowaves.left.and.right"
        case .hold: "pause.circle"
        }
    }

    var help: String {
        switch self {
        case .any: String(localized: "Geht beim nächsten Austausch mit — über Internet oder Funk.")
        case .internet: String(localized: "Wird nur bei einem Austausch über Internet (CMS) gesendet.")
        case .radio: String(localized: "Wird nur bei einem Austausch über Funk (VARA/ARDOP) gesendet.")
        case .hold: String(localized: "Bleibt im Postausgang, bis die Kennzeichnung geändert wird.")
        }
    }

    /// Ob eine so gekennzeichnete Nachricht über `path` raus darf.
    func allows(_ path: ExchangePath) -> Bool {
        switch self {
        case .any: true
        case .internet: !path.isRadio
        case .radio: path.isRadio
        case .hold: false
        }
    }
}

/// Der Weg eines Austauschs — bestimmt, welche Nachrichten angeboten
/// werden, und steht während der Sitzung sichtbar in der Statuszeile.
enum ExchangePath: Equatable, Sendable {
    case internet
    case radio(RadioTransportKind, gateway: String)
    /// Direktverbindung zu einer Station; `peer` ist nil, solange auf
    /// einen Anruf gewartet wird.
    case p2p(RadioTransportKind, peer: String?)

    var isRadio: Bool {
        if case .internet = self { return false }
        return true
    }

    /// «Internet (CMS)», «ARDOP → HB9AK», «ARDOP P2P ↔ HB9XYZ».
    var displayName: String {
        switch self {
        case .internet: String(localized: "Internet (CMS)")
        case .radio(let kind, let gateway): "\(kind.displayName) → \(gateway)"
        case .p2p(let kind, let peer?): "\(kind.displayName) P2P ↔ \(peer)"
        case .p2p(let kind, nil): String(localized: "\(kind.displayName) P2P · empfangsbereit")
        }
    }

    var symbol: String {
        isRadio ? "antenna.radiowaves.left.and.right" : "network"
    }
}
