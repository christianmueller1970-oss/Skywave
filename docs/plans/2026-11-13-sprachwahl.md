# Feature: Sprachwahl Deutsch / English

Stand: 2026-11-13 · Projekt: Skywave · Branch: feature/sprachwahl (gemergt nach `main` am 2026-11-13) · Status: umgesetzt, Durchsicht durch Chris grün

## Ziel
Skywave lässt sich vollständig auf Deutsch oder auf Englisch bedienen. Die Sprache wählt der
Nutzer in den Einstellungen der App, unabhängig von der Systemsprache. Der Wechsel gilt nach
einem Neustart, den ein Knopf «Jetzt neu starten» direkt auslöst. Danach ist die ganze App
einheitlich in der gewählten Sprache: Fenster, Menüleiste, Dialoge, Status- und
Fehlermeldungen, Berechtigungsabfragen und der Update-Dialog.

## Nicht-Ziele
- Weitere Sprachen (Französisch, Italienisch). Der Katalog lässt sie später zu, übersetzt wird
  jetzt nur Englisch.
- Sprachwechsel im laufenden Betrieb ohne Neustart.
- Übersetzung von README, Release-Notizen, Appcast und `docs/`.
- Änderungen an WinlinkKit. Das Kit enthält keine deutschen Texte.
- Arbeit an HAM-Tools. HAM-Tools ist bereits zweisprachig (de/en).

## Ausgangslage (Stand `main`, 0d630a2)
- Kein String-Katalog, keine `.lproj`. Alle Texte stehen deutsch im Code.
- Rund 1'070 Textstellen in 56 Swift-Dateien (11'546 Zeilen).
- Rund 430 davon sind SwiftUI-Aufrufe (`Text`, `Button`, `Label`, `Picker`, `Toggle`, `.help`,
  `TextField`, `Section`, `Menu`, `.navigationTitle`). Xcode zieht sie beim Build von selbst in
  den Katalog.
- Der Rest entsteht als gewöhnlicher `String` und muss von Hand auf `String(localized:)`
  umgestellt werden. Schwerpunkt ist `ExchangeController.swift` mit rund 120 Stellen
  (Statuszeilen, Fehlermeldungen, Protokollzeilen mit eingesetzten Werten).
- `String(localized:)` wird heute erst an 7 Stellen benutzt (`LevelTuningController.swift`).
- 16 berechnete Anzeigenamen (`displayName`, `title`, `summaryLine`) in Enums und Stores.
- 7 Testdateien prüfen deutsche Texte (28 Stellen, am meisten `ExchangeControllerTests`).

## Betroffene Stellen
- `project.yml` – Katalog als Ressource, Englisch als zweite Sprache des Bundles; die
  Berechtigungstexte (`INFOPLIST_KEY_NSMicrophoneUsageDescription`, Standort) bekommen eine
  englische Fassung über `InfoPlist.xcstrings`.
- `Skywave/Localizable.xcstrings` (neu) – Deutsch als Quellsprache, Englisch als Übersetzung.
- `Skywave/Settings/AppSettings.swift` – Einstellung für die App-Sprache.
- `Skywave/Settings/SettingsView.swift` – Wähler «Sprache» und Knopf «Jetzt neu starten».
- `Skywave/SkywaveApp.swift` – Neustart der App; läuft über den bestehenden Weg in
  `applicationShouldTerminate`, damit ein getasteter Sender vorher entsichert wird.
- `Skywave/Mail/ExchangeController.swift` – Status-, Fehler- und Protokolltexte.
- `Skywave/Mail/LevelTuningController.swift`, `Skywave/Radio/RigController.swift` – Meldungen.
- Enums mit Anzeigenamen: `MailStore.swift`, `OutboxRouting.swift`, `RadioTransportKind.swift`,
  `AppSettings.swift`, `AppSection.swift`, `PositionResolver.swift`, `ContactsStore.swift`,
  `ConnectionHistoryStore.swift`, `P2PConnectSheet.swift`, `ContactsView.swift`,
  `ConnectionHistoryView.swift`, `SessionLogsView.swift`.
- `Skywave/Mail/CatalogTemplates.swift` – Beschreibungen der Abfrage-Vorlagen.
- `Skywave/Navigation/MailboxCommands.swift` – Menüleiste.
- `Skywave/Radio/rig-profiles.json` – ein deutscher Modellname («Dummy-Rig (Test ohne
  Hardware)»).
- Alle übrigen Views – kein Codeumbau, nur Übersetzung im Katalog; Stellen mit
  zusammengesetzten Texten (`"Gesamt \(…) — \(…)"`) einzeln prüfen.
- `Tests/` – Sprache im Testlauf festlegen, neue Tests für Sprachwahl und Vollständigkeit.

