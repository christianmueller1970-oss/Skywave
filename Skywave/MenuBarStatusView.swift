import SwiftUI

/// Inhalt des Menüleisten-Symbols: letzter/nächster Abruf,
/// Postausgangs-Zähler, «Jetzt abrufen» und Sprung ins Hauptfenster.
struct MenuBarStatusView: View {
    @Environment(AppModel.self) private var app
    @Environment(ExchangeController.self) private var exchange
    @Environment(AutoFetchController.self) private var autoFetch
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let workspace = app.workspace {
            if exchange.isRunning {
                Text("Austausch läuft …")
            } else if let last = exchange.lastSuccessDate {
                Text("Letzter Abruf: \(last.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Noch kein Abruf in dieser Sitzung")
            }
            if let next = autoFetch.nextFetch {
                Text("Nächster Auto-Abruf: \(next.formatted(date: .omitted, time: .shortened))")
            }
            let outbox = workspace.store.items(in: .outbox).count
            if outbox > 0 {
                Text(outbox == 1 ? "1 Nachricht im Postausgang" : "\(outbox) Nachrichten im Postausgang")
            }

            Divider()

            Button("Jetzt abrufen") {
                Task {
                    await exchange.exchange(
                        store: workspace.store, settings: workspace.settings,
                        history: workspace.history)
                }
            }
            .disabled(exchange.isRunning)
        } else {
            Text("Kein Datenordner gewählt")
        }

        Divider()

        Button("Skywave öffnen") {
            openWindow(id: "mailbox")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
