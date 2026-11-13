import SwiftUI

/// Was im Postausgang wartet, nach Versandweg.
struct OutboxSummary: Equatable {
    let total: Int
    /// Anzahl je Kennzeichnung, nur vorhandene, in fester Reihenfolge.
    let counts: [OutboxRoute: Int]

    init(items: [MailItem]) {
        total = items.count
        counts = Dictionary(grouping: items, by: \.route).mapValues(\.count)
    }

    /// «2 für jeden Weg», «1 nur über Funk», … — eine Zeile je Weg.
    var lines: [String] {
        OutboxRoute.allCases.compactMap { route in
            guard let count = counts[route], count > 0 else { return nil }
            switch route {
            case .any: return String(localized: "\(count) für jeden Weg")
            case .internet: return String(localized: "\(count) nur über Internet")
            case .radio: return String(localized: "\(count) nur über Funk")
            case .hold: return String(localized: "\(count) zurückgehalten")
            }
        }
    }

    /// «3 Nachrichten warten» bzw. «Nichts zu senden».
    var headline: String {
        switch total {
        case 0: String(localized: "Nichts zu senden")
        case 1: String(localized: "1 Nachricht wartet")
        default: String(localized: "\(total) Nachrichten warten")
        }
    }
}

/// Die Übersicht in der rechten Spalte des Postfachs, solange keine
/// Nachricht gewählt ist: was wartet, wann zuletzt ausgetauscht wurde,
/// wo das Funkgerät steht — und die häufigsten Schritte.
struct OverviewView: View {
    @Environment(MailStore.self) private var store
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(ExchangeController.self) private var exchange
    @Environment(AppNavigation.self) private var nav
    @Environment(MailboxCommandCenter.self) private var commands
    @Environment(\.openWindow) private var openWindow

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)]

    private var unread: Int {
        store.allFolders.filter(\.isInboxTree).reduce(0) { $0 + store.unreadCount(in: $1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Übersicht")
                    .font(.title2.bold())

                HStack(spacing: 10) {
                    Button {
                        commands.send(.exchangeInternet)
                    } label: {
                        Label("Abrufen & Senden", systemImage: "envelope.arrow.triangle.branch")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(exchange.isRunning)
                    .help("Mit dem Winlink-CMS über Internet austauschen (⇧⌘R)")
                    Button {
                        openWindow(id: "compose")
                    } label: {
                        Label("Neue Nachricht", systemImage: "square.and.pencil")
                    }
                    Button {
                        nav.show(.gateways)
                    } label: {
                        Label("Über Funk verbinden", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .help("Gateway-Verzeichnis öffnen und einen Kanal wählen")
                }
                .controlSize(.large)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    Card(title: String(localized: "Posteingang")) {
                        Text(unread == 0 ? "Alles gelesen" : unread == 1 ? "1 ungelesene Nachricht" : "\(unread) ungelesene Nachrichten")
                            .font(.headline)
                        Text("Wähle links in der Liste eine Nachricht, um sie zu lesen.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    outboxCard
                    lastExchangeCard
                    Card(title: String(localized: "Funkgerät")) {
                        RigStatusLine()
                        Button("Funkgerät öffnen") { nav.show(.rig) }
                    }
                    connectionsCard
                }
            }
            .padding(20)
        }
    }

    private var outboxCard: some View {
        let summary = OutboxSummary(items: store.items(in: .outbox))
        return Card(title: String(localized: "Postausgang")) {
            Text(summary.headline)
                .font(.headline)
            ForEach(summary.lines, id: \.self) { line in
                Text(line).foregroundStyle(.secondary)
            }
            Button("Postausgang öffnen") { nav.show(.folder(.outbox)) }
        }
    }

    private var lastExchangeCard: some View {
        let last = history.records.first { $0.outcome == .success }
        return Card(title: String(localized: "Letzter Austausch")) {
            if let last {
                Text("\(last.utcStamp) UTC")
                    .font(.headline)
                    .monospacedDigit()
                Text("\(last.wayText) · \(last.gateway) · \(last.received) empfangen, \(last.sent) gesendet")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Noch kein erfolgreicher Austausch")
                    .font(.headline)
            }
        }
    }

    private var connectionsCard: some View {
        Card(title: String(localized: "Letzte Verbindungen")) {
            if history.records.isEmpty {
                Text("Noch keine Verbindungen")
                    .foregroundStyle(.secondary)
            }
            ForEach(history.records.prefix(3)) { record in
                HStack(spacing: 6) {
                    Image(systemName: record.outcomeSymbol)
                        .foregroundStyle(
                            record.outcome == .success
                                ? Color.statusOK
                                : record.outcome == .aborted ? Color.statusWarn : Color.statusError)
                    Text(record.gateway).fontWeight(.medium)
                    Text("· \(record.wayText) · \(record.outcomeText)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help("\(record.utcStamp) UTC")
            }
            Button("Alle Verbindungen") { nav.show(.connections) }
        }
    }
}
