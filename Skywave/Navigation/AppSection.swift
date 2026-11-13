import SwiftUI

/// Ein Bereich des Hauptfensters. Die Seitenleiste führt sie in den
/// Gruppen Postfach, Funk und Werkzeuge; ein Klick zeigt den Bereich
/// rechts daneben. Siehe `docs/plans/2026-11-12-ui-konzept.md`.
enum AppSection: Hashable, Sendable {
    /// Ein Ordner des Postfachs mit Nachrichtenliste und Lesebereich.
    case folder(MailFolder)
    /// Gateway-Verzeichnis.
    case gateways
    /// Verbindungshistorie als Liste.
    case connections
    /// Gespeicherte Sitzungsprotokolle.
    case logs
    /// Funkgerät: Status, Verbinden, Tune, Pegel.
    case rig
    /// Adressbuch.
    case contacts
    /// Positionsmeldung an Winlink.
    case position
    /// Katalog-Vorlagen, gespeicherte Abfragen und GRIB-Assistent.
    case queries

    /// Die Bereiche ausserhalb des Postfachs, in der Reihenfolge der
    /// Seitenleiste.
    static let radio: [AppSection] = [.gateways, .connections, .logs, .rig]
    static let tools: [AppSection] = [.contacts, .position, .queries]

    var title: String {
        switch self {
        case .folder(let folder): folder.displayName
        case .gateways: String(localized: "Gateways")
        case .connections: String(localized: "Verbindungen")
        case .logs: String(localized: "Protokolle")
        case .rig: String(localized: "Funkgerät")
        case .contacts: String(localized: "Kontakte")
        case .position: String(localized: "Positionsmeldung")
        case .queries: String(localized: "Abfragen")
        }
    }

    var symbol: String {
        switch self {
        case .folder(let folder): folder.symbol
        case .gateways: "antenna.radiowaves.left.and.right"
        case .connections: "clock.arrow.circlepath"
        case .logs: "list.bullet.rectangle"
        case .rig: "dial.medium"
        case .contacts: "person.2"
        case .position: "location"
        case .queries: "arrow.down.doc"
        }
    }

    /// Der Ordner, wenn der Bereich zum Postfach gehört.
    var folder: MailFolder? {
        if case .folder(let folder) = self { folder } else { nil }
    }
}

extension MailFolder {
    /// Symbol in der Seitenleiste.
    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .drafts: "doc.badge.ellipsis"
        case .outbox: "paperplane"
        case .sent: "checkmark.seal"
        case .trash: "trash"
        case .custom: "folder"
        }
    }
}

/// Welcher Bereich im Hauptfenster gezeigt wird. Ein Objekt für die
/// ganze App, damit auch Menübefehle den Bereich wechseln können.
@MainActor @Observable final class AppNavigation {
    var section: AppSection = .folder(.inbox)

    /// Der zuletzt gezeigte Ordner — bleibt stehen, während ein anderer
    /// Bereich offen ist, damit Ordner-Dialoge ein Ziel haben.
    private(set) var lastFolder: MailFolder = .inbox

    func show(_ section: AppSection) {
        self.section = section
        if let folder = section.folder { lastFolder = folder }
    }
}

/// Was ein eingebetteter Bereich tut, wenn er «fertig» ist (Meldung in
/// den Postausgang gelegt, Verbindung gestartet). In einem eigenen
/// Fenster fehlt der Wert, dort schliesst sich das Fenster.
struct FinishSectionAction: Sendable {
    let run: @MainActor @Sendable () -> Void
}

extension EnvironmentValues {
    @Entry var finishSection: FinishSectionAction?
}
