# Feature: Skywave-Repo öffentlich stellen

Stand: 2026-11-13 · Projekt: Skywave · Status: umgesetzt, das Repo ist seit 2026-11-13 öffentlich

## Ziel
Der Quellcode von Skywave ist öffentlich auf GitHub, unter der bestehenden MIT-Lizenz. Jeder
kann ihn lesen, bauen und weiterverwenden. Das öffentliche Repo ist danach das Arbeitsrepo.
Nichts Privates wird dabei mitveröffentlicht: keine alte Historie, keine Interna der privaten
App HAM-Tools, keine persönlichen Pfade.

## Nicht-Ziele
- Lizenzwechsel. MIT bleibt.
- HAM-Tools öffentlich stellen oder dort etwas ändern, ausser die beiden Portierungslisten
  aufzunehmen.
- Den Winlink-Web-Service-Key stärker schützen als heute.
- Beitragsrichtlinien, Issue-Vorlagen, CI. Kann später folgen.
- Eine neue Skywave-Version. Der Quellstand entspricht 0.8.0 plus Aufräumarbeit.

## Ausgangslage (Stand `main`, df1c465)
- Das Repo `Skywave` ist privat, 165 Commits. `WinlinkKit` und `Skywave-releases` sind
  öffentlich.
- Prüfung vom 2026-11-13: keine Passwörter, Keys oder Tokens in der Historie (Mustersuche
  über alle Branches), keine echten Mails oder fremden Adressen.
- Privat oder intern im aktuellen Stand: `PORT-HAMTOOLS.md`, `BACKPORT-HAMTOOLS.md`,
  `docs/archiv/`, `scripts/backup-to-drive.sh` (Drive-Pfad mit Mailadresse), ein privater
  Artifact-Link im UI-Plan, der lokale Pfad `~/Developer/ardopcf` im README.
- HAM-Tools wird in 25 Commit-Nachrichten, fünf Dokumenten und einigen Code-Kommentaren
  genannt. Drei Teile sind aus HAM-Tools portiert: Pegel-Assistent, Geräteprofile, das
  rigctld-Binary.
- Der macOS-Port von ardopcf liegt nur lokal (Branch `macos-port`, fünf Commits vor
  Upstream); auch dort gibt es ein Backup-Skript mit dem Drive-Pfad.

## Betroffene Stellen
- `PORT-HAMTOOLS.md`, `BACKPORT-HAMTOOLS.md` – ziehen ins HAM-Tools-Repo um, hier entfernt.
- `docs/archiv/`, `scripts/backup-to-drive.sh` – entfernt, bleiben im privaten Archiv.
- `docs/ROADMAP.md`, `docs/plans/*.md` – Verweise auf HAM-Tools-Pfade, -Branches und
  -Commits sowie der private Artifact-Link raus; Entscheide und Verlauf bleiben.
- `Skywave/Mail/LevelTuningController.swift`, `LevelTuningSheet.swift`,
  `Skywave/Radio/RigProfile.swift`, `Tests/LevelTuningControllerTests.swift` –
  Herkunftskommentare neutral fassen.
- `Skywave/Vendor/hamlib/` – neue Datei mit Quellstand (Hamlib 4.7.1, `d042479`), Link zum
  Quellcode und dem Bauskript; `HAMLIB-VERSION` ohne Verweis auf HAM-Tools.
- `README.md` – Link auf den öffentlichen ardopcf-Fork statt des lokalen Pfads, Abschnitt
  «Building» mit Hinweis auf Team-ID und Signatur, Quellhinweis für rigctld.
- `.gitignore` – `reviews/` aufnehmen (heute nur lokal ausgeschlossen).
- ardopcf-Fork – Backup-Skript entfernen, als öffentliches Repo anlegen.

## Entscheidungen
| Frage | Entscheidung | Warum |
|---|---|---|
| Lizenz | MIT bleibt | Chris, 2026-11-13: eine kommerzielle Übernahme stört ihn nicht («Ham Spirit»); WinlinkKit ist bereits MIT, die veröffentlichten Versionen nennen MIT. |
| Winlink-Web-Service-Key | Bleibt wie heute verschleiert | Chris, 2026-11-13. Die Maske war nie ein Schutz (steht im README); der Client drosselt die Abfragen selbst. |
| Historie | Neustart ohne Historie | Chris, 2026-11-13: HAM-Tools ist «heilig». Alte Commits nennen dessen Pfade, Branches und Commits. |
| Technik des Neustarts | Das heutige Repo wird in `Skywave-archiv` umbenannt und bleibt privat; ein neues Repo `Skywave` entsteht mit einem ersten Commit aus dem bereinigten Stand | Ein Überschreiben per Force-Push im selben Repo wäre nicht sicher: GitHub hält alte Commits über ihre Kennung erreichbar. Das alte Repo wird deshalb nie öffentlich. |
| Portierter Code | Bleibt drin und wird öffentlich | Chris, 2026-11-13. Ohne Pegel-Assistent und Geräteprofile läuft Skywave nicht. |
| Arbeitsweise | Offen entwickeln: das öffentliche Repo ist das Arbeitsrepo, ROADMAP und Pläne sind öffentlich | Chris, 2026-11-13. Ein Repo, kein Abgleich. Künftige Pläne nennen keine HAM-Tools-Interna. |
| Portierungslisten | Ziehen ins HAM-Tools-Repo | Sie beschreiben Arbeit an HAM-Tools und gehören dorthin. |
| Mitgelieferte Programme | Quellen offenlegen: ardopcf-Fork öffentlich, für rigctld Quellstand und Bauskript im Repo | Chris, 2026-11-13. Erfüllt die GPL für rigctld sauber, und jeder kann Skywave nachbauen. |
| Autor der Commits | GitHub-Noreply-Adresse, nur für dieses Repo eingestellt | Chris, 2026-11-13. Die private Mailadresse steht nirgends im öffentlichen Repo. |
| Name des ardopcf-Repos | `ardopcf-macos`, eigenständiges Repo mit Upstream-Historie | Chris, 2026-11-13. Nicht mit dem Original zu verwechseln. |
| Issues | Eingeschaltet | Chris, 2026-11-13. Rückmeldungen von OMs an einem Ort; abschalten geht jederzeit. |
| Plan «CAT-Konzept» | Kommt nicht ins öffentliche Repo, bleibt im Archiv | Er beschreibt den Aufbau von HAM-Tools im Detail (Pfade, Klassen, Umfang); bereinigt bliebe kaum etwas Lesbares übrig. Die offenen Punkte daraus stehen in der Roadmap. |
| Sparkle-Updates | Unverändert | Der Feed liegt in `Skywave-releases`, nicht in diesem Repo. |
| Lokales Arbeitsverzeichnis | Bleibt `~/Developer/Skywave`; die heutige Kopie wandert nach `~/Developer/_backups/` | Skripte, Xcode und die Notizen von Claude Code hängen am Pfad. |

