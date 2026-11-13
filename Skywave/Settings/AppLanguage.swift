import AppKit
import Foundation

/// Die Sprache der Oberfläche. Der Nutzer wählt sie in den Einstellungen,
/// unabhängig von der Systemsprache; sie gilt ab dem nächsten Start.
///
/// Bewusst in UserDefaults statt `settings.json`: die Wahl muss feststehen,
/// bevor ein Workspace existiert, und sie gilt für die App, nicht für
/// einen Datenordner.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    /// Eigenname der Sprache — wird nie übersetzt, damit man die eigene
    /// Sprache auch in einer fremden Oberfläche wiederfindet.
    var nativeName: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// Ohne Wahl gilt Deutsch (Entscheid Chris, 2026-11-13): bestehende
    /// Installationen ändern sich nicht, die Systemsprache zählt nicht.
    static let fallback: AppLanguage = .german

    static let selectionKey = "appLanguage"
    /// Systemschlüssel, aus dem Foundation, AppKit und Sparkle beim Start
    /// die Sprache des Prozesses bestimmen.
    static let systemKey = "AppleLanguages"

    /// Die gewählte Sprache, wie sie gespeichert ist.
    static func selected(in defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: selectionKey).flatMap(AppLanguage.init(rawValue:)) ?? fallback
    }

    /// Speichert die Wahl und stellt sie für den nächsten Start bereit.
    static func select(_ language: AppLanguage, in defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: selectionKey)
        defaults.set([language.rawValue], forKey: systemKey)
    }

    /// Sorgt beim Start dafür, dass die Sprachvorgabe der App zur Wahl
    /// passt — auch beim allerersten Start, wenn noch nichts gewählt ist.
    /// Liefert `true`, wenn die Vorgabe dabei geändert wurde.
    ///
    /// Eine hier geschriebene Vorgabe gilt erst ab dem nächsten Start
    /// (am 2026-11-13 am Debug-Build geprüft): der laufende Prozess hat
    /// seine Sprache dann schon festgelegt. Der Aufrufer startet deshalb
    /// einmal neu, wenn sich etwas geändert hat.
    @discardableResult
    static func applyAtLaunch(in defaults: UserDefaults = .standard) -> Bool {
        applyAtLaunch(in: defaults, domainName: Bundle.main.bundleIdentifier)
    }

    static func applyAtLaunch(in defaults: UserDefaults, domainName: String?) -> Bool {
        let wanted = [selected(in: defaults).rawValue]
        // Nur die eigene Domäne zählt: `stringArray(forKey:)` läse sonst
        // die Systemvorgabe mit und hielte sie für die Wahl der App.
        let domain = domainName.flatMap(defaults.persistentDomain(forName:))
        guard domain?[systemKey] as? [String] != wanted else { return false }
        defaults.set(wanted, forKey: systemKey)
        return true
    }

    /// Die Sprache, in der dieser Prozess tatsächlich läuft.
    static var active: AppLanguage {
        Bundle.main.preferredLocalizations.first
            .flatMap { AppLanguage(rawValue: String($0.prefix(2))) } ?? fallback
    }
}

/// Startet die App neu, damit eine geänderte Sprache gilt.
@MainActor enum AppRelauncher {
    /// Ein Neustart beendet rigctld und ardopcf. Während Sitzung, Tune
    /// oder Pegel-Assistent ist er deshalb gesperrt.
    static func isBlocked(isRunning: Bool, isTuning: Bool, isManualTuning: Bool) -> Bool {
        isRunning || isTuning || isManualTuning
    }

    /// Neustart aus den Einstellungen. Das Beenden läuft über den
    /// normalen Weg (`applicationShouldTerminate`).
    static func relaunch() {
        // Ohne Helfer bleibt die App offen; die Wahl ist gespeichert und
        // gilt beim nächsten Start von Hand.
        guard spawnReopenHelper() else { return }
        NSApp.terminate(nil)
    }

    /// Neustart ganz am Anfang des Starts, bevor irgendetwas läuft —
    /// für den Fall, dass der Prozess in der falschen Sprache gestartet
    /// ist (erster Start auf einem nicht deutschen System).
    static func relaunchBeforeStart() {
        guard spawnReopenHelper() else { return }
        exit(0)
    }

    /// Startet einen Hilfsprozess, der wartet, bis diese Instanz ganz
    /// beendet ist, und die App dann neu öffnet. So gibt die alte Instanz
    /// zuerst den seriellen Port und den rigctld-Port frei.
    private static func spawnReopenHelper() -> Bool {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c",
            #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open "$2""#,
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundlePath,
        ]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        do {
            try helper.run()
            return true
        } catch {
            return false
        }
    }
}
