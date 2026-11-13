import SwiftUI

/// Auswahl im Bereich «Verbindungen»: nach Weg, Ergebnis und Rufzeichen.
struct ConnectionFilter: Equatable {
    enum Way: Hashable {
        case all
        case internet
        case radio(RadioTransportKind)

        static let allCases: [Way] = [.all, .internet] + RadioTransportKind.allCases.map(Way.radio)

        var title: String {
            switch self {
            case .all: String(localized: "Alle Wege")
            case .internet: "Internet"
            case .radio(let kind): kind.displayName
            }
        }
    }

    var way = Way.all
    /// nil = alle Ergebnisse.
    var outcome: ConnectionRecord.Outcome?
    var search = ""

    func apply(to records: [ConnectionRecord]) -> [ConnectionRecord] {
        let query = search.trimmingCharacters(in: .whitespaces).uppercased()
        return records.filter { record in
            switch way {
            case .all: break
            case .internet: if record.kind != nil { return false }
            case .radio(let kind): if record.kind != kind { return false }
            }
            if let outcome, record.outcome != outcome { return false }
            return query.isEmpty || record.gateway.uppercased().contains(query)
        }
    }
}

extension ConnectionRecord {
    /// «12.11.2026 16:39» in UTC, für die Liste der Verbindungen.
    var utcStamp: String { Self.listStamp.string(from: date) }

    /// «ARDOP» bzw. «Internet».
    var wayText: String { kind?.displayName ?? "Internet" }

    /// «3'613,0 kHz · 80 m» — nil ohne Kanal aus dem Verzeichnis.
    var channelText: String? {
        centerHz.map { "\(GatewayChannel.kilohertz($0)) kHz · \(GatewayChannel.band(forHz: $0))" }
    }

    var outcomeText: String {
        switch outcome {
        case .success: String(localized: "Erfolgreich")
        case .aborted: String(localized: "Abgebrochen")
        case .failed: String(localized: "Fehlgeschlagen")
        }
    }

    var outcomeSymbol: String {
        switch outcome {
        case .success: "checkmark.circle.fill"
        case .aborted: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private static let listStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd.MM.yyyy HH:mm"
        return f
    }()
}

/// Bereich «Verbindungen»: jeder Verbindungsversuch mit Ergebnis, neueste
/// zuerst. Zeiten in UTC.
struct ConnectionHistoryView: View {
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(ExchangeController.self) private var exchange
    @Environment(MailboxCommandCenter.self) private var commands
    @Environment(AppNavigation.self) private var nav

    @State private var filter = ConnectionFilter()
    @State private var selection: ConnectionRecord.ID?

    private var visible: [ConnectionRecord] { filter.apply(to: history.records) }

    private var selected: ConnectionRecord? {
        visible.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Weg", selection: $filter.way) {
                    ForEach(ConnectionFilter.Way.allCases, id: \.self) { way in
                        Text(way.title).tag(way)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Picker("Ergebnis", selection: $filter.outcome) {
                    Text("Alle Ergebnisse").tag(ConnectionRecord.Outcome?.none)
                    Text("Erfolgreich").tag(ConnectionRecord.Outcome?.some(.success))
                    Text("Abgebrochen").tag(ConnectionRecord.Outcome?.some(.aborted))
                    Text("Fehlgeschlagen").tag(ConnectionRecord.Outcome?.some(.failed))
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            if visible.isEmpty {
                ContentUnavailableView(
                    history.records.isEmpty ? "Noch keine Verbindungen" : "Keine Treffer",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        history.records.isEmpty
                            ? "Jeder Austausch über Internet oder Funk erscheint hier mit seinem Ergebnis."
                            : "Kein Eintrag passt zur Auswahl.")
                )
            } else {
                Table(visible, selection: $selection) {
                    TableColumn("Zeit (UTC)") { record in
                        Text(record.utcStamp).monospacedDigit()
                    }
                    .width(min: 120, ideal: 130)
                    TableColumn("Gegenstelle") { record in
                        Text(record.gateway).fontWeight(.medium)
                    }
                    .width(min: 90, ideal: 120)
                    TableColumn("Weg") { record in
                        Text(record.wayText)
                    }
                    .width(min: 70, ideal: 80)
                    TableColumn("Kanal") { record in
                        Text(record.channelText ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(record.channelText == nil ? .secondary : .primary)
                    }
                    .width(min: 120, ideal: 150)
                    TableColumn("Ergebnis") { record in
                        OutcomeLabel(record: record)
                    }
                    .width(min: 130, ideal: 220)
                    TableColumn("Nachrichten") { record in
                        Text("\(record.received) empfangen · \(record.sent) gesendet")
                            .monospacedDigit()
                    }
                    .width(min: 150, ideal: 170)
                    TableColumn("Dauer") { record in
                        Text(record.durationText).monospacedDigit()
                    }
                    .width(min: 50, ideal: 60)
                    TableColumn("Rate") { record in
                        Text(record.rateText ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 70)
                }
            }

            Divider()
            HStack {
                Text("\(visible.count) von \(history.records.count) Verbindungen")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Protokolle anzeigen") {
                    nav.show(.logs)
                }
                .help("Die gespeicherten Sitzungsprotokolle öffnen")
                Button("Erneut verbinden …") {
                    guard let selected else { return }
                    if let kind = selected.kind {
                        commands.send(.radio(kind))
                    } else {
                        commands.send(.exchangeInternet)
                    }
                }
                .disabled(selected == nil || exchange.isRunning)
                .help("Denselben Weg noch einmal versuchen")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .searchable(text: $filter.search, placement: .toolbar, prompt: "Rufzeichen")
        .navigationTitle("Verbindungen")
    }
}

/// Ergebnis einer Verbindung: Symbol und Text, nie nur Farbe.
private struct OutcomeLabel: View {
    let record: ConnectionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(record.outcomeText, systemImage: record.outcomeSymbol)
                .foregroundStyle(color)
            if let error = record.errorText, record.outcome != .success {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(record.errorText ?? record.summaryLine)
    }

    private var color: Color {
        switch record.outcome {
        case .success: .statusOK
        case .aborted: .statusWarn
        case .failed: .statusError
        }
    }
}
