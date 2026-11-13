# Feature: UI-Konzept

Stand: 2026-11-12 · Projekt: Skywave · Branch: feature/ui-konzept (gemergt nach `main` am 2026-11-12) · Status: gemergt, Durchtest durch Chris steht aus

## Ziel
Alles, was Skywave kann, ist in der App sichtbar und anwählbar: über die Navigation im
Hauptfenster, über beschriftete Knöpfe und über eine vollständige Menüleiste. Niemand muss
ein Tastenkürzel, ein Kontextmenü oder einen Einstellungs-Tab kennen, um eine Funktion zu
finden. Die Oberfläche nutzt den Platz im Hauptfenster, bekommt eine einheitliche, dezente
Farbsprache und ist danach in einem einzigen Durchgang testbar (Chris, vor dem nächsten
Release).

Ein sichtbarer Entwurf (drei Ansichten: Postfach, Verbindungen, Funkgerät) lag Chris bei der
Entscheidung vor; er ist nicht Teil des Repos.

## Ausgangslage (Stand `main`, 3719b15)
Was heute versteckt ist oder nur über Umwege erreichbar:

| Funktion | Heute erreichbar über | Problem |
|---|---|---|
| Gateways (Verzeichnis) | Menü «Window» ▸ Gateways, ⇧⌘G | Kein Knopf im Hauptfenster |
| Verbindungshistorie | Spalte «Zuletzt» und Tooltip im Gateway-Verzeichnis, eine Zeile im Verbindungsdialog | Keine eigene Ansicht; Chris hat sie am 2026-11-12 nicht gefunden |
| Sitzungsprotokoll | Knopf «Protokoll» in der Statusleiste, nur während/nach einer Sitzung | Ältere Protokolle liegen nur als Dateien im Container |
| Funkgerät verbinden/trennen | Einstellungen ▸ Funkgerät | Im Hauptfenster nur Anzeige in der Leiste «Pegel / Tune» |
| Pegel-Assistent | Einstellungen ▸ Modem ▸ «Pegel-Assistent …» | Werkzeug, keine Einstellung |
| Funk-Transporte, P2P | Aufklappmenü am Knopf «Abrufen & Senden» | Kein Menü «Funk» in der Menüleiste |
| Abfragen, GRIB-Assistent, gespeicherte Abfragen | Aufklappmenü am Symbol «Abfragen»; Verwaltung in Einstellungen ▸ Abfragen | Zwei Orte |
| Ordner anlegen, umbenennen, löschen; Papierkorb leeren | Nur Rechtsklick in der Seitenleiste | Kein Menü, kein Knopf |
| Versandweg, Verschieben, Entwurf bearbeiten | Rechtsklick in der Liste, Symbole über der Nachricht | Kein Menü «Nachricht» |
| Kontakte, Positionsmeldung | Symbole ohne Beschriftung, eigene Fenster | Symbole nicht selbsterklärend |
| Signaturen | Einstellungen ▸ Signaturen | (in Ordnung, bleibt Einstellung) |

Dazu kommt:
- Die Symbolleiste zeigt nur Symbole (Neue Nachricht, Kontakte, Position, Abfragen, Abrufen &
  Senden), Beschriftung nur als Tooltip.
- Die Menüleiste hat keine eigenen Menüs für Postfach, Nachricht und Funk. Das Fenster-Menü
  führt Kontakte, Gateways und Positionsmeldung doppelt (einmal von SwiftUI für die
  `Window`-Szenen, einmal aus `CommandGroup(before: .windowList)`), GRIB-Wetterdaten nur
  einmal ohne Kürzel.
- Systemmenüs erscheinen englisch («Minimize», «Zoom», «Bring All to Front»), die App ist
  sonst deutsch — das Projekt nennt keine deutsche Entwicklungssprache.
- Farbe kommt nur vereinzelt vor (Pegel-Assistent, «SENDET», Statuspunkte); es gibt keine
  Akzentfarbe im Asset-Katalog und keine zentrale Definition.
- Das Hauptfenster ist ein dreispaltiges Mail-Fenster (Ordner · Liste · Nachricht). Rechts
  bleibt viel Fläche leer, solange keine Nachricht gewählt ist; Funk-Werkzeuge leben in
  eigenen Fenstern und Dialogen.