## Entscheidungen
| Frage | Entscheidung | Warum |
|---|---|---|
| Wie wirkt der Wechsel? | Nach Neustart, mit Knopf «Jetzt neu starten» | Chris, 2026-11-13. Nur so sind auch Systemmenüs, Dateidialoge und der Sparkle-Dialog einheitlich. |
| Quellsprache | Deutsch bleibt Quellsprache, Englisch ist Übersetzung | `developmentLanguage: de` in `project.yml`; kein Text im Code muss umgeschrieben werden. |
| Ablage der Texte | Ein String-Katalog `Localizable.xcstrings` | Xcode-16-Standard, zieht SwiftUI-Texte selbst ein, zeigt fehlende Übersetzungen. |
| Technik der Sprachwahl | Sprachvorgabe der App in ihren eigenen `UserDefaults` (`AppleLanguages`), gelesen beim Start | Systemweg für eine App-eigene Sprache; wirkt auch auf AppKit, Sparkle und Berechtigungsdialoge. |
| Neustart während einer Sitzung | Knopf ist gesperrt, solange eine Sitzung, Tune oder der Pegel-Assistent läuft | Ein Neustart beendet rigctld und ardopcf; in der Sendephase unerwünscht. |
| Gespeicherte Daten | Keine Migration | Ordner liegen unter festen Namen (`drafts`, `out`, `sent`, `trash`) auf der Platte, die Historie speichert `outcome` als Wert; Anzeigenamen werden erst bei der Anzeige gebildet. |
| Maschinenlesbare Zeitstempel | Bleiben `en_US_POSIX` | Dateinamen der Protokolle und UTC-Angaben dürfen nicht von der Sprache abhängen. |
| Rufzeichen, Betriebsarten, Frequenzen, Modemausgaben (`vara: …`) | Unübersetzt | Fachbegriffe und Fremdausgaben. |
| Sprache des Sitzungsprotokolls | Gewählte Sprache, im Fenster und in den Protokolldateien | Chris, 2026-11-13. Ein englischsprachiger OM muss sein eigenes Protokoll lesen können. |
| Vorgabe ohne Wahl | Deutsch | Chris, 2026-11-13. Bestehende Installationen ändern sich nicht; die Systemsprache wird nicht übernommen. |
| Zahlen- und Datumsformate | Region des Systems bleibt, nur die Sprache wechselt | Chris, 2026-11-13. `3'613 kHz` bleibt auf einem Schweizer Mac so; kein Umbau an den Formatier-Stellen. |
| HAM-Tools | Keine Portierung | Chris, 2026-11-13: HAM-Tools ist längst de/en, die Arbeit betrifft nur Skywave. |
| Erster Start in der falschen Sprache | Die App schreibt die Vorgabe und startet sich einmal selbst neu, noch bevor ein Fenster erscheint | Am Debug-Build geprüft (2026-11-13): eine beim Start geschriebene Vorgabe gilt erst ab dem nächsten Start. Betrifft nur den ersten Start auf einem nicht deutschen System; danach stimmt die Vorgabe, es gibt keine Schleife. |
| Technik des Neustarts | Hilfsprozess (`/bin/sh`) wartet auf das Ende der alten Instanz und öffnet die App dann neu | Am Debug-Build in der Sandbox geprüft; die alte Instanz gibt zuerst den seriellen Port und den rigctld-Port frei, das Funkgerät war nach dem Neustart wieder verbunden. |
| Englisch im Projekt | xcodegen trägt `en` selbst als bekannte Sprache ein, sobald der Katalog sie enthält | Geprüft an `knownRegions` im erzeugten Projekt; keine Einstellung in `project.yml` nötig. |
| Wie kommen die Texte in den Katalog? | `scripts/sync-strings.sh` (Lokalisierungs-Export), dazu `SWIFT_EMIT_LOC_STRINGS` in `project.yml` | `xcodebuild build` füllt den Katalog nicht. Ohne die Compiler-Einstellung fand der Export nur `Text("…")` (187 statt 475 Texte); xcodegen setzt sie nicht von selbst. |
| Begriffe | Funk = Radio, Funkgerät = Rig, Versandweg = Route, Abfragen = Queries, Protokoll = Log, Sendepegel = Drive level, Gegenstation = Remote station | Übliche Wörter im englischen Amateurfunk; Durchsicht durch Chris in Etappe 5. |
| Zahlen in Meldungen | Portnummern und Baudraten werden als Text eingesetzt (`String(port)`), Stückzahlen als Zahl | In übersetzten Texten formatiert das System Zahlen nach Region, aus Port 47178 wurde «47'178» (von `RigControllerTests` aufgedeckt). |
| Satzbausteine | «per CI-V» / «über rigctld», « an %@ (%@ Baud)» und der Nachsatz zur QRG bleiben eingesetzte Bausteine und sind einzeln übersetzt | Die Sätze sind in beiden Sprachen so gebaut, dass der Baustein an derselben Stelle passt; ein Umbau in ganze Sätze hätte die Zahl der Texte vervielfacht. |
| Nicht übersetzt | Einheiten (`s`, `min`, `B/s`, `kB`), Namen der Verfahren (VARA HF, ARDOP), Modemausgaben, das Etikett «E-Mail» für alte Kontaktdaten | Fachbegriffe, Fremdausgaben und gespeicherte Daten. |
| Tests | Der Testlauf erzwingt Deutsch | Die 28 bestehenden Textprüfungen bleiben gültig und hängen nicht von der Systemsprache des Rechners ab. |

