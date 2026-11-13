import Foundation

/// The three radio paths to an RMS gateway. Telnet/CMS stays separate —
/// it needs no gateway dialog.
enum RadioTransportKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case varaHF
    case varaFM
    case ardop

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .varaHF: "VARA HF"
        case .varaFM: "VARA FM"
        case .ardop: "ARDOP"
        }
    }

    /// The modem program the user has to run, for error messages.
    var modemName: String {
        switch self {
        case .varaHF, .varaFM: "VARA"
        case .ardop: "ARDOP"
        }
    }

    /// VARA FM negotiates its bandwidth itself.
    var hasBandwidthChoice: Bool { self != .varaFM }
}