## Nicht-Ziele
- Keine neuen Funkfunktionen, keine Änderung an B2F, Modem- oder PTT-Wegen.
- Keine Änderung am Datenmodell (Postfach, Kontakte, Historie, Einstellungsdatei) — nur neue
  Sichten auf vorhandene Daten.
- Die CAT-Einstellungen selbst (Wege, Vorgabe für neue Einrichtungen) bleiben wie sie sind;
  Chris überdenkt sie getrennt (CAT-Konzept 2026-11, Offene Fragen).
- Keine englische Übersetzung, kein iOS/iPadOS.
- Kein Umbau anderer Apps.

## Konzept

### 1. Navigation: Bereiche in der Seitenleiste
Die Seitenleiste führt nicht mehr nur Ordner, sondern die Bereiche der App. Ein Klick zeigt
den Bereich im Hauptfenster; Kontakte und Position brauchen kein eigenes Fenster mehr, das
Gateway-Verzeichnis lässt sich zusätzlich als Fenster öffnen.

    POSTFACH                 FUNK                     WERKZEUGE
      Posteingang              Gateways                 Kontakte
        (Unterordner)          Verbindungen             Positionsmeldung
      Entwürfe                 Protokolle               Abfragen
      Postausgang              Funkgerät
      Gesendet
      Papierkorb

- **Verbindungen** ist neu: die Verbindungshistorie als Liste (Zeit in UTC, Gegenstelle,
  Weg, Band/Frequenz, Ergebnis, Datenrate, Fehlertext), filterbar nach Weg und Ergebnis.
- **Protokolle** ist neu: die gespeicherten Sitzungsprotokolle (`SessionLogStore`) als Liste
  mit Vorschau, «Kopieren» und «Im Finder zeigen».
- **Funkgerät** zeigt Status, Frequenz und Modus gross, mit «Verbinden/Trennen», Tune,
  Pegel-Regler und dem Pegel-Assistenten; ein Knopf führt in die Einstellungen.
- **Abfragen** vereint Katalog-Vorlagen, GRIB-Assistent und gespeicherte Abfragen samt ihrer
  Verwaltung (heute in den Einstellungen).

### 2. Symbolleiste: beschriftet
Symbol **und** Text, in dieser Reihenfolge: «Abrufen & Senden» (mit Aufklappmenü für den
Weg) · «Neue Nachricht» · «Antworten» · «Weiterleiten» · «Verschieben» · «Löschen» · Suche.
Im Funk- und Werkzeug-Bereich zeigt die Leiste die Aktionen des jeweiligen Bereichs
(z. B. Gateways: «Verbinden», «Aktualisieren», «Nur Favoriten»).

### 3. Menüleiste: vollständig
Jede Funktion steht auch in der Menüleiste, mit Kürzel wo sinnvoll:

| Menü | Inhalt |
|---|---|
| Skywave | Über, Nach Updates suchen, Einstellungen |
| Ablage | Neue Nachricht, Neuer Ordner, Ordner umbenennen/löschen, Papierkorb leeren |
| Nachricht | Antworten, Allen antworten, Weiterleiten, Entwurf bearbeiten, Versandweg ▸, Verschieben nach ▸, Löschen |
| Funk | Abrufen & Senden über Internet / VARA HF / VARA FM / ARDOP, Direktverbindung (P2P), Sitzung abbrechen, Funkgerät verbinden/trennen, Tune, Pegel-Assistent |
| Darstellung | die Bereiche der Seitenleiste (Posteingang … Abfragen) mit ⌘1–⌘9, Protokoll der laufenden Sitzung |
| Fenster | Systemeinträge, ohne die doppelten Zeilen |

Systemmenüs erscheinen deutsch (Entwicklungssprache `de`).

### 4. Funk-Leiste unten
Die Leiste am unteren Rand bleibt immer sichtbar (heute nur bei Bedarf): links Funkgerät
(Statuspunkt, Name, Frequenz, Modus), Mitte Sitzungsstatus mit Weg und Fortschritt, rechts
«SENDET», Pegel und «Protokoll». Ein Klick auf den Geräteteil öffnet den Bereich «Funkgerät».

