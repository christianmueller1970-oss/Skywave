import SwiftUI
import WinlinkKit

/// The app settings window (Skywave ▸ Einstellungen…, ⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("Allgemein", systemImage: "gearshape")
                }
            RigSettingsView()
                .tabItem {
                    Label("Funkgerät", systemImage: "dial.medium")
                }
            RadioSettingsView()
                .tabItem {
                    Label("Modem", systemImage: "antenna.radiowaves.left.and.right")
                }
            SignatureSettingsView()
                .tabItem {
                    Label("Signaturen", systemImage: "signature")
                }
        }
        .frame(width: 480)
    }
}

/// Station, account and connection settings.
private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange

    @State private var password = ""
    @State private var language = AppLanguage.selected()

    /// An empty locator is fine — it is optional for mail. Only a
    /// non-empty malformed one is worth a warning.
    private var locatorLooksValid: Bool {
        settings.locator.isEmpty || Maidenhead.isValid(settings.locator)
    }

    private var relaunchBlocked: Bool {
        AppRelauncher.isBlocked(
            isRunning: exchange.isRunning, isTuning: exchange.isTuning,
            isManualTuning: exchange.isManualTuning)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Rufzeichen", text: $settings.callsign, prompt: Text("HB9XYZ"))
                    .autocorrectionDisabled()
                HStack {
                    TextField("Locator", text: $settings.locator, prompt: Text("JN47PN"))
                        .autocorrectionDisabled()
                    // Only a warning, never a block: the field is typed
                    // character by character, so half a locator is a
                    // normal intermediate state.
                    if !locatorLooksValid {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.statusWarn)
                            .help("Kein gültiger Maidenhead-Locator (4, 6 oder 8 Zeichen, z. B. JN47PN)")
                            .accessibilityLabel("Locator unvollständig")
                    }
                }
            } header: {
                Text("Station")
            } footer: {
                if !locatorLooksValid {
                    Text(
                        "Ohne gültigen Locator wird die Gateway-Liste nicht aktualisiert — sie braucht ihn, um die Entfernung zu berechnen.")
                }
            }

            Section {
                Toggle(
                    "Gateway-Liste täglich aktualisieren",
                    isOn: $settings.gatewayRefreshEnabled)
                Picker("Suchradius", selection: $settings.gatewayMaxDistanceKm) {
                    ForEach([300, 500, 800, 1500, 3000], id: \.self) { km in
                        Text("\(km) km").tag(km)
                    }
                }
            } header: {
                Text("Gateway-Verzeichnis")
            } footer: {
                Text("""
                    Die Liste der RMS-Gateways kommt von den Winlink Web Services und \
                    wird höchstens einmal täglich abgerufen — Winlink verlangt sparsame \
                    Nutzung. Ohne Verbindung gilt der lokale Zwischenspeicher. \
                    Fenster: Ablage ▸ Gateways (⇧⌘G).
                    """)
            }

            Section {
                SecureField("Passwort", text: $password)
                    .onChange(of: password) { _, new in
                        Keychain.setPassword(new)
                    }
            } header: {
                Text("Winlink-Konto")
            } footer: {
                Text("Das Passwort deines Winlink-Kontos (winlink.org). Es wird ausschliesslich im Schlüsselbund gespeichert.")
            }

            Section {
                TextField("CMS-Host", text: $settings.cmsHost)
                    .autocorrectionDisabled()
                TextField("Port", value: $settings.cmsPort, format: .number.grouping(.never))
            } header: {
                Text("Verbindung")
            } footer: {
                Text("""
                    Standard ist \(SettingsKeys.defaultCMSHost) (Produktion). \
                    Zum Testen ohne echte Zustellung: \(SettingsKeys.testCMSHost) — \
                    Achtung, das ist ein isolierter Testserver. Er nimmt Nachrichten an, \
                    stellt sie aber nicht zu.
                    """)
            }

            Section {
                Toggle("Automatisch abrufen", isOn: $settings.autoFetchEnabled)
                if settings.autoFetchEnabled {
                    Picker("Intervall", selection: $settings.autoFetchIntervalMinutes) {
                        Text("Alle 15 Minuten").tag(15)
                        Text("Alle 30 Minuten").tag(30)
                        Text("Stündlich").tag(60)
                        Text("Alle 2 Stunden").tag(120)
                    }
                }
                MenuBarToggle()
            } header: {
                Text("Abruf")
            } footer: {
                Text("""
                    Ruft im Hintergrund über Telnet (Internet) ab und meldet neue \
                    Nachrichten als Mitteilung. Funkverbindungen startet der \
                    Auto-Abruf nie.
                    """)
            }

            Section {
                Picker("Sprache", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName).tag(language)
                    }
                }
                .onChange(of: language) { _, new in
                    AppLanguage.select(new)
                }
                if language != AppLanguage.active {
                    LabeledContent("Die Änderung gilt nach einem Neustart.") {
                        Button("Jetzt neu starten") {
                            AppRelauncher.relaunch()
                        }
                        .controlSize(.small)
                        .disabled(relaunchBlocked)
                    }
                }
            } header: {
                Text("Sprache")
            } footer: {
                if language != AppLanguage.active, relaunchBlocked {
                    Text("Ein Neustart ist erst möglich, wenn Sitzung, Tune und Pegel-Assistent beendet sind.")
                }
            }

            Section {
                if let root = app.workspace?.root {
                    LabeledContent("Ordner") {
                        HStack {
                            Text(root.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button("Im Finder zeigen") {
                                NSWorkspace.shared.activateFileViewerSelecting([root])
                            }
                            .controlSize(.small)
                        }
                    }
                }
                Button("Ordner ändern …") {
                    app.chooseFolder()
                }
            } header: {
                Text("Speicherort")
            } footer: {
                Text("""
                    Nachrichten, Adressbuch, Signaturen und Einstellungen liegen als \
                    normale Dateien in diesem Ordner. Beim Wechsel werden die Daten in \
                    den neuen Ordner kopiert; der bisherige bleibt als Kopie erhalten.
                    """)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            password = Keychain.password() ?? ""
        }
    }
}

