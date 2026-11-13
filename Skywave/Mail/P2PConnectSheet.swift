import SwiftUI
import WinlinkKit

/// Direktverbindung zu einer Station (P2P), ohne RMS-Gateway: entweder
/// die Gegenstation rufen oder empfangsbereit warten, bis sie ruft.
///
/// Über P2P gehen nur Nachrichten, die ausschliesslich an das
/// Rufzeichen der Gegenstation adressiert sind — so wie bei Winlink
/// Express und Pat. Die Vorschau zeigt sie vor dem Start.
struct P2PConnectSheet: View {
    @Environment(MailStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange
    @Environment(ContactsStore.self) private var contacts
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss

    enum Role: String, CaseIterable, Identifiable {
        case call
        case listen

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .call: String(localized: "Station rufen")
            case .listen: String(localized: "Empfangsbereit")
            }
        }
    }

    @State private var role: Role = .call
    @State private var kind: RadioTransportKind = .ardop
    @State private var peer = ""
    @State private var varaBandwidth = SettingsKeys.defaultVaraHFBandwidth
    @State private var ardopMax = 500
    @State private var dialKHz = ""
    @State private var keepListening = false

    private var peerCall: String {
        peer.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var peerItems: [MailItem] {
        peerCall.isEmpty ? [] : store.outboxItems(exclusivelyFor: peerCall)
    }

    private var dialHz: Int? { Self.dialHz(fromKHz: dialKHz) }

    /// Dial-Frequenz in Hz aus der kHz-Eingabe («3'614,5» oder «3614.5»).
    /// Nur 100 kHz bis 450 MHz; alles andere (auch «inf», «1e20») ist
    /// keine Frequenz und darf nie bis zur Int-Umwandlung kommen.
    static func dialHz(fromKHz text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let khz = Double(cleaned), khz.isFinite, (100...450_000).contains(khz)
        else { return nil }
        return Int((khz * 1000).rounded())
    }

    /// QSY wie beim Gateway: bei ARDOP, sobald Skywave das Gerät erreicht.
    private var qsyActive: Bool {
        kind == .ardop && dialHz != nil && settings.qsyAvailable
    }

    private var callContacts: [Contact] {
        contacts.sorted.filter { !$0.callsign.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Betrieb", selection: $role) {
                        ForEach(Role.allCases) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Verfahren", selection: $kind) {
                        ForEach(RadioTransportKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    if kind == .ardop {
                        LabeledContent("Funkgerät") { RigStatusLine() }
                    }

                    if role == .call {
                        LabeledContent("Gegenstation") {
                            TextField("Gegenstation", text: $peer, prompt: Text("HB9XYZ"))
                                .labelsHidden()
                                .autocorrectionDisabled()
                            if !callContacts.isEmpty {
                                Menu {
                                    ForEach(callContacts) { contact in
                                        Button("\(contact.callsign) – \(contact.displayName)") {
                                            peer = contact.callsign
                                        }
                                    }
                                } label: {
                                    Image(systemName: "person.crop.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Rufzeichen aus den Kontakten übernehmen")
                            }
                        }
                    }

                    if kind == .varaHF, role == .call {
                        Picker("Bandbreite", selection: $varaBandwidth) {
                            ForEach(VaraModem.bandwidths, id: \.self) { value in
                                Text("\(value) Hz").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if kind == .ardop, role == .call {
                        Picker("Max. Bandbreite", selection: $ardopMax) {
                            ForEach(ArdopBandwidth.supportedMax, id: \.self) { value in
                                Text("\(value) Hz").tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    TextField("Dial-Frequenz (kHz)", text: $dialKHz, prompt: Text("optional, z. B. 3'587,0"))
                    if role == .listen {
                        Toggle("Nach einer Sitzung weiter empfangsbereit bleiben", isOn: $keepListening)
                    }
                } header: {
                    Text("Direktverbindung (P2P)")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if dialHz != nil {
                            Text(
                                qsyActive
                                    ? "Frequenz und USB-D werden vorher \(settings.civQSYAvailable ? String(localized: "per CI-V") : String(localized: "über rigctld")) eingestellt."
                                    : "Frequenz bitte von Hand einstellen — automatisch geht das mit ARDOP, sobald unter Einstellungen → Funkgerät ein Weg zum Gerät eingerichtet ist.")
                        }
                        Text(
                            role == .call
                                ? "Kein Gateway, kein Winlink-Passwort: die Gegenstation muss auf derselben Frequenz empfangsbereit sein."
                                : "Skywave wartet, bis eine Station \(settings.effectiveCallsign) ruft, und tauscht dann direkt aus. Abbrechen in der Statuszeile beendet das Warten.")
                    }
                }

                Section {
                    if role == .call {
                        if peerCall.isEmpty {
                            Text("Rufzeichen eingeben, um die passende Post zu sehen.")
                                .foregroundStyle(.secondary)
                        } else if peerItems.isEmpty {
                            Label(
                                "Keine Nachricht ausschliesslich an \(peerCall) im Postausgang — es wird nur abgeholt, was \(peerCall) für dich hat.",
                                systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                        } else {
                            ForEach(peerItems) { item in
                                LabeledContent(
                                    item.subject.isEmpty ? String(localized: "(ohne Betreff)") : item.subject,
                                    value: "\(SessionMailbox.kilobytes(item.sizeBytes)) kB")
                            }
                        }
                    } else {
                        Text("Angeboten wird, was ausschliesslich an die anrufende Station adressiert ist.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Versand")
                } footer: {
                    if role == .call, !peerCall.isEmpty,
                        let last = history.last(gateway: peerCall, kind: kind)
                    {
                        Text("Zuletzt mit \(peerCall): \(last.summaryLine)")
                    }
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                Button(role == .call ? "Rufen" : "Empfang starten") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        exchange.isRunning || exchange.isTuning
                            || (role == .call && peerCall.isEmpty))
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 420)
        .onAppear {
            peer = settings.p2pPeer
            kind = settings.p2pKind
        }
    }

    private func start() {
        settings.p2pKind = kind
        let kind = kind
        let dialHz = dialHz
        dismiss()
        switch role {
        case .call:
            settings.p2pPeer = peerCall
            let peer = peerCall
            let bandwidth: String? =
                switch kind {
                case .varaHF: varaBandwidth
                case .varaFM: nil
                case .ardop: ArdopBandwidth(max: ardopMax)?.description
                }
            Task {
                await exchange.exchangeP2P(
                    kind: kind, peer: peer, bandwidth: bandwidth, dialHz: dialHz,
                    store: store, settings: settings, history: history)
            }
        case .listen:
            let keep = keepListening
            Task {
                await exchange.listenP2P(
                    kind: kind, dialHz: dialHz, keepListening: keep,
                    store: store, settings: settings, history: history)
            }
        }
    }
}