## Offene Fragen
- (keine)

## Etappen
1. **Aufräumen** auf diesem Branch: Dateien entfernen, Dokumente und Kommentare bereinigen,
   Quellhinweise und README. Suite grün, Codex-Review, Merge nach `main` im heutigen Repo.
   **Erledigt 2026-11-13:** Codex-Review ohne Befunde, 165 Tests grün.
2. **Portierungslisten** ins HAM-Tools-Repo legen (eigener Commit dort, mit Chris' OK).
   **Erledigt 2026-11-13** (dort lokal committet, Push durch Chris).
3. **ardopcf-Fork** bereinigen und als öffentliches Repo anlegen. **Erledigt 2026-11-13:**
   https://github.com/christianmueller1970-oss/ardopcf-macos, Branch `macos-port` bis `d57299c`
   (der Stand des mitgelieferten Modems); der spätere Commit mit dem Backup-Skript ist nicht
   dabei.
4. **Neustart:** bereinigten Stand in ein leeres Verzeichnis kopieren, ein Commit, Prüfung
   (siehe Risiken), altes Repo umbenennen, neues privates Repo `Skywave` anlegen und pushen.
   **Erledigt 2026-11-13:** erster Commit `95376f6`, Prüfungen ohne Befund, lokales
   Arbeitsverzeichnis umgehängt.
5. **Öffentlich stellen:** letzte Sichtprüfung auf GitHub, dann Sichtbarkeit umstellen
   (Chris). **Erledigt 2026-11-13** durch Chris.
6. **Nachziehen:** lokales Verzeichnis umhängen, Memorys und Handover-Notizen korrigieren,
   README-Link in `Skywave-releases` prüfen. **Erledigt 2026-11-13:** Verzeichnis
   umgehängt, Notizen korrigiert. `Skywave-releases` hat kein README, dort ist nichts zu ändern.

## Abnahmekriterien
- [x] Im neuen Repo gibt es genau einen Commit; `git log --all` zeigt keine alten Commits. Beim Anlegen geprüft (2026-11-13).
- [x] Suche im neuen Stand nach `HAMRechner`, `PORT-HAMTOOLS`, `gmail`, `/Users/chris`,
  `claude.ai/artifact` und `~/Developer` liefert nichts. Bekannte Ausnahme: das ardopcf-Binary
  enthält die Bauverzeichnisse `/Users/chris/Developer/ardopcf/…` als Debug-Angaben. Es steckt
  so bereits in den veröffentlichten Versionen und bleibt unverändert, weil es das on air
  geprüfte Modem ist. Zweite Ausnahme: dieser Plan nennt die entfernten Dateien beim Namen.
- [x] Mustersuche nach Passwörtern, Keys und Tokens im neuen Stand liefert nichts.
- [x] Ein frischer Klon des neuen Repos baut ohne Winlink-Key mit `xcodegen generate` und
  `xcodebuild build` (WinlinkKit als Nachbarverzeichnis), Suite grün. Geprüft am Stand des ersten
  Commits vor dem Push (165 Tests), nicht an einem Klon von GitHub.
- [x] README nennt für ardopcf und rigctld je einen öffentlichen Quellort; beide Links
  antworten. Von aussen geprüft (2026-11-13), ebenso ein anonymer Klon.
- [x] Das alte Repo heisst `Skywave-archiv` und ist privat.
- [x] Sparkle-Feed und Download von 0.8.0 antworten wie vorher.

## Risiken / Backup
- **Nicht rückholbar:** Was einmal öffentlich war, kann geklont worden sein. Deshalb bleibt das
  neue Repo zuerst privat; öffentlich wird es erst nach der Sichtprüfung auf GitHub.
- **Historie geht öffentlich verloren:** Sie bleibt in `Skywave-archiv` und in der lokalen
  Kopie unter `~/Developer/_backups/`. Vor dem Umbenennen zusätzlich ein Bundle
  (`git bundle create`) als Sicherung.
- **Umbenennen auf GitHub:** Alte Links auf das private Repo zeigen danach ins Archiv bzw. auf
  das neue Repo. Betroffen sind nur eigene Lesezeichen und Klone.
- **Unterwegs:** Umbenennen, Anlegen und Sichtbarkeit nur über eine stabile Verbindung.
- Kein Bezug zu QSO-Daten, Postfach oder Shack-Hardware.
