import Foundation
import Testing

@testable import Skywave

/// Sprachwahl: gespeicherte Wahl, Vorgabe und die Sperre des Neustarts.
@MainActor
struct AppLanguageTests {
    /// Eigene, leere Vorgaben je Test — die echten bleiben unberührt.
    private func makeDefaults() -> UserDefaults {
        let name = "AppLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func withoutChoiceGermanApplies() {
        #expect(AppLanguage.selected(in: makeDefaults()) == .german)
    }

    @Test func unknownStoredValueFallsBackToGerman() {
        let defaults = makeDefaults()
        defaults.set("fr", forKey: AppLanguage.selectionKey)
        #expect(AppLanguage.selected(in: defaults) == .german)
    }

    @Test func choiceIsStoredAndPreparedForNextLaunch() {
        let name = "AppLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        // Gespeicherte Domäne lesen, nicht `stringArray(forKey:)`: der
        // Testlauf setzt `AppleLanguages` als Startargument, und das
        // überdeckt beim normalen Lesen jeden gespeicherten Wert.
        func stored() -> [String]? {
            defaults.persistentDomain(forName: name)?[AppLanguage.systemKey] as? [String]
        }

        AppLanguage.select(.english, in: defaults)
        #expect(AppLanguage.selected(in: defaults) == .english)
        #expect(stored() == ["en"])

        AppLanguage.select(.german, in: defaults)
        #expect(AppLanguage.selected(in: defaults) == .german)
        #expect(stored() == ["de"])
    }

    /// Beim Start wird die Vorgabe nur geschrieben, wenn sie nicht passt —
    /// daran hängt, dass der automatische Neustart höchstens einmal läuft.
    @Test func launchWritesPreferenceOnlyWhenItDiffers() {
        let name = "AppLanguageTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(AppLanguage.applyAtLaunch(in: defaults, domainName: name))
        #expect(defaults.persistentDomain(forName: name)?[AppLanguage.systemKey] as? [String] == ["de"])
        #expect(!AppLanguage.applyAtLaunch(in: defaults, domainName: name))

        defaults.set("en", forKey: AppLanguage.selectionKey)
        #expect(AppLanguage.applyAtLaunch(in: defaults, domainName: name))
        #expect(!AppLanguage.applyAtLaunch(in: defaults, domainName: name))
    }

    @Test func nativeNamesAreNeverTranslated() {
        #expect(AppLanguage.german.nativeName == "Deutsch")
        #expect(AppLanguage.english.nativeName == "English")
    }

    @Test func relaunchIsBlockedWhileRadioIsBusy() {
        #expect(!AppRelauncher.isBlocked(isRunning: false, isTuning: false, isManualTuning: false))
        #expect(AppRelauncher.isBlocked(isRunning: true, isTuning: false, isManualTuning: false))
        #expect(AppRelauncher.isBlocked(isRunning: false, isTuning: true, isManualTuning: false))
        #expect(AppRelauncher.isBlocked(isRunning: false, isTuning: false, isManualTuning: true))
    }

    /// Der Testlauf erzwingt Deutsch, damit Textprüfungen nicht von der
    /// Systemsprache des Rechners abhängen.
    @Test func testRunIsGerman() {
        #expect(AppLanguage.active == .german)
    }
}

/// Die englischen Texte liegen wirklich im gebauten Bundle — nicht nur im
/// Katalog. Der Testlauf selbst ist deutsch, also wird das englische
/// Teil-Bundle direkt befragt.
@MainActor
struct EnglishBundleTests {
    private func english(_ key: String) throws -> String {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "⟂fehlt", table: nil)
    }

    /// Anzeigenamen aus dem Code (Ordner, Bereiche, Ergebnisse).
    @Test func displayNamesAreEnglish() throws {
        #expect(try english("Posteingang") == "Inbox")
        #expect(try english("Postausgang") == "Outbox")
        #expect(try english("Funkgerät") == "Rig")
        #expect(try english("Erfolgreich") == "Successful")
    }

    /// Status-, Fehler- und Protokolltexte einer Sitzung.
    @Test func sessionMessagesAreEnglish() throws {
        #expect(try english("Austausch über Internet (CMS)") == "Exchange via Internet (CMS)")
        #expect(try english("Keine neuen Nachrichten") == "No new messages")
        #expect(try english("Abbruch angefordert …") == "Abort requested …")
        #expect(
            try english("Die Verbindung wurde unerwartet beendet. Bitte erneut versuchen.")
                == "The connection was closed unexpectedly. Please try again.")
        // Platzhalter bleiben erhalten und stehen an der richtigen Stelle.
        #expect(
            String(format: try english("Verbinde mit %@:%@ …"), "server.winlink.org", "8772")
                == "Connecting to server.winlink.org:8772 …")
    }

    /// Im deutschen Testlauf liefern dieselben Stellen weiter Deutsch.
    @Test func germanStaysGerman() {
        #expect(MailFolder.inbox.displayName == "Posteingang")
        #expect(String(localized: "Keine neuen Nachrichten") == "Keine neuen Nachrichten")
    }
}
