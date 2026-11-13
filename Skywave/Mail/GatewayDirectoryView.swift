import SwiftUI
import WinlinkKit

/// The gateway window: every known RMS channel with distance, bearing
/// and bandwidth, filterable, with favourites and a refresh button.
///
/// The connect dialog's picker only shows a short list; this is where
/// the whole directory lives.
struct GatewayDirectoryView: View {
    @Environment(GatewayStore.self) private var gateways
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.finishSection) private var finishSection

    @State private var search = ""
    @State private var bandFilter: String?
    @State private var favoritesOnly = false
    @State private var sortOrder = [KeyPathComparator(\GatewayChannel.gateway)]
    @State private var selection = Set<GatewayChannel.ID>()

    /// Set by the table's context menu, opens the connect sheet.
    @State private var connectTo: GatewayChannel?

    var body: some View {
        VStack(spacing: 0) {
            if let notice {
                NoticeBanner(text: notice, isWarning: gateways.accessDenied)
            }

            Table(visibleChannels, selection: $selection, sortOrder: $sortOrder) {
                leadingColumns
                trailingColumns
            }
            .contextMenu(forSelectionType: GatewayChannel.ID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                // Doppelklick auf die Zeile übernimmt den Kanal — ohne das
                // war der einzige Weg das Kontextmenü, und der ist nicht
                // zu erraten.
                connect(to: ids)
            }
            .searchable(text: $search, prompt: "Rufzeichen oder Locator")

            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle("Gateways")
        .toolbar { toolbar }
        .sheet(item: $connectTo) { channel in
            // Nach dem Verbinden hat das Verzeichnis seinen Zweck erfüllt
            // und stünde sonst nur noch im Weg.
            RadioConnectSheet(
                kind: channel.kind, preselectedChannelID: channel.id,
                onConnected: {
                    if let finishSection { finishSection.run() } else { dismiss() }
                })
        }
    }

    // Zwei Hälften, sonst gibt der Typprüfer bei elf Spalten auf.
    @TableColumnBuilder<GatewayChannel, KeyPathComparator<GatewayChannel>>
    private var leadingColumns: some TableColumnContent<GatewayChannel, KeyPathComparator<GatewayChannel>> {
            TableColumn("") { channel in
                FavoriteToggle(channel: channel, gateways: gateways)
            }
            .width(24)

            TableColumn("Gateway", value: \.gateway)
            // Ohne diese Spalte sind zwei Zeilen desselben Gateways auf
            // derselben Frequenz nicht auseinanderzuhalten — HB9AK auf
            // 40 m gibt es als ARDOP (2000 Hz) und als VARA HF (2750 Hz).
            TableColumn("Transport", value: \.transportSortKey) { channel in
                Text(verbatim: channel.kind.displayName)
            }
            .width(80)
            TableColumn("Band", value: \.centerHz) { channel in
                Text(channel.band)
            }
            .width(60)
            TableColumn("Dial", value: \.dialHz) { channel in
                Text("\(GatewayChannel.kilohertz(channel.dialHz)) kHz")
                    .monospacedDigit()
            }
            .width(100)
            TableColumn("Bandbreite", value: \.bandwidthSortKey) { channel in
                Text(channel.bandwidthHz.map { "\($0) Hz" } ?? "—")
                    .foregroundStyle(channel.bandwidthHz == nil ? .secondary : .primary)
            }
            .width(80)
    }

    @TableColumnBuilder<GatewayChannel, KeyPathComparator<GatewayChannel>>
    private var trailingColumns: some TableColumnContent<GatewayChannel, KeyPathComparator<GatewayChannel>> {
            TableColumn("Distanz", value: \.distanceSortKey) { channel in
                Text(channel.distanceKm.map { "\($0) km" } ?? "—")
                    .monospacedDigit()
            }
            .width(70)
            TableColumn("Peilung", value: \.headingSortKey) { channel in
                Text(channel.headingDegrees.map { String(format: "%03d°", $0) } ?? "—")
                    .monospacedDigit()
            }
            .width(60)
            TableColumn("Zuletzt") { channel in
                LastContactCell(channel: channel, history: history)
            }
            .width(110)
            TableColumn("Rate") { channel in
                RateCell(channel: channel, history: history)
            }
            .width(60)
            TableColumn("Quelle", value: \.sourceSortKey) { channel in
                Text(channel.source == .builtin ? "Eingebaut" : "Winlink")
                    .foregroundStyle(.secondary)
            }
            .width(70)
    }

    // MARK: - Content

    private var visibleChannels: [GatewayChannel] {
        var channels = gateways.sorted(gateways.channels)
        if favoritesOnly {
            channels = channels.filter { gateways.isFavorite($0.id) }
        }
        if let bandFilter {
            channels = channels.filter { $0.band == bandFilter }
        }
        let needle = search.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            channels = channels.filter {
                $0.gateway.localizedCaseInsensitiveContains(needle)
                    || $0.grid.localizedCaseInsensitiveContains(needle)
            }
        }
        return channels.sorted(using: sortOrder)
    }

    private var bands: [String] {
        Array(Set(gateways.channels.map(\.band))).sorted { left, right in
            // Sort by frequency, not alphabetically: "10 m" before "160 m".
            let order = gateways.channels
            let leftHz = order.first { $0.band == left }?.centerHz ?? 0
            let rightHz = order.first { $0.band == right }?.centerHz ?? 0
            return leftHz < rightHz
        }
    }

    /// The one message worth putting above the table, if any.
    private var notice: String? {
        if let blocked = gateways.refreshBlockedReason(settings: settings) {
            return String(localized: "\(blocked) Es wird die eingebaute Starterliste gezeigt.")
        }
        if gateways.usesBuiltinFallback {
            return String(localized: "Noch keine Liste abgerufen — es wird die eingebaute Starterliste gezeigt.")
        }
        if let error = gateways.lastError {
            return String(localized: "Letzter Abgleich fehlgeschlagen: \(String(describing: error))")
        }
        return nil
    }

    // MARK: - Chrome

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem {
            Menu {
                Button("Alle Bänder") { bandFilter = nil }
                Divider()
                ForEach(bands, id: \.self) { band in
                    Button(band) { bandFilter = band }
                }
            } label: {
                Label(bandFilter ?? String(localized: "Alle Bänder"), systemImage: "line.3.horizontal.decrease")
            }
        }
        ToolbarItem {
            Toggle(isOn: $favoritesOnly) {
                Label("Nur Favoriten", systemImage: favoritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
        }
        ToolbarItem {
            RefreshButton(gateways: gateways, settings: settings)
        }
        // Nur im Hauptfenster: das Verzeichnis neben das Postfach legen.
        if finishSection != nil {
            ToolbarItem {
                Button {
                    openWindow(id: "gateways")
                } label: {
                    Label("In eigenem Fenster öffnen", systemImage: "macwindow.on.rectangle")
                }
                .help("Gateway-Verzeichnis zusätzlich als eigenes Fenster öffnen")
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(visibleChannels.count) von \(gateways.channels.count) Kanälen")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Verbinden über diesen Kanal …") {
                connect(to: selection)
            }
            .disabled(selectedChannel == nil)
            .help("Öffnet den Verbindungsdialog mit dem gewählten Gateway")
            Divider().frame(height: 14)
            FreshnessLabel(gateways: gateways)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// Der aktuell markierte Kanal, sofern genau einer gewählt ist.
    private var selectedChannel: GatewayChannel? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return gateways.channel(id: id)
    }

    /// Öffnet den Verbindungsdialog mit dem gewählten Kanal. Gemeinsamer
    /// Weg für Doppelklick, Fussleisten-Knopf und Kontextmenü.
    private func connect(to ids: Set<GatewayChannel.ID>) {
        guard let id = ids.first, let channel = gateways.channel(id: id) else { return }
        connectTo = channel
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<GatewayChannel.ID>) -> some View {
        if let id = ids.first, let channel = gateways.channel(id: id) {
            Button(gateways.isFavorite(id) ? "Favorit entfernen" : "Als Favorit") {
                gateways.toggleFavorite(id)
            }
            Button("Verbinden über \(channel.kind.displayName) …") {
                connectTo = channel
            }
            Divider()
            Button("Dial-Frequenz kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    GatewayChannel.kilohertz(channel.dialHz), forType: .string)
            }
        }
    }
}

// MARK: - Pieces

private struct NoticeBanner: View {
    let text: String
    let isWarning: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(isWarning ? .statusWarn : .secondary)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5))
    }
}