### 5. Farben
Eine Akzentfarbe für Auswahl und Hauptknöpfe, farbige Symbole je Bereich in der Seitenleiste
(wie Mail/Finder), dazu feste Statusfarben mit genau einer Bedeutung:

| Farbe | Bedeutung |
|---|---|
| Rot | Sender getastet («SENDET»), Fehler |
| Grün | verbunden, erfolgreich |
| Orange | Warnung, Abbruch, Versuch ohne Erfolg |
| Grau | getrennt, inaktiv |
| Gelb | in Arbeit: verbindet gerade (Etappe 5 ergänzt) |

Alle Farben liegen als benannte Farben im Asset-Katalog (hell und dunkel) und werden über
eine Stelle im Code angesprochen (`Theme.swift`), nicht mehr als verstreute `.red`/`.green`.
Status wird nie nur über Farbe gezeigt, immer mit Symbol oder Text.

### 6. Leere Flächen
Ist keine Nachricht gewählt, zeigt die rechte Spalte statt «Keine Nachricht ausgewählt»
eine Übersicht: letzter Abruf, wartende Nachrichten im Postausgang nach Versandweg,
Funkgerät-Status, die letzten drei Verbindungen, Knöpfe für die häufigsten Schritte.

## Betroffene Stellen
- `Skywave/SkywaveApp.swift` – Menüleiste (`CommandMenu`), Fenster-Szenen, doppelte
  Fenster-Einträge entfernen
- `Skywave/Mail/MailboxView.swift` – Seitenleiste mit Bereichen, Symbolleiste, Funk-Leiste,
  Übersicht in der leeren Detailspalte; die Datei wird dabei aufgeteilt
- `Skywave/Mail/GatewayDirectoryView.swift`, `Skywave/Contacts/ContactsView.swift`,
  `Skywave/Position/PositionReportView.swift`, `Skywave/Mail/GRIBAssistantView.swift` – als
  Bereich im Hauptfenster einbettbar machen
- `Skywave/Mail/MessageListView.swift`, `MessageDetailView.swift` – Aktionen als gemeinsame
  Befehle, damit Menü, Symbolleiste und Kontextmenü dasselbe auslösen
- `Skywave/Settings/SettingsView.swift` – Abfragen-Verwaltung und Pegel-Assistent ziehen um
- `Skywave/Radio/RigStatusLine.swift`, `RigSettingsTab.swift` – Bereich «Funkgerät» nutzt
  dieselben Bausteine
- neu: `Skywave/Navigation/AppSection.swift`, `Skywave/Mail/ConnectionHistoryView.swift`,
  `Skywave/Mail/SessionLogView.swift`, `Skywave/Radio/RigPanelView.swift`,
  `Skywave/Support/Theme.swift`, `Skywave/Mail/OverviewView.swift`
- `Skywave/Assets.xcassets` – Akzentfarbe und benannte Farben
- `project.yml` – Entwicklungssprache `de`
- `Tests/` – Tests für Bereichs-Navigation, Historien-Filter, Protokoll-Liste und dafür,
  welche Befehle wann aktiv sind