## Offene Fragen
- (keine) Der Vorschlag, die englischen Begriffe aus HAM-Tools zu übernehmen, wurde nicht
  umgesetzt; Chris hat die hier gewählten Begriffe in der Durchsicht abgenommen.

## Etappen
1. **Gerüst:** Katalog, Einstellung, Wähler, Neustart, Berechtigungstexte. Die App läuft
   danach wie bisher deutsch; Englisch zeigt noch überall den deutschen Text. **Erledigt
   2026-11-13.**
2. **Views:** eingezogene SwiftUI-Texte übersetzen. **Erledigt 2026-11-13:** 475 Texte im
   Katalog, alle mit englischer Fassung. Zusammengesetzte Texte, deren Bausteine als `String`
   aus dem Code kommen (zum Beispiel «Frequenz und Modus werden vor dem Verbinden %@
   eingestellt»), sind übersetzt, der eingesetzte Baustein folgt in Etappe 3.
3. **Meldungen:** `ExchangeController`, `RigController`, Enums und Stores auf
   `String(localized:)`. **Erledigt 2026-11-13:** 37 Dateien, 241 weitere Texte, der Katalog
   hat 716 Einträge. Einzahl und Mehrzahl bleiben wie bisher zwei getrennte Texte.
4. **Tests:** Sprache im Testlauf, Sprachwahl, Vollständigkeit des Katalogs, englische Texte
   im gebauten Bundle. **Erledigt 2026-11-13:** 165 Tests grün.
5. **Durchsicht:** Chris liest die englischen Funkbegriffe gegen und klickt die App einmal
   auf Englisch durch. **Erledigt 2026-11-13:** «saubere Arbeit, grün» (Angabe Chris);
   Codex-Review ohne Befunde.

## Abnahmekriterien
- [x] Einstellungen zeigen einen Wähler «Sprache» mit Deutsch und English; nach «Jetzt neu
  starten» erscheint die App in der gewählten Sprache, auch wenn das System anders eingestellt
  ist (Handgriff, beide Richtungen). Belegt 2026-11-13 am Debug-Build: Deutsch → English →
  Deutsch, Systemmenüs und der Abschnitt «Sprache» wechseln mit; die übrigen Texte folgen ab
  Etappe 2.
- [x] Die Wahl übersteht Beenden und Neustart (Test auf der Einstellung).
- [x] Der Knopf «Jetzt neu starten» ist während einer laufenden Sitzung gesperrt (Test).
- [x] Jeder Eintrag im Katalog hat eine englische Übersetzung im Zustand «translated» (Test,
  der `Localizable.xcstrings` liest). `CatalogCompletenessTests`.
- [x] Auf Englisch zeigen Menüleiste, Einstellungen, Postfach, Verbindungen, Funkgerät,
  Protokolle und alle Dialoge keinen deutschen Text (Durchklick Chris nach Checkliste). Durchsicht Chris
  2026-11-13 grün; einziger Hinweis war ein eigener Ordner («gelesen»), der seinen Namen behält.
- [x] Status- und Fehlermeldungen einer Sitzung liegen auf Englisch im gebauten Bundle
  (`EnglishBundleTests`). Abweichung vom Entwurf: kein Sitzungslauf über die Pipe auf Englisch,
  weil der Testlauf fest deutsch ist; eine echte Sitzung auf Englisch gehört in den Durchklick.
- [ ] Berechtigungsabfrage für Mikrofon und Standort erscheint in der gewählten Sprache
  (Handgriff mit zurückgesetzter Berechtigung).
- [ ] Bestehendes Postfach, Kontakte, Abfragen und Historie sind nach dem Sprachwechsel
  unverändert vorhanden (Handgriff, vorher Backup).
- [x] Bestehende Tests grün, Build auf dem DEV-Mac erfolgreich (165 Tests, 2026-11-13).

## Risiken / Backup
- **Daten:** Das Feature ändert kein Datenformat. Der Durchklick läuft trotzdem auf dem echten
  Postfach, weil Debug- und Release-App denselben Container nutzen: vor dem ersten Test auf
  Englisch den Datenordner sichern.
- **Umfang:** Der Branch berührt fast jede View. Er startet erst, wenn der UI-Durchtest
  abgeschlossen ist, und sollte nicht lange neben anderen UI-Branches leben (Merge-Konflikte).
- **Vergessene Texte:** Ein `String`, der nicht umgestellt wurde, bleibt auf Englisch deutsch
  stehen. Dagegen stehen der Katalog-Test und der Durchklick.
- **Mehrzahl und Satzbau:** Zusammengesetzte Sätze lassen sich nicht wortweise übersetzen;
  solche Stellen werden zu einem Text mit Platzhaltern.
- **Shack-Hardware:** Die Abnahme braucht kein Funkgerät. Eine Funksitzung auf Englisch ist
  ein Zusatztest an einem Rechner mit Gerät.
