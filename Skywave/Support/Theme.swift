import SwiftUI

/// Die Farben der App an einer Stelle. Die Werte liegen als benannte
/// Farben im Asset-Katalog (hell und dunkel); die Akzentfarbe «Petrol»
/// ist dort als `AccentColor` hinterlegt und gilt für Auswahl,
/// Hauptknöpfe und Regler.
///
/// Statusfarben haben genau eine Bedeutung und stehen nie allein: immer
/// mit Symbol oder Text.
extension ShapeStyle where Self == Color {
    /// Verbunden, erfolgreich.
    static var statusOK: Color { Color("StatusOK") }
    /// Warnung, Abbruch, Versuch ohne Erfolg, Hinweis «geht über Funk».
    static var statusWarn: Color { Color("StatusWarn") }
    /// Fehler — und «SENDET»: der Sender ist getastet.
    static var statusError: Color { Color("StatusError") }
    /// In Arbeit: verbindet gerade.
    static var statusBusy: Color { Color("StatusBusy") }
    /// Favoriten-Stern.
    static var favorite: Color { Color("Favorite") }
}

extension AppSection {
    /// Farbe des Symbols in der Seitenleiste, je Gruppe: Postfach blau,
    /// Funk petrol, Werkzeuge violett.
    var tint: Color {
        switch self {
        case .folder: Color("SectionMail")
        case .gateways, .connections, .logs, .rig: Color("SectionRadio")
        case .contacts, .position, .queries: Color("SectionTools")
        }
    }
}