/// The store is passed in, not read from the environment: SwiftUI hosts
/// toolbar items and table cells outside this view's hierarchy, where an
/// `@Environment(GatewayStore.self)` lookup traps at runtime.
private struct FavoriteToggle: View {
    let channel: GatewayChannel
    let gateways: GatewayStore

    var body: some View {
        Button {
            gateways.toggleFavorite(channel.id)
        } label: {
            Image(systemName: gateways.isFavorite(channel.id) ? "star.fill" : "star")
                .foregroundStyle(gateways.isFavorite(channel.id) ? .favorite : .secondary)
        }
        .buttonStyle(.plain)
        .help(gateways.isFavorite(channel.id) ? "Favorit entfernen" : "Als Favorit")
    }
}

/// Letzter Verbindungsversuch zu diesem Gateway über diesen Transport
/// (die Historie kennt kein einzelnes Band). Der Store wird übergeben,
/// nicht aus der Umgebung gelesen — siehe `FavoriteToggle`.
private struct LastContactCell: View {
    let channel: GatewayChannel
    let history: ConnectionHistoryStore

    var body: some View {
        if let last = history.last(gateway: channel.gateway, kind: channel.kind) {
            HStack(spacing: 4) {
                Image(systemName: last.outcome == .success ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(last.outcome == .success ? .statusOK : .statusWarn)
                Text(last.date.formatted(.relative(presentation: .named)))
                    .lineLimit(1)
            }
            .help(last.summaryLine + (last.errorText.map { " — \($0)" } ?? ""))
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}

/// Datenrate des letzten erfolgreichen Kontakts.
private struct RateCell: View {
    let channel: GatewayChannel
    let history: ConnectionHistoryStore

    var body: some View {
        let rate = history.lastSuccess(gateway: channel.gateway, kind: channel.kind)?.rateText
        Text(rate ?? "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// Refresh, disabled while the client's own rate limit is in force —
/// Winlink asks that these endpoints be queried sparingly.
private struct RefreshButton: View {
    let gateways: GatewayStore
    let settings: AppSettingsStore

    var body: some View {
        Button {
            Task { await gateways.refresh(settings: settings, force: true) }
        } label: {
            if gateways.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
            }
        }
        .disabled(!canRefresh)
        .help(helpText)
    }

    private var canRefresh: Bool {
        !gateways.isRefreshing
            && gateways.refreshBlockedReason(settings: settings) == nil
    }

    private var helpText: String {
        if let blocked = gateways.refreshBlockedReason(settings: settings) {
            return blocked
        }
        if let next = gateways.nextAllowedRefresh {
            return String(localized: "Frühestens wieder \(next.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Liste bei Winlink neu abrufen")
    }
}

private struct FreshnessLabel: View {
    let gateways: GatewayStore

    var body: some View {
        if let lastRefresh = gateways.lastRefresh {
            let age = Date.now.timeIntervalSince(lastRefresh)
            Text("Aktualisiert \(lastRefresh.formatted(.relative(presentation: .named)))")
                // Beyond two days the frequencies may well have moved.
                .foregroundStyle(age > 48 * 3600 ? .statusWarn : .secondary)
        } else {
            Text("Noch nie abgerufen")
                .foregroundStyle(.secondary)
        }
    }
}
