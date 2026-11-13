import SwiftUI
import WinlinkKit

/// Einstellungen ▸ Funkgerät: der Weg zum Gerät, an einer Stelle und
/// prüfbar. Status zuoberst, dann Gerät, Anschluss, PTT und QSY.
struct RigSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(RigController.self) private var rig
    @Environment(ExchangeController.self) private var exchange

    @State private var serialPorts = [String]()
    @State private var brand = ""
    @State private var civTest: CIVTest = .idle

    private enum CIVTest: Equatable {
        case idle
        case running
        case ok(String)
        case failed(String)
    }

    private let catalog = RigProfileCatalog.bundled

    /// Funkbetrieb läuft: dann bleibt die Verbindung, wie sie ist.
    private var radioBusy: Bool { exchange.isRunning || exchange.isTuning }

    var body: some View {
        @Bindable var settings = settings

        Form {
            statusSection

            Section {
                Picker("Verbindung", selection: $settings.rigAccess) {
                    Text(RigAccess.bundled.displayName).tag(RigAccess.bundled)
                    Text(RigAccess.none.displayName).tag(RigAccess.none)
                    Divider()
                    Text(RigAccess.external.displayName).tag(RigAccess.external)
                    Text(RigAccess.civDirect.displayName).tag(RigAccess.civDirect)
                }
                .disabled(radioBusy)
            } header: {
                Text("Weg zum Funkgerät")
            } footer: {
                Text(accessHint)
            }

            if settings.rigAccess == .bundled {
                Section("Gerät") {
                    Picker("Hersteller", selection: $brand) {
                        if brand.isEmpty { Text("Bitte wählen").tag("") }
                        ForEach(catalog.brands, id: \.self) { Text($0).tag($0) }
                    }
                    Picker(
                        "Modell",
                        selection: Binding(
                            get: { settings.rigProfileID },
                            set: { id in
                                if let profile = catalog.profile(id: id) {
                                    settings.selectRigProfile(profile)
                                }
                            })
                    ) {
                        if settings.rigProfile?.brand != brand { Text("Bitte wählen").tag("") }
                        ForEach(catalog.profiles(brand: brand)) { profile in
                            Text(profile.model).tag(profile.id)
                        }
                    }
                    .disabled(brand.isEmpty)
                }
                .disabled(radioBusy)
            }

            connectionSection
            pttSection

            Section {
                Toggle(
                    "QRG nach der Sitzung zurückstellen",
                    isOn: $settings.restoreQRGAfterSession)
            } header: {
                Text("QSY")
            } footer: {
                Text("Aus (Vorgabe): Das Funkgerät bleibt nach dem Austausch auf dem Kanal des Gateways stehen — der nächste Ruf läuft ohne erneutes Umstimmen. Ein: Frequenz und Modus von vor der Sitzung werden wiederhergestellt.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            let ports = SerialPortCatalog.portPaths()
            let stored = settings.ardopSerialPort
            serialPorts = stored.isEmpty || ports.contains(stored) ? ports : ports + [stored]
            brand = settings.rigProfile?.brand ?? ""
        }
        // Geänderte Angaben gelten erst für eine neue Verbindung — die
        // alte zu behalten hiesse, etwas anderes anzuzeigen als eingestellt.
        .onChange(of: linkSignature) {
            civTest = .idle
            if rig.status != .disconnected, !radioBusy {
                Task { await rig.disconnect() }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder private var statusSection: some View {
        switch settings.rigAccess {
        case .bundled, .external:
            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                    Text(statusText)
                        .foregroundStyle(isFailed ? .statusError : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if rig.status == .connecting {
                        ProgressView().controlSize(.small)
                    } else if rig.isConnected {
                        Button("Trennen") { Task { await rig.disconnect() } }
                            .disabled(radioBusy)
                    } else {
                        Button("Verbinden") { connect() }
                            .disabled(settings.rigLink == nil || radioBusy)
                    }
                }
                Toggle("Beim Start automatisch verbinden", isOn: Bindable(settings).rigAutoConnect)
            } header: {
                Text("Status")
            } footer: {
                if settings.rigLink == nil {
                    Text(missingHint)
                }
            }
        case .civDirect:
            Section {
                HStack(spacing: 8) {
                    switch civTest {
                    case .idle:
                        Text("Nicht geprüft").foregroundStyle(.secondary)
                    case .running:
                        ProgressView().controlSize(.small)
                        Text("Lese Frequenz …").foregroundStyle(.secondary)
                    case .ok(let text):
                        Circle().fill(.statusOK).frame(width: 9, height: 9)
                        Text(text)
                    case .failed(let text):
                        Circle().fill(.statusError).frame(width: 9, height: 9)
                        Text(text).foregroundStyle(.statusError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Verbindung testen") { testCIV() }
                        .disabled(
                            civTest == .running || radioBusy
                                || settings.ardopSerialPort.trimmingCharacters(in: .whitespaces)
                                    .isEmpty)
                }
            } header: {
                Text("Status")
            } footer: {
                Text("Der Test öffnet den Port kurz und liest Frequenz und Modus. Während einer Funk-Sitzung hält ardopcf den Port.")
            }
        case .none:
            EmptyView()
        }
    }

    private var isFailed: Bool {
        if case .failed = rig.status { return true }
        return false
    }

    private var statusColor: Color {
        switch rig.status {
        case .connected: .statusOK
        case .connecting: .statusBusy
        case .failed: .statusError
        case .disconnected: .secondary
        }
    }

    private var statusText: String {
        switch rig.status {
        case .disconnected:
            return String(localized: "Nicht verbunden")
        case .connecting:
            return String(localized: "Verbinde mit \(rig.rigName ?? String(localized: "Funkgerät")) …")
        case .failed(let message):
            return message
        case .connected:
            var parts = [rig.rigName ?? String(localized: "Funkgerät")]
            if let hz = rig.frequencyHz { parts.append("\(GatewayChannel.kilohertz(hz)) kHz") }
            if let mode = rig.modeName { parts.append(mode) }
            return parts.joined(separator: " · ")
        }
    }

    private var missingHint: String {
        switch settings.rigAccess {
        case .bundled:
            guard let profile = settings.rigProfile else {
                return String(localized: "Bitte Hersteller und Modell wählen.")
            }
            return profile.isNetworkRig
                ? String(localized: "Bitte die Adresse des Funkgeräts eintragen.")
                : String(localized: "Bitte den seriellen Port wählen.")
        case .external:
            return String(localized: "Bitte den Host des rigctld eintragen.")
        case .civDirect, .none:
            return ""
        }
    }

    private var accessHint: String {
        switch settings.rigAccess {
        case .bundled:
            String(localized: "Skywave startet den mitgelieferten rigctld (Hamlib) und hält die Verbindung zum Gerät. Andere Programme dürfen den seriellen Port dann nicht belegen.")
        case .none:
            String(localized: "Skywave spricht nicht mit dem Funkgerät. Frequenz und Modus stellst du von Hand ein.")
        case .external:
            String(localized: "Skywave dockt an einen rigctld an, den du oder ein anderes Programm gestartet hat.")
        case .civDirect:
            String(localized: "Das integrierte ardopcf tastet selbst über CI-V; Skywave nutzt denselben Port nur vor und nach der Sitzung. Nur Icom.")
        }
    }

    // MARK: - Anschluss

    @ViewBuilder private var connectionSection: some View {
        @Bindable var settings = settings
        let profile = settings.rigProfile
        let access = settings.rigAccess
        let needsSerial =
            access == .civDirect
            || (access == .bundled && profile?.needsSerialPort == true)
            || (access == .none && settings.ardopPTTMode == .rts)
        let showsCIV =
            access == .civDirect || (access == .bundled && profile?.usesCIVAddress == true)

        if needsSerial || access == .external || (access == .bundled && profile?.isNetworkRig == true)
        {
            Section("Anschluss") {
                if needsSerial {
                    Picker("Serieller Port", selection: $settings.ardopSerialPort) {
                        if settings.ardopSerialPort.isEmpty { Text("Bitte wählen").tag("") }
                        ForEach(serialPorts, id: \.self) { Text($0).tag($0) }
                    }
                    if access != .none {
                        TextField(
                            "Baudrate", value: $settings.ardopCATBaud,
                            format: .number.grouping(.never))
                    }
                }
                if showsCIV {
                    TextField("CI-V-Adresse (hex)", text: $settings.ardopCIVAddress)
                        .autocorrectionDisabled()
                }
                if access == .bundled, profile?.isNetworkRig == true {
                    TextField(
                        "Adresse des Funkgeräts", text: $settings.rigNetworkHost,
                        prompt: Text("192.168.1.20"))
                        .autocorrectionDisabled()
                }
                if access == .external {
                    TextField("Host", text: $settings.rigctldHost, prompt: Text("localhost"))
                        .autocorrectionDisabled()
                    TextField(
                        "Port", value: $settings.rigctldPort,
                        format: .number.grouping(.never))
                }
            }
            .disabled(radioBusy)
        }
    }

    // MARK: - PTT

    @ViewBuilder private var pttSection: some View {
        @Bindable var settings = settings
        Section {
            switch settings.rigAccess {
            case .bundled:
                Picker("PTT", selection: $settings.rigPTTViaCAT) {
                    Text("Über CAT").tag(true)
                    Text("Keine (VOX)").tag(false)
                }
            case .none:
                Picker("PTT", selection: $settings.ardopPTTMode) {
                    Text(ArdopPTTMode.rts.displayName).tag(ArdopPTTMode.rts)
                    Text(ArdopPTTMode.none.displayName).tag(ArdopPTTMode.none)
                }
            case .external:
                LabeledContent("PTT", value: String(localized: "über rigctld"))
            case .civDirect:
                LabeledContent("PTT", value: String(localized: "ardopcf über CI-V"))
            }
        } header: {
            Text("PTT")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if settings.rtsPTTBlockedBySandbox {
                    Label(
                        "RTS tastet mit dem integrierten ardopcf nicht: die App-Sandbox blockiert die Steuerleitung. Bitte über CAT oder VOX tasten.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.statusWarn)
                }
                Text("Gilt für ARDOP. VARA tastet den Sender selbst — CAT/PTT im VARA-Programm einstellen.")
            }
        }
        .disabled(radioBusy)
    }

    // MARK: - Aktionen

    /// Alles, was die Verbindung bestimmt — ändert es sich, wird getrennt.
    private var linkSignature: String {
        "\(settings.rigAccess.rawValue)|" + (settings.rigLink.map { "\($0.link)" } ?? "-")
            + "|\(settings.ardopSerialPort)|\(settings.ardopCATBaud)|\(settings.ardopCIVAddress)"
    }

    private func connect() {
        guard let target = settings.rigLink else { return }
        Task { await rig.connect(target.link, name: target.name) }
    }

    private func testCIV() {
        civTest = .running
        let port = settings.ardopSerialPort
        let baud = settings.ardopCATBaud
        let address = settings.civAddress
        Task {
            do {
                let civ = try await CIVClient.connect(
                    serialPort: port, baud: baud, radioAddress: address)
                do {
                    let hz = try await civ.frequency()
                    let mode = try await civ.operatingMode()
                    await civ.close()
                    civTest = .ok("\(GatewayChannel.kilohertz(hz)) kHz · \(mode)")
                } catch {
                    await civ.close()
                    civTest = .failed(
                        String(localized: "Das Funkgerät antwortet nicht an \(port) — CI-V-Adresse und Baudrate prüfen."))
                }
            } catch {
                civTest = .failed(String(localized: "Der Port \(port) lässt sich nicht öffnen: \(error.localizedDescription)"))
            }
        }
    }
}