## Entscheidungen
| Frage | Entscheidung | Warum |
|---|---|---|
| Umfang | Nur Oberfläche: Navigation, Menüs, Beschriftung, Farben, neue Sichten auf vorhandene Daten | Chris, 2026-11-12: erst die Oberfläche auf einen neuen Stand, dann einmal durchtesten |
| «Neue Nachricht» | Bleibt ein eigenes Fenster | Mehrere Entwürfe nebeneinander, Antworten neben der Originalnachricht; so arbeitet auch Mail |
| Einstellungen | Bleiben ein eigenes Fenster (⌘,); Werkzeuge ziehen ins Hauptfenster um | macOS-Konvention; Einstellungen sind, was man einmal einrichtet |
| Systemmenüs | Deutsch, Entwicklungssprache `de` | Die App ist deutsch, englische Systemzeilen wirken wie ein Fehler |
| Doppelte Fenster-Einträge | Entfallen | Entstehen aus `Window`-Szenen plus eigener Befehlsgruppe |
| Zeiten in Verbindungen und Protokollen | UTC, so beschriftet | Funkbezogene Zeiten immer UTC |
| Farbdefinition | Benannte Farben im Asset-Katalog, eine Stelle im Code | Hell/Dunkel ohne Sonderfälle, später leicht änderbar |
| Status nie nur über Farbe | Immer Symbol oder Text dazu | Lesbar bei Farbfehlsichtigkeit und in der Sonne |
| Navigation | Bereiche in der Seitenleiste eines Fensters (Postfach · Funk · Werkzeuge) | Chris, 2026-11-12: alles soll in der App sichtbar und anwählbar sein, der Platz ist da |
| Symbolleiste | Symbol und Text, fest (nicht anpassbar) | Chris, 2026-11-12; Beschriftung kann nicht versehentlich verschwinden, weniger Zustände zu testen |
| Akzentfarbe | Petrol `#0B6E7A` (hell; die dunkle Variante wird in Etappe 5 auf Kontrast geprüft) | Chris, 2026-11-12 anhand des Entwurfs; beisst sich nicht mit den Statusfarben |
| Neue Bereiche | «Verbindungen» und «Protokolle» kommen in diesem Umbau mit | Chris, 2026-11-12: ein Durchtest statt zwei; die Historie war nicht auffindbar |
| Leere Detailspalte | Übersicht (letzter Abruf, Postausgang nach Weg, Funkgerät, letzte Verbindungen), als letzte Etappe | Chris, 2026-11-12 |
| Eigene Fenster | Nur Gateways zusätzlich als Fenster («In eigenem Fenster öffnen»); Kontakte und Position nur noch als Bereich | Chris, 2026-11-12: Gateways neben dem Postfach ist beim Verbinden nützlich |
| Funk-Leiste | Steht als eigene Zeile unter dem ganzen Fenster, nicht als `safeAreaInset` | Die Detailspalte hielt den Einzug nicht ein, Knöpfe am unteren Rand der Bereiche lagen darunter (Etappe 1, am Bildschirmabzug gesehen) |
| Kontakte im Hauptfenster | Filter (Alle, Favoriten, Gruppen) als Auswahl über der Liste statt einer eigenen Spalte | Eine dritte Spalte neben der Seitenleiste wäre zu eng (Etappe 1) |
| Bereich nach Abschluss | Positionsmeldung wechselt nach «In Postausgang legen» in den Postausgang, Gateways nach dem Verbinden in den Posteingang; der GRIB-Assistent bleibt stehen | Früher schloss sich das jeweilige Fenster; im Hauptfenster gibt es nichts zu schliessen (Etappe 1) |
| Menüleiste ↔ Fenster | Menüs schicken Anforderungen über `MailboxCommandCenter` ans Hauptfenster; das Fenster meldet die gewählte Nachricht zurück | Dialoge (Ordner, Funk, Rückfragen) gehören dem Fenster; ein gemeinsames Objekt ist einfacher zu testen als fokussierte Werte (Etappe 2) |
| Symbolleiste im Postfach | Feste Reihe: Antworten, Weiterleiten, Verschieben, Löschen — «Allen antworten» und «Als gelesen markieren» stehen im Menü «Nachricht» und im Kontextmenü | Mit Beschriftung passen nicht mehr alle Knöpfe; die Reihe springt nicht mehr, wenn eine Nachricht gewählt wird (Etappe 2) |
| Löschen aus dem Papierkorb | Fragt immer nach, auch über das Kontextmenü der Liste | Lief dort bisher ohne Rückfrage; jetzt geht alles über dieselbe Stelle (Etappe 2) |
| Kürzel | Neu: ⇧⌘N Neuer Ordner, ⇧⌘U gelesen/ungelesen, ⌘⌫ Löschen, ⌘. Sitzung abbrechen, ⇧⌘L Protokoll, ⇧⌘A Abfragen, ⌘1–⌘5 Ordner | Bisherige Kürzel bleiben (⌘N, ⌘R, ⌥⌘R, ⇧⌘F, ⌘O, ⇧⌘R, ⇧⌘G, ⇧⌘K, ⇧⌘P) |
| Zeiten in Protokollen | Neue Protokolle schreiben ihre Zeilen in UTC und sagen das in der Kopfzeile; der Dateiname bleibt in Ortszeit, die Liste zeigt den Beginn in UTC | Ältere Protokolle tragen Ortszeit in den Zeilen und lassen sich nicht nachträglich umstellen; mit Ortszeit im Dateinamen bleiben alte und neue Dateien gleich lesbar (Etappe 4) |
| P2P in «Verbindungen» | Kein eigener Filter | Die Historie speichert nur den Weg (ARDOP, VARA), nicht ob Gateway oder Gegenstation; das Datenmodell bleibt in diesem Umbau unverändert (Etappe 4) |
| «Protokoll anzeigen» aus einer Verbindung | Führt in den Bereich «Protokolle», nicht zum einzelnen Protokoll | Historie und Protokolldateien sind nicht verknüpft; eine Zuordnung über die Zeit wäre geraten (Etappe 4) |

