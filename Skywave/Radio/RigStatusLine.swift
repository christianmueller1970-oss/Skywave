import SwiftUI

/// Eine Zeile zum Funkgerät: ob und wie Skywave es erreicht, und wo es
/// gerade steht. Für die Verbindungsdialoge und die Leiste im
/// Hauptfenster — nur Anzeige, keine Bedienung.
struct RigStatusLine: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(RigController.self) private var rig

    /// Kurzform für die Leiste im Hauptfenster: ohne erklärende Sätze.
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .lineLimit(compact ? 1 : 3)
                .foregroundStyle(isFailed ? .statusError : .primary)
                .fixedSize(horizontal: false, vertical: !compact)
        }
        .help(compact ? helpText : "")
    }

    private var usesRigctld: Bool {
        settings.rigAccess == .bundled || settings.rigAccess == .external
    }

    private var isFailed: Bool {
        guard usesRigctld, case .failed = rig.status else { return false }
        return true
    }

    private var color: Color {
        guard usesRigctld else { return .secondary }
        switch rig.status {
        case .connected: return .statusOK
        case .connecting: return .statusBusy
        case .failed: return .statusError
        case .disconnected: return .secondary
        }
    }

    private var text: String {
        switch settings.rigAccess {
        case .none:
            return compact ? String(localized: "Kein CAT") : String(localized: "Kein CAT — Frequenz und Modus von Hand einstellen")
        case .civDirect:
            let port = settings.ardopSerialPort.trimmingCharacters(in: .whitespaces)
            if port.isEmpty { return String(localized: "CI-V direkt — kein Port gewählt") }
            return compact ? String(localized: "CI-V direkt") : String(localized: "CI-V direkt an \(port)")
        case .bundled, .external:
            switch rig.status {
            case .connected:
                var parts = [rig.rigName ?? String(localized: "Funkgerät")]
                if let hz = rig.frequencyHz {
                    parts.append("\(GatewayChannel.kilohertz(hz)) kHz")
                }
                if let mode = rig.modeName { parts.append(mode) }
                return parts.joined(separator: " · ")
            case .connecting:
                return String(localized: "Verbinde mit \(rig.rigName ?? String(localized: "Funkgerät")) …")
            case .failed(let message):
                return compact ? String(localized: "Funkgerät: Fehler") : message
            case .disconnected:
                if settings.rigLink == nil {
                    return compact
                        ? String(localized: "Funkgerät nicht eingerichtet")
                        : String(localized: "Nicht eingerichtet — Einstellungen → Funkgerät")
                }
                return compact
                    ? String(localized: "Funkgerät nicht verbunden")
                    : String(localized: "Nicht verbunden — wird beim Verbinden aufgebaut")
            }
        }
    }

    private var helpText: String {
        if case .failed(let message) = rig.status, usesRigctld { return message }
        return String(localized: "Verbindung zum Funkgerät — einrichten unter Einstellungen → Funkgerät.")
    }
}