/// Der Menüleisten-Schalter lebt in UserDefaults (siehe SkywaveApp),
/// darum ein eigener kleiner View mit @AppStorage statt Settings-Store.
private struct MenuBarToggle: View {
    @AppStorage("showMenuBarStatus") private var showMenuBarStatus = true

    var body: some View {
        Toggle("Status in der Menüleiste anzeigen", isOn: $showMenuBarStatus)
    }
}

/// Radio modem endpoints (VARA, ARDOP) and optional rigctld PTT.
/// Gateway and bandwidth are chosen per connection in the dialog.
private struct RadioSettingsView: View {
    @Environment(AppSettingsStore.self) private var settings

    @State private var captureDevices = [String]()
    @State private var playbackDevices = [String]()

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Host", text: $settings.varaHost)
                    .autocorrectionDisabled()
                TextField(
                    "Command-Port", value: $settings.varaCommandPort,
                    format: .number.grouping(.never))
                TextField(
                    "Data-Port", value: $settings.varaDataPort,
                    format: .number.grouping(.never))
            } header: {
                Text("VARA")
            } footer: {
                Text("""
                    Das VARA-HF- bzw. VARA-FM-Programm muss laufen und auf diesen \
                    Ports erreichbar sein (Standard: localhost, 8300/8301). VARA \
                    tastet den Sender selbst — CAT/PTT im VARA-Programm konfigurieren.
                    """)
            }

            Section {
                Picker("TNC", selection: $settings.ardopUseBundled) {
                    Text("Integriert (ardopcf)").tag(true)
                    Text("Extern").tag(false)
                }
                .pickerStyle(.segmented)

                if settings.ardopUseBundled {
                    Picker("Audio-Eingang (vom TRX)", selection: $settings.ardopCaptureDevice) {
                        Text("Systemstandard").tag("")
                        ForEach(captureDevices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Picker("Audio-Ausgang (zum TRX)", selection: $settings.ardopPlaybackDevice) {
                        Text("Systemstandard").tag("")
                        ForEach(playbackDevices, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    LabeledContent("Sendepegel") {
                        HStack(spacing: 10) {
                            Slider(
                                value: Binding(
                                    get: { Double(settings.ardopDriveLevel) },
                                    set: { settings.ardopDriveLevel = Int($0.rounded()) }),
                                in: 0...100, step: 5)
                            .frame(maxWidth: 200)
                            Text("\(settings.ardopDriveLevel) %")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                    Text("Skaliert die NF, die ans Funkgerät geht. Zu viel übersteuert den Modulator und kostet Verbindungen — im Datenbetrieb (USB-D) fehlt die Mikrofonkette, die das sonst abfängt. Richtwert: so weit herunter, dass die ALC-Anzeige am Gerät gerade eben anspricht.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tune und Pegel-Assistent stehen im Hauptfenster unter Funk → Funkgerät.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !settings.rigctldEnabled {
                        // Ohne rigctld fehlt die Messgroesse: ALC ueber CI-V
                        // kann das Kit (noch) nicht.
                        Text("Automatisch messen kann der Assistent nur über rigctld — bei PTT über CI-V sendet er den Ton, und du liest die ALC am Gerät ab.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField("Host", text: $settings.ardopHost)
                        .autocorrectionDisabled()
                    TextField(
                        "Control-Port", value: $settings.ardopControlPort,
                        format: .number.grouping(.never))
                    TextField(
                        "Data-Port", value: $settings.ardopDataPort,
                        format: .number.grouping(.never))
                }

                Text("PTT, serieller Port und QSY stehen im Tab «Funkgerät».")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("ARDOP")
            } footer: {
                if settings.ardopUseBundled {
                    Text("""
                        Skywave startet das mitgelieferte ardopcf-Modem selbst — es \
                        braucht nur das USB-Kabel zum Funkgerät (IC-7610: eine \
                        USB-Verbindung liefert Audio und CI-V, Standard-Adresse 98). \
                        Beim ersten Verbinden fragt macOS nach der Mikrofon-Freigabe.
                        """)
                } else {
                    Text("""
                        Der ARDOP-TNC muss laufen und auf diesen Ports erreichbar sein \
                        (Standard: localhost, 8515/8516).
                        """)
                }
            }

            Section {
                Picker("Grösste Nachricht", selection: $settings.radioInboundMaxKB) {
                    ForEach(AppSettingsStore.radioInboundLimitsKB, id: \.self) { kb in
                        Text(kb == 0 ? "Unbegrenzt" : "\(kb) kB").tag(kb)
                    }
                }
            } header: {
                Text("Empfang über Funk")
            } footer: {
                Text("""
                    Grössere Nachrichten werden über Funk zurückgestellt — das CMS \
                    bietet sie beim nächsten Austausch wieder an, zum Beispiel über \
                    Internet. Was im Postausgang über welchen Weg raus darf, legst du \
                    je Nachricht über «Versandweg» fest.
                    """)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Keep a stored selection visible even when its device is
            // currently unplugged, so the Picker does not lose it.
            captureDevices = including(
                settings.ardopCaptureDevice, in: AudioDeviceCatalog.deviceNames(input: true))
            playbackDevices = including(
                settings.ardopPlaybackDevice, in: AudioDeviceCatalog.deviceNames(input: false))
        }
    }

    private func including(_ stored: String, in list: [String]) -> [String] {
        stored.isEmpty || list.contains(stored) ? list : list + [stored]
    }
}

/// Manage signatures: list on the left, editor on the right. The
/// default signature is inserted into every new message.
private struct SignatureSettingsView: View {
    @Environment(SignatureStore.self) private var signatures

    @State private var selectedID: Signature.ID?

    private var selectedSignature: Signature? {
        signatures.signatures.first { $0.id == selectedID }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(signatures.signatures, selection: $selectedID) { signature in
                    HStack {
                        Text(signature.name)
                            .lineLimit(1)
                        Spacer()
                        if signature.id == signatures.defaultID {
                            Text("Standard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(signature.id)
                }
                .listStyle(.plain)

                Divider()
                HStack(spacing: 0) {
                    Button {
                        selectedID = signatures.add().id
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .help("Neue Signatur anlegen")
                    Button {
                        if let signature = selectedSignature {
                            signatures.remove(signature)
                            selectedID = signatures.signatures.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .disabled(selectedSignature == nil)
                    .help("Signatur löschen")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 160)

            Divider()

            if let signature = selectedSignature {
                SignatureForm(signature: signature)
            } else {
                ContentUnavailableView(
                    "Keine Signatur",
                    systemImage: "signature",
                    description: Text("Lege mit «+» eine Signatur an. Die Standard-Signatur wird in jede neue Nachricht eingefügt.")
                )
            }
        }
        .frame(height: 320)
        .onAppear {
            selectedID = signatures.defaultID ?? signatures.signatures.first?.id
        }
    }
}

/// Edits one signature; every change is written back to the store
/// immediately.
private struct SignatureForm: View {
    @Environment(SignatureStore.self) private var signatures

    let signature: Signature

    @State private var draft = Signature()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $draft.name)
            TextEditor(text: $draft.text)
                .font(.body.monospaced())
                .overlay(alignment: .topLeading) {
                    if draft.text.isEmpty {
                        Text("73 de HB9XYZ\nRené, Amriswil")
                            .font(.body.monospaced())
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            Toggle(
                "Als Standard-Signatur verwenden",
                isOn: Binding(
                    get: { signatures.defaultID == signature.id },
                    set: { signatures.setDefault($0 ? draft : nil) }
                ))
        }
        .padding(12)
        .onAppear { draft = signature }
        .onChange(of: signature.id) { draft = signature }
        .onChange(of: draft) {
            guard draft.id == signature.id, draft != signature else { return }
            signatures.update(draft)
        }
    }
}