## Offene Fragen
Keine — alle sechs Fragen vom 2026-11-12 sind beantwortet und stehen in der
Entscheidungstabelle.

## Etappen
1. **Gerüst:** `AppSection`, Seitenleiste mit Bereichen, bestehende Ansichten eingebettet;
   Fenster-Menü bereinigt, Entwicklungssprache `de`.
2. **Befehle:** Menüleiste vollständig, Symbolleiste beschriftet, Aktionen an einer Stelle.
3. **Funk:** Bereich «Funkgerät», Funk-Leiste immer sichtbar, Pegel-Assistent zieht um.
4. **Neue Sichten:** «Verbindungen», «Protokolle», Abfragen-Verwaltung im Bereich «Abfragen».
5. **Farben:** Asset-Farben, `Theme`, farbige Bereichssymbole, Statusfarben vereinheitlicht.
6. **Übersicht** in der leeren Detailspalte.
7. **Abnahme:** Durchtest nach Checkliste (entsteht aus den Abnahmekriterien), Codex-Review,
   Merge-OK.

Jede Etappe ist für sich lauffähig und wird einzeln committet; `main` bleibt unberührt, bis
Chris das Merge-OK gibt.

## Stand der Etappen
- [x] **Etappe 1 (2026-11-12):** `AppSection`/`AppNavigation`, Seitenleiste mit den Gruppen
  Postfach, Funk (Gateways) und Werkzeuge (Kontakte, Positionsmeldung, Abfragen); die vier
  Ansichten sind eingebettet, das Gateway-Verzeichnis zusätzlich als Fenster. Menü
  «Darstellung» wechselt die Bereiche (⌘1, ⇧⌘G, ⇧⌘K, ⇧⌘P, ⇧⌘A), Fenster-Menü ohne
  Doppel, Systemmenüs deutsch. In der laufenden App an allen fünf Bereichen angesehen
  (Bildschirmabzüge), nicht durchgeklickt. Suite 141 grün.
- [x] **Etappe 2 (2026-11-12):** Menüleiste vollständig — Ablage (Ordner anlegen, umbenennen,
  löschen, Papierkorb leeren), Nachricht, Funk, Darstellung (alle Bereiche, ⌘1–⌘5 für die
  Ordner). Symbolleiste fest mit Symbol und Text: Abrufen & Senden, Neue Nachricht, im
  Postfach Antworten, Weiterleiten, Verschieben, Löschen (im Postausgang zusätzlich
  Versandweg). Menü, Symbolleiste und Kontextmenü lösen dasselbe aus
  (`MailboxCommandCenter`, `MessageCommandState`). Menüleiste der laufenden App ausgelesen,
  Symbolleiste am Bildschirmabzug geprüft; kein Befehl ausgelöst. Suite 147 grün.
- [x] **Etappe 3 (2026-11-12):** Bereich «Funkgerät» (Status, Frequenz und Modus gross,
  Verbinden/Trennen, Sendepegel, Tune, Pegel-Assistent, Weg zum Gerät). Die Funk-Leiste ist
  immer sichtbar und führt per Klick auf das Gerät in den Bereich. Menü «Funk» um Funkgerät
  verbinden/trennen, Tune (⌥⌘T) und Pegel-Assistent erweitert; der Assistent ist aus den
  Einstellungen ins Hauptfenster gezogen. Am Bildschirmabzug mit verbundenem IC-7300
  angesehen; weder Tune noch Assistent ausgelöst. Suite 148 grün.
