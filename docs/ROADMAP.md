# Roadmap Skywave

Zuletzt aufgeräumt: 2026-11-13

## Jetzt
- (nichts offen)

## Als Nächstes
- [ ] ⌘Q beim Tune am Gerät prüfen; QSY über fremden rigctld am Gerät prüfen – Quelle:
  CAT-Konzept 2026-11
- [ ] CAT-Einstellungen überdenken (Chris), samt Vorgabe für neue Einrichtungen und der
  Bestätigung für «beim Start automatisch verbinden» – Quelle: CAT-Konzept 2026-11
- [ ] On-Air-Tests der Ergänzungsrunde 2026-10, an einem Rechner mit Funkgerät (der IC-7300
  hängt derzeit am DEV-Mac): Eingang zurückstellen, Gateway-Historie über Funk. P2P gegen
  Winlink Express/Pat braucht zusätzlich eine Gegenstation – Quelle: Ergänzungsrunde 2026-10

## Später
- [ ] Katalog-Starterliste nach WL2K_HELP-Abruf – Quelle: Ergänzungsrunde 2026-10
- [ ] Formulare als eigenes Projekt – Quelle: Ergänzungsrunde 2026-10

## Ideen
- Aufseher im Kit schickt `T 0`, bevor er rigctld beendet: deckt `kill -9`/Absturz in der
  Sendephase ab. Von Chris am 2026-11-12 vorerst abgelehnt (Absturz zu unwahrscheinlich).
- «Weitere Hamlib-Modelle …» (braucht `rigctld --list` und Caps-Abfrage) und automatische
  Geräteerkennung – CAT-Konzept 2026-11
- Packet sowie Druck/ICS-309/Identitäten – am 2026-10-11 vertagt (Ergänzungsrunde 2026-10)

## Pläne
| Plan | Status | Branch |
|---|---|---|
| [Repo öffentlich](plans/2026-11-13-repo-oeffentlich.md) | umgesetzt, öffentlich seit 2026-11-13 | – |
| [Sprachwahl](plans/2026-11-13-sprachwahl.md) | gemergt 2026-11-13, mit 0.8.0 veröffentlicht | feature/sprachwahl |
| [UI-Konzept](plans/2026-11-12-ui-konzept.md) | gemergt 2026-11-12, mit 0.8.0 veröffentlicht | feature/ui-konzept |
| CAT-Konzept 2026-11 (Plan nicht im Repo) | gemergt 2026-11-12, mit 0.7.0 veröffentlicht | feature/cat-konzept |

## Kürzlich erledigt
- [x] `scripts/build-hamlib.sh` vollständig durchlaufen lassen (in einer Kopie): rigctld 4.7.1,
  `d042479`, universal, Smoke-Test grün; das mitgelieferte Binary bleibt unverändert (2026-11-13)
- [x] Repo öffentlich gestellt (MIT): Neustart ohne frühere Historie, Quellstand und Bauskript
  für rigctld, macOS-Port von ardopcf als eigenes öffentliches Repo (2026-11-13)
- [x] Update von 0.7.0 auf 0.8.0 über Sparkle an der installierten App eingespielt (Angabe
  Chris, 2026-11-13: «Update war erfolgreich»)
- [x] Skywave 0.8.0 (Build 14) veröffentlicht: notarisierter Kandidat `8890004`, GitHub-Release
  `v0.8.0` in `Skywave-releases`, Appcast-Eintrag, Notizen aus `docs/release-notes/0.8.0.md`.
  Am Kandidaten geprüft: Start, rigctld in der Sandbox, Selbst-Neustart; keine Sitzung
  (2026-11-13)
- [x] Sprachwahl Deutsch / English: Wähler in den Einstellungen mit Neustart, 716 Texte
  zweisprachig, Durchsicht Chris grün, Codex-Review ohne Befunde (2026-11-13)
- [x] Durchtest der neuen Oberfläche durch Chris am Debug-Build von `main` (`0d630a2`):
  «UI ist Top» (Angabe Chris, 2026-11-13)
- [x] Neues Hauptfenster: Bereiche in der Seitenleiste, vollständige Menüleiste, beschriftete
  Symbolleiste, Verbindungen, Protokolle, Funkgerät, Übersicht, Farben – `ee66588`
  (2026-11-12)
- [x] Update von 0.6.0 auf 0.7.0 über Sparkle sauber eingespielt (Angabe Chris, 2026-11-12)
- [x] Appcast: `pubDate` der Einträge 0.6.0 und 0.7.0 ins RFC-822-Format gebracht –
  `Skywave-releases` `7aadab4`; Skript behoben in `8b00b5c`
- [x] Skywave 0.7.0 (Build 13) veröffentlicht: GitHub-Release `v0.7.0` in `Skywave-releases`,
  Appcast-Eintrag, Notizen aus `docs/release-notes/0.7.0.md` (2026-11-12)
- [x] Signierter Kandidat 0.7.0 (Build 13): notarisiert, rigctld startet in der Sandbox und
  liest das Gerät – `f489e52` (2026-11-12)
- [x] CAT-Konzept nach `main`: Tab «Funkgerät», mitgelieferter rigctld, PTT und QSY über den
  `RigController` – `c332fb7`
- [x] ⌘Q in der Sendephase entsichert den Sender – `06df39e`, `0058f6e`
- [x] Hinweis im Tab, dass RTS mit dem integrierten ardopcf nicht tastet –
  `a385401`
- [x] WinlinkKit 0.8.0 getaggt (`ProcessSupervisor`, `RigctldProcess`)
