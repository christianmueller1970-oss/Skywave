import SwiftUI
import WinlinkKit

/// The connect dialog for a radio exchange: gateway picker or manual
/// callsign plus the transport's bandwidth choice, prefilled from the
/// last use. Picking a listed gateway also arms the automatic QSY
/// (frequency + USB-D via CI-V) when the integrated TNC keys via CAT.
/// Modem host/port configuration lives in Einstellungen → Funk.
struct RadioConnectSheet: View {
    let kind: RadioTransportKind
    /// Opened from the gateway window: start on this channel instead of
    /// the last one used.
    var preselectedChannelID: String?
    /// Wird gerufen, sobald der Austausch startet — das Gateway-Fenster
    /// schliesst sich daraufhin, statt hinter der Sitzung stehen zu bleiben.
    var onConnected: (() -> Void)?

    @Environment(MailStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(GatewayStore.self) private var gateways
    @Environment(ExchangeController.self) private var exchange
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var gateway = ""
    @State private var varaBandwidth = SettingsKeys.defaultVaraHFBandwidth
    @State private var ardopMax = 2000
    @State private var ardopForced = false
    @State private var channelID: String?
    /// Im Dialog abgewählte Postausgangs-Nachrichten (MIDs); alles
    /// andere, was für Funk erlaubt ist, geht mit.
    @State private var deselected = Set<String>()

    private var path: ExchangePath {
        .radio(kind, gateway: gateway.trimmingCharacters(in: .whitespaces).uppercased())
    }

    /// Nachrichten, die über Funk raus dürfen — Kennzeichnung
    /// «beliebig» oder «nur Funk».
    private var eligible: [MailItem] {
        store.items(in: .outbox).filter { $0.route.allows(path) }
    }

    private var heldCount: Int {
        store.heldItems(for: path).count
    }

    private var selectedItems: [MailItem] {
        eligible.filter { !deselected.contains($0.id) }
    }

    /// Grober Richtwert fürs Funkbudget; die echte Rate hängt von
    /// Band und Bedingungen ab.
    private var estimateMode: TransferTimeEstimator.Mode {
        switch kind {
        case .ardop: ardopMax <= 500 ? .ardop500 : .ardop2000
        case .varaHF, .varaFM: .varaHF
        }
    }

    private var outboundSummary: String {
        let items = selectedItems
        guard !items.isEmpty else { return String(localized: "Nichts zu senden — nur Abruf.") }
        let bytes = items.reduce(0) { $0 + $1.sizeBytes }
        let count = items.count == 1 ? String(localized: "1 Nachricht") : String(localized: "\(items.count) Nachrichten")
        return "\(count), \(SessionMailbox.kilobytes(bytes)) kB, "
            + TransferTimeEstimator.formatted(bytes: bytes, mode: estimateMode)
    }

    /// Favourites first, then the nearest — a picker with every known
    /// channel would be unusable. «Alle anzeigen …» opens the window.
    private var channels: [GatewayChannel] {
        var listed = gateways.suggestions(for: kind)
        // A channel opened from the window — or the last one used —
        // may sit outside the top of the list; it still has to be
        // selectable here. Without a matching entry the picker cannot
        // show its selection at all and visibly falls back to «Manuell».
        for id in [preselectedChannelID, channelID].compactMap({ $0 }) {
            guard !listed.contains(where: { $0.id == id }),
                let channel = gateways.channel(id: id)
            else { continue }
            listed.insert(channel, at: 0)
        }
        return listed
    }

    /// Kanaele der Liste, die zum von Hand eingetippten Rufzeichen
    /// passen — nur gefuellt, wenn gerade «Manuell» gilt.
    private var matchesForTypedGateway: [GatewayChannel] {
        let call = gateway.trimmingCharacters(in: .whitespaces).uppercased()
        guard channelID == nil, !call.isEmpty else { return [] }
        return gateways.channels(for: kind).filter { $0.gateway == call }
    }

    /// Entfernung und Peilung als eine Zeile — beides kann fehlen,
    /// wenn der Kanal aus der eingebauten Starterliste kommt.
    private func channelDistanceText(_ channel: GatewayChannel) -> String {
        var parts: [String] = []
        if let km = channel.distanceKm { parts.append("\(km) km") }
        if let heading = channel.headingDegrees {
            parts.append(String(format: "%03d°", heading))
        }
        return parts.joined(separator: " · ")
    }

    private var selectedChannel: GatewayChannel? {
        channelID.flatMap(gateways.channel(id:))
    }

    /// QSY läuft bei ARDOP, sobald Skywave das Gerät erreicht: über
    /// rigctld (RigController) oder direkt per CI-V.
    private var qsyActive: Bool {
        kind == .ardop && selectedChannel != nil && settings.qsyAvailable
    }

    private var qsyPathName: String {
        settings.civQSYAvailable ? String(localized: "per CI-V") : String(localized: "über rigctld")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if !channels.isEmpty {
                        Picker("Gateway", selection: $channelID) {
                            Text("Manuell").tag(String?.none)
                            Divider()
                            ForEach(channels) { channel in
                                Text(label(for: channel)).tag(String?.some(channel.id))
                            }
                        }
                        .onChange(of: channelID) { _, newValue in
                            guard let channel = newValue.flatMap(gateways.channel(id:))
                            else { return }
                            gateway = channel.gateway
                            // No reported bandwidth means keep the
                            // user's choice rather than guess one.
                            if let width = channel.bandwidthHz {
                                if kind == .ardop,
                                    ArdopBandwidth.supportedMax.contains(width)
                                {
                                    ardopMax = width
                                }
                                if kind == .varaHF,
                                    VaraModem.bandwidths.contains(String(width))
                                {
                                    varaBandwidth = String(width)
                                }
                            }
                        }

                        // Nur anbieten, wenn der Dialog NICHT aus dem
                        // Gateway-Fenster kommt (dann ist preselectedChannelID
                        // gesetzt) — sonst öffnet der Knopf ein zweites
                        // Fenster über dem, aus dem er aufgerufen wurde, und
                        // dieser Dialog bliebe mit dem alten Gateway stehen.
                        if preselectedChannelID == nil {
                            Button("Alle Gateways anzeigen …") {
                                openWindow(id: "gateways")
                                dismiss()
                            }
                            .buttonStyle(.link)
                        }
                    }

                    // Bewusst ein eigenes Binding statt .onChange: nur
                    // eine Eingabe im Feld darf die Kanalwahl loesen.
                    // Mit .onChange feuerte die Pruefung auch, wenn
                    // prefill() und die Picker-Wahl das Rufzeichen im
                    // selben Durchlauf setzten — dann kam sie mit dem
                    // alten Wert an und loeschte den gerade gewaehlten
                    // Kanal samt Dial-Frequenz (kein QSY mehr).
                    TextField(
                        "Gateway-Rufzeichen",
                        text: Binding(
                            get: { gateway },
                            set: { newValue in
                                gateway = newValue
                                // A manual edit away from the picked gateway
                                // switches back to "Manuell" (and disarms QSY).
                                if let channel = selectedChannel,
                                    newValue != channel.gateway
                                {
                                    channelID = nil
                                }
                            }),
                        prompt: Text("HB9AK")
                    )
                    .autocorrectionDisabled()

                    if let channel = selectedChannel {
                        LabeledContent(
                            "Dial-Frequenz",
                            value: "\(GatewayChannel.kilohertz(channel.dialHz)) kHz · USB-D")
                        LabeledContent(
                            "Center-Frequenz",
                            value: "\(GatewayChannel.kilohertz(channel.centerHz)) kHz · \(channel.band)")
                        if let width = channel.bandwidthHz {
                            LabeledContent("Kanal-Bandbreite", value: "\(width) Hz")
                        }
                        if channel.distanceKm != nil || channel.headingDegrees != nil {
                            LabeledContent("Entfernung", value: channelDistanceText(channel))
                        }
                        if let last = history.last(gateway: channel.gateway, kind: kind) {
                            LabeledContent("Zuletzt", value: last.summaryLine)
                            if last.outcome != .success,
                                let success = history.lastSuccess(gateway: channel.gateway, kind: kind)
                            {
                                LabeledContent("Letzter Erfolg", value: success.summaryLine)
                            }
                        }
                    } else if !matchesForTypedGateway.isEmpty {
                        // Von Hand eingetippt: ohne Kanal kennt Skywave
                        // weder Frequenz noch Band, kann also auch nicht
                        // umstimmen. Das Rufzeichen steht aber in der
                        // Liste — dann sagen, wo die Angaben herkommen.
                        Text("\(gateway.uppercased()) steht mit \(matchesForTypedGateway.count) Kanälen in der Liste. Oben einen davon wählen — dann kennt Skywave Dial-Frequenz und Bandbreite und stellt sie vor dem Verbinden ein.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if kind == .varaHF {
                        Picker("Bandbreite", selection: $varaBandwidth) {
                            ForEach(VaraModem.bandwidths, id: \.self) { value in
                                Text("\(value) Hz").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .ardop {
                        Picker("Max. Bandbreite", selection: $ardopMax) {
                            ForEach(ArdopBandwidth.supportedMax, id: \.self) { value in
                                Text("\(value) Hz").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        Toggle("Bandbreite erzwingen (FORCED)", isOn: $ardopForced)
                    }
                    if kind == .ardop {
                        LabeledContent("Funkgerät") { RigStatusLine() }
                    }
                } header: {
                    Text("Verbindung über \(kind.displayName)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if qsyActive {
                            if settings.restoreQRGAfterSession {
                                Text("""
                                    Frequenz und Modus (USB-D) werden vor dem Verbinden \
                                    \(qsyPathName) eingestellt und nach der Sitzung wiederhergestellt.
                                    """)
                            } else {
                                Text("""
                                    Frequenz und Modus (USB-D) werden vor dem Verbinden \
                                    \(qsyPathName) eingestellt und bleiben danach stehen \
                                    (umstellbar in Einstellungen → Funkgerät).
                                    """)
                            }
                        } else if selectedChannel != nil {
                            Text("""
                                Dial-Frequenz und USB-D bitte von Hand am Funkgerät \
                                einstellen — automatisch geht das, sobald unter \
                                Einstellungen → Funkgerät ein Weg zum Gerät eingerichtet ist.
                                """)
                        }
                        if kind == .ardop {
                            Text("""
                                FORCED besteht auf genau dieser Bandbreite; sonst gilt \
                                sie als Maximum. Modem-Host und Ports: Einstellungen → Modem.
                                """)
                        } else {
                            Text("Modem-Host und Ports: Einstellungen → Modem.")
                        }
                    }
                }

                Section {
                    // Der Dialog ist auf seine Inhaltshöhe fixiert; ein
                    // voller Postausgang darf ihn nicht über den Bildschirm
                    // hinaus strecken — ab etwa sechs Zeilen wird gescrollt,
                    // die Knöpfe unten bleiben erreichbar.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(eligible) { item in
                                Toggle(
                                    isOn: Binding(
                                        get: { !deselected.contains(item.id) },
                                        set: { on in
                                            if on {
                                                deselected.remove(item.id)
                                            } else {
                                                deselected.insert(item.id)
                                            }
                                        })
                                ) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.subject.isEmpty ? String(localized: "(ohne Betreff)") : item.subject)
                                            .lineLimit(1)
                                        Text("\(item.to) · \(SessionMailbox.kilobytes(item.sizeBytes)) kB")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                } header: {
                    Text("Versand")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outboundSummary)
                        if heldCount > 0 {
                            Text(heldCount == 1
                                ? "1 weitere Nachricht bleibt zurückgehalten (Versandweg)."
                                : "\(heldCount) weitere Nachrichten bleiben zurückgehalten (Versandweg).")
                        }
                        if settings.radioInboundMaxKB > 0 {
                            Text("Eingang: Nachrichten über \(settings.radioInboundMaxKB) kB werden zurückgestellt.")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) {
                    dismiss()
                }
                Button("Verbinden") {
                    connect()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    gateway.trimmingCharacters(in: .whitespaces).isEmpty
                        || exchange.isRunning
                        || exchange.isTuning)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 380)
        .onAppear(perform: prefill)
    }

    /// Favourites carry a star, and the distance is worth the width.
    private func label(for channel: GatewayChannel) -> String {
        let star = gateways.isFavorite(channel.id) ? "★ " : ""
        return star + channel.detailLabel
    }

    private func prefill() {
        switch kind {
        case .varaHF:
            gateway = settings.varaHFGateway
            if VaraModem.bandwidths.contains(settings.varaHFBandwidth) {
                varaBandwidth = settings.varaHFBandwidth
            }
        case .varaFM:
            gateway = settings.varaFMGateway
        case .ardop:
            gateway = settings.ardopGateway
            if let parsed = ArdopBandwidth(parsing: settings.ardopBandwidth) {
                ardopMax = parsed.max
                ardopForced = parsed.forced
            }
            // Restore the last picker choice; its onChange re-derives
            // callsign and bandwidth from the channel.
            if gateways.channel(id: settings.ardopChannelID) != nil {
                channelID = settings.ardopChannelID
            }
        }
        // Opened from the gateway window: that choice wins.
        if let preselectedChannelID, gateways.channel(id: preselectedChannelID) != nil {
            channelID = preselectedChannelID
        }
    }

    private func connect() {
        let target = gateway.trimmingCharacters(in: .whitespaces).uppercased()
        var bandwidth: String?
        switch kind {
        case .varaHF:
            settings.varaHFGateway = target
            settings.varaHFBandwidth = varaBandwidth
            bandwidth = varaBandwidth
        case .varaFM:
            settings.varaFMGateway = target
            bandwidth = nil
        case .ardop:
            settings.ardopGateway = target
            let parsed = ArdopBandwidth(max: ardopMax, forced: ardopForced)
            settings.ardopBandwidth = parsed?.description ?? SettingsKeys.defaultArdopBandwidth
            bandwidth = settings.ardopBandwidth
            settings.ardopChannelID = channelID ?? ""
        }
        let dialHz = selectedChannel?.dialHz
        let centerHz = selectedChannel?.centerHz
        let selection = Set(selectedItems.map(\.id))
        dismiss()
        onConnected?()
        Task {
            await exchange.exchangeRadio(
                kind: kind, gateway: target, bandwidth: bandwidth, dialHz: dialHz,
                centerHz: centerHz, selection: selection, store: store, settings: settings,
                history: history)
        }
    }
}