- [x] **Etappe 4 (2026-11-12):** Bereich «Verbindungen» (Historie als Tabelle mit UTC-Zeit,
  Weg, Kanal, Ergebnis mit Symbol und Fehlertext, Nachrichten, Dauer, Rate; Filter nach Weg,
  Ergebnis und Rufzeichen; «Erneut verbinden …»). Bereich «Protokolle» (gespeicherte
  Sitzungsprotokolle, neueste zuerst, Vorschau, Kopieren, Im Finder zeigen). Die Verwaltung
  der gespeicherten Abfragen ist aus den Einstellungen in den Bereich «Abfragen» gezogen.
  Beide neuen Bereiche mit den echten Daten am Bildschirmabzug angesehen (4 Verbindungen,
  32 Protokolle). Suite 152 grün.
- [x] **Etappe 5 (2026-11-12):** Akzentfarbe Petrol und acht weitere benannte Farben im
  Asset-Katalog (hell und dunkel), eine Stelle im Code (`Support/Theme.swift`). Alle
  Farbliterale für Status sind ersetzt (per Suche geprüft: keine `.red/.green/.orange/.yellow`
  mehr ausserhalb von `Theme.swift`). Symbole der Seitenleiste in der Farbe ihrer Gruppe:
  Postfach blau, Funk petrol, Werkzeuge violett. Dunkel und hell am Bildschirmabzug
  angesehen (hell über ein Startargument erzwungen). Suite 152 grün.
- [x] **Etappe 6 (2026-11-12):** Übersicht in der rechten Spalte des Postfachs, solange keine
  Nachricht gewählt ist: Posteingang (ungelesen), Postausgang nach Versandweg, letzter
  Austausch (UTC), Funkgerät, die letzten drei Verbindungen und die drei häufigsten Schritte.
  Der Seitenleisten-Knopf lag im Überlauf der Symbolleiste und steht jetzt unter
  «Darstellung» (⌃⌘S). Am Bildschirmabzug mit echten Daten angesehen. Suite 153 grün.
- [ ] **Etappe 7 (Abnahme):** Codex-Review am 2026-11-12: zwei Befunde, beide behoben
  (Menübefehl bei geschlossenem Hauptfenster ging verloren; gewähltes Protokoll blieb nach
  Sitzungsende unvollständig). Merge-OK von Chris am 2026-11-12, **vor** dem Durchtest —
  `main` enthält den Umbau, die Checkliste unten ist noch offen und gehört vor das nächste
  Release.

## Durchtest (Chris)
Mit dem Debug-Build vom Branch. Sendetests nur in die Kunstlast oder mit Leistung auf 0.

**Fenster und Menüs**
- [ ] Seitenleiste zeigt Postfach, Funk (Gateways, Verbindungen, Protokolle, Funkgerät) und
  Werkzeuge (Kontakte, Positionsmeldung, Abfragen); jeder Eintrag öffnet seinen Bereich
- [ ] Menü «Darstellung»: jeder Bereich per Menü und Kürzel (⌘1–⌘5, ⇧⌘G/H/J/T/K/P/A),
  Seitenleiste ein-/ausblenden (⌃⌘S)
- [ ] Menü «Fenster» ohne doppelte Einträge; Systemmenüs deutsch
- [ ] Symbolleiste überall mit Beschriftung, hell und dunkel lesbar

**Postfach**
- [ ] Nachricht wählen: Antworten, Weiterleiten, Verschieben, Löschen über Symbolleiste
  **und** Menü «Nachricht»; ohne Auswahl sind sie grau
- [ ] Allen antworten (⌥⌘R), Als gelesen/ungelesen markieren (⇧⌘U), Entwurf bearbeiten (⌘O)
- [ ] Postausgang: Versandweg über Symbolleiste, Menü und Rechtsklick
- [ ] Löschen: in den Papierkorb ohne Rückfrage, aus dem Papierkorb mit Rückfrage — auch per
  Rechtsklick
- [ ] Ablage: Neuer Ordner (⇧⌘N), Ordner umbenennen, Ordner löschen, Papierkorb leeren
- [ ] Übersicht erscheint ohne gewählte Nachricht; ihre Knöpfe führen an den richtigen Ort
- [ ] Suche findet Nachrichten in allen Ordnern

