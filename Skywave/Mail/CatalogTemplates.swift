import Foundation
import WinlinkKit

/// Vordefinierte Katalog- und Saildocs-Abfragen fürs «Abfrage»-Menü in
/// der Mailbox. Jede Vorlage öffnet ein vorbefülltes Compose-Fenster —
/// der Nutzer sieht und editiert die Anfrage vor dem Absenden.
enum CatalogTemplate: String, CaseIterable, Identifiable {
    case saildocsWeb
    case saildocsGRIB
    case winlinkHelp
    case winlinkItem

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .saildocsWeb: String(localized: "Webseite als Text (Saildocs) …")
        case .saildocsGRIB: String(localized: "GRIB-Wetterdaten (Saildocs) …")
        case .winlinkHelp: String(localized: "Winlink-Katalog-Hilfe anfordern")
        case .winlinkItem: String(localized: "Winlink-Katalog-Item …")
        }
    }

    var help: String {
        switch self {
        case .saildocsWeb:
            String(localized: "Saildocs liefert eine Webseite als Text-Mail zurück — URL im Text ergänzen")
        case .saildocsGRIB:
            String(localized: "GRIB-Wetterdaten für den vorbereiteten Europa-Ausschnitt anfordern")
        case .winlinkHelp:
            String(localized: "Hilfedatei mit allen verfügbaren Katalog-Items anfordern")
        case .winlinkItem:
            String(localized: "Beliebiges Katalog-Item anfordern — Item-Name in den Text schreiben")
        }
    }

    /// Vorbefüllter Entwurf; Platzhalter ersetzt der Nutzer im Compose.
    var draft: MessageDraft {
        switch self {
        case .saildocsWeb:
            CatalogRequest.saildocsFetch(urls: ["https://"])
        case .saildocsGRIB:
            CatalogRequest.saildocsGRIB("GFS:50N,42N,5W,20E|0.5,0.5|0,24,48,72|PRMSL,WIND")
        case .winlinkHelp:
            CatalogRequest.winlinkInquiry(items: [CatalogRequest.helpItem])
        case .winlinkItem:
            CatalogRequest.winlinkInquiry(items: [])
        }
    }
}
