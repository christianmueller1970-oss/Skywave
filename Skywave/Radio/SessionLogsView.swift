import AppKit
import SwiftUI

/// Ein gespeichertes Sitzungsprotokoll auf der Platte.
struct SessionLogFile: Identifiable, Hashable, Sendable {
    let url: URL
    /// Beginn der Sitzung, aus dem Dateinamen gelesen.
    let started: Date?

    var id: URL { url }

    /// «12.11.2026 16:39:05 UTC» — oder der Dateiname, wenn er nicht
    /// dem Muster folgt.
    var title: String {
        guard let started else { return url.lastPathComponent }
        return Self.titleStamp.string(from: started) + " UTC"
    }

    private static let titleStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return f
    }()
}

extension SessionLogStore {
    /// Die gespeicherten Protokolle eines Ordners, neueste zuerst.
    static func sessions(in directory: URL = SessionLogStore.logsDirectory) -> [SessionLogFile] {
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return
            urls
            .filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("session-") }
            .map { SessionLogFile(url: $0, started: startDate(fromFileName: $0.lastPathComponent)) }
            .sorted { $0.url.lastPathComponent > $1.url.lastPathComponent }
    }

    /// Liest den Beginn aus «session-2026-11-12_17-39-05.log». Der
    /// Dateiname trägt Ortszeit.
    static func startDate(fromFileName name: String, timeZone: TimeZone = .current) -> Date? {
        guard name.hasPrefix("session-"), name.hasSuffix(".log") else { return nil }
        let stamp = String(name.dropFirst("session-".count).dropLast(".log".count))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.date(from: stamp)
    }
}

/// Bereich «Protokolle»: die gespeicherten Sitzungsprotokolle, neueste
/// zuerst, mit Vorschau.
struct SessionLogsView: View {
    @Environment(ExchangeController.self) private var exchange

    @State private var sessions = [SessionLogFile]()
    @State private var selection: SessionLogFile.ID?
    @State private var text = ""
    /// Zählt hoch, wenn der Inhalt neu gelesen werden muss, obwohl die
    /// Auswahl gleich bleibt (Sitzungsende).
    @State private var revision = 0

    private struct LoadKey: Hashable {
        let selection: SessionLogFile.ID?
        let revision: Int
    }

    private var selected: SessionLogFile? {
        sessions.first { $0.id == selection }
    }

    var body: some View {
        HSplitView {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Protokolle",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Jeder Austausch schreibt sein Protokoll mit.")
                    )
                } else {
                    List(sessions, selection: $selection) { session in
                        Text(session.title)
                            .monospacedDigit()
                            .lineLimit(1)
                            .tag(session.id)
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 340, maxHeight: .infinity)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }
                    .disabled(text.isEmpty)
                    Button {
                        if let selected {
                            NSWorkspace.shared.activateFileViewerSelecting([selected.url])
                        } else {
                            NSWorkspace.shared.open(SessionLogStore.logsDirectory)
                        }
                    } label: {
                        Label("Im Finder zeigen", systemImage: "folder")
                    }
                    Spacer()
                    Text("\(sessions.count) Protokolle")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                if selected == nil {
                    ContentUnavailableView(
                        "Kein Protokoll ausgewählt",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Wähle links eine Sitzung.")
                    )
                } else {
                    // Ein Textblock, damit sich das ganze Protokoll
                    // markieren und kopieren lässt.
                    ScrollView {
                        Text(text)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Protokolle")
        .onAppear(perform: reload)
        // Nach einer Sitzung liegt ein neues Protokoll bereit — und ein
        // schon gewähltes ist jetzt vollständig: Inhalt neu lesen.
        .onChange(of: exchange.isRunning) { _, running in
            if !running {
                reload()
                revision += 1
            }
        }
        .task(id: LoadKey(selection: selection, revision: revision)) {
            guard let url = selected?.url else {
                text = ""
                return
            }
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? String(localized: "Protokoll nicht lesbar.")
        }
    }

    private func reload() {
        sessions = SessionLogStore.sessions()
        if selected == nil { selection = sessions.first?.id }
    }
}