**Funk**
- [ ] Abrufen & Senden über Internet: Knopf, Menü «Funk» und ⇧⌘R
- [ ] Über ARDOP: Dialog aus Symbolleiste und Menü; Sitzung starten, Stop/Abbrechen (⌘.)
- [ ] Direktverbindung (P2P): Dialog öffnet sich
- [ ] Gateways: Doppelklick verbindet; nach dem Verbinden wechselt die App in den
  Posteingang; «In eigenem Fenster öffnen» geht
- [ ] Verbindungen: die Sitzung von eben steht zuoberst mit UTC-Zeit; Filter nach Weg und
  Ergebnis; «Erneut verbinden …»
- [ ] Protokolle: das Protokoll von eben steht zuoberst, Zeilen in UTC; Kopieren, Im Finder
  zeigen
- [ ] Funkgerät: Trennen und Verbinden; Tune (auch ⌥⌘T) tastet und enttastet;
  Pegel-Assistent öffnet sich und läuft durch
- [ ] Funk-Leiste: Klick auf das Gerät öffnet «Funkgerät»; Pegel, Tune, Protokoll (⇧⌘L)
- [ ] ⌘Q in einer Sendephase: Gerät geht auf RX

**Werkzeuge**
- [ ] Kontakte: anlegen, ändern, löschen; Filter Alle/Favoriten/Gruppe; Suche
- [ ] Positionsmeldung: «In Postausgang legen» wechselt in den Postausgang, Meldung liegt dort
- [ ] Abfragen: Katalog-Vorlage und GRIB-Assistent öffnen «Neue Nachricht»; gespeicherte
  Abfrage anlegen, ändern, löschen
- [ ] Einstellungen: Tabs Allgemein, Funkgerät, Modem, Signaturen — ohne «Abfragen» und ohne
  Pegel-Assistent, beides jetzt im Hauptfenster

## Abnahmekriterien
- [ ] Jede Funktion aus der Tabelle «Ausgangslage» ist über die Seitenleiste oder einen
  beschrifteten Knopf **und** über die Menüleiste erreichbar (Checkliste im Durchtest)
- [x] Die Symbolleiste zeigt zu jedem Symbol eine Beschriftung (Bildschirmabzug, Etappe 2)
- [x] Das Fenster-Menü führt keinen Eintrag doppelt; Systemmenüs sind deutsch (Menüleiste
  der laufenden App ausgelesen, Etappe 2)
- [x] «Verbindungen» listet die Einträge der Historie mit UTC-Zeit und filtert nach Weg und
  Ergebnis (Test für den Filter)
- [x] «Protokolle» listet die gespeicherten Sitzungsprotokolle, neuestes zuerst (Test)
- [ ] Funkgerät lässt sich im Hauptfenster verbinden und trennen; Tune und Pegel-Assistent
  sind von dort erreichbar
- [x] Menübefehle sind nur aktiv, wenn sie etwas tun können (z. B. «Antworten» nur mit
  gewählter Nachricht, «Sitzung abbrechen» nur während einer Sitzung) — Test
- [x] Keine verstreuten Farbliterale mehr für Status; hell und dunkel geprüft (Etappe 5)
- [x] Bestehende Tests grün, Build auf dem DEV-Mac erfolgreich (153 Tests, 2026-11-12)
- [x] Einstellungsdatei, Postfach, Kontakte und Historie aus 0.7.0 werden unverändert gelesen
  (in der laufenden App gesehen: Gerät verbunden, 1 Nachricht, 2 Kontakte, 4 Verbindungen)

## Risiken / Backup
- Keine QSO-Daten betroffen. Postfach, Kontakte und Historie werden nur gelesen wie bisher;
  trotzdem vor dem ersten Start des Umbaus eine Kopie des Datenordners ablegen, weil
  Verschieben und Löschen von Nachrichten über neue Befehlswege laufen.
- Der Umbau fasst Stellen an, über die gesendet wird (Abrufen & Senden, Tune). Die PTT-Wege
  bleiben unverändert, aber nach Etappe 2 und 3 je ein kurzer Sendetest am Gerät: Sitzung
  starten, Stop, ⌘Q in der Sendephase.
- `MailboxView.swift` (591 Zeilen) wird aufgeteilt — grösster Einzelumbau, deshalb zuerst
  das Gerüst ohne Funktionsänderung.
- Sendetests brauchen einen Rechner mit Funkgerät (der IC-7300 hängt derzeit am DEV-Mac).
