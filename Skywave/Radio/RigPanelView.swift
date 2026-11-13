import SwiftUI

/// Bereich «Funkgerät»: wo das Gerät steht, verbinden und trennen, Tune,
/// Sendepegel und der Pegel-Assistent. Eingerichtet wird das Gerät
/// weiterhin in den Einstellungen; hier wird es bedient.
struct RigPanelView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange
    @Environment(RigController.self) private var rig
    @Environment(MailboxCommandCenter.self) private var commands

    private var radioBusy: Bool { exchange.isRunning || exchange.isTuning }

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                Card(title: String(localized: "Gerät")) { deviceCard }
                Card(title: String(localized: "Senden")) { transmitCard }
                Card(title: String(localized: "Weg zum Gerät")) { linkCard }
            }
            .padding(20)
        }
        .navigationTitle("Funkgerät")
    }

    // MARK: - Gerät

    @ViewBuilder private var deviceCard: some View {
        switch settings.rigAccess {
        case .bundled, .external:
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(rig.rigName ?? settings.rigLink?.name ?? String(localized: "Funkgerät"))
                    .font(.headline)
                Text(statusWord)
                    .foregroundStyle(.secondary)
                if rig.status == .connecting {
                    ProgressView().controlSize(.small)
                }
            }
            if rig.isConnected, let hz = rig.frequencyHz {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(GatewayChannel.kilohertz(hz))
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                    Text("kHz")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                if let mode = rig.modeName {
                    Text(mode)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            if case .failed(let message) = rig.status {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.statusError)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if settings.rigLink == nil {
                Text("Noch nicht eingerichtet — Modell und Anschluss in den Einstellungen wählen.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if rig.isConnected {
                    Button("Trennen") { Task { await rig.disconnect() } }
                        .disabled(radioBusy)
                } else {
                    Button("Verbinden") { connect() }
                        .disabled(settings.rigLink == nil || radioBusy || rig.status == .connecting)
                }
            }
        case .civDirect:
            RigStatusLine()
            Text("ardopcf tastet auf diesem Weg selbst und hält den Port während der Sitzung. Frequenz und Modus zeigt Skywave hier nicht laufend an; «Verbindung testen» steht in den Einstellungen.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .none:
            RigStatusLine()
            Text("Ohne CAT stellt Skywave die Frequenz nicht ein und zeigt sie nicht an.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusColor: Color {
        switch rig.status {
        case .connected: .statusOK
        case .connecting: .statusBusy
        case .failed: .statusError
        case .disconnected: .secondary
        }
    }

    private var statusWord: String {
        switch rig.status {
        case .connected: "verbunden"
        case .connecting: String(localized: "verbindet …")
        case .failed: String(localized: "Fehler")
        case .disconnected: String(localized: "nicht verbunden")
        }
    }

    private func connect() {
        guard let target = settings.rigLink else { return }
        Task { await rig.connect(target.link, name: target.name) }
    }

    // MARK: - Senden

    @ViewBuilder private var transmitCard: some View {
        if settings.ardopUseBundled || exchange.canAdjustDriveLevel {
            DriveLevelControl()
        }
        HStack {
            TuneButton()
            Button("Pegel-Assistent …") {
                commands.send(.levelAssistant)
            }
            .disabled(!settings.ardopUseBundled || radioBusy)
            .help("Sendet einen Zweiton und stellt den Pegel gegen die ALC des Geräts ein")
            if exchange.isManualTuning {
                Label("SENDET", systemImage: "dot.radiowaves.up.forward")
                    .font(.callout.bold())
                    .foregroundStyle(.statusError)
            }
        }
        Text(
            settings.ardopUseBundled
                ? "Tune tastet den Sender für höchstens 15 s mit einem Zweiton — nur auf freier Frequenz oder in die Kunstlast. Der Assistent stellt den Pegel anhand von ALC und Leistung ein."
                : "Tune und Pegel-Assistent brauchen das integrierte ardopcf (Einstellungen → Modem)."
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Weg

    @ViewBuilder private var linkCard: some View {
        @Bindable var settings = settings
        let port = settings.ardopSerialPort.trimmingCharacters(in: .whitespaces)

        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text("Steuerung").foregroundStyle(.secondary)
                Text(settings.rigAccess.displayName)
            }
            if settings.rigAccess == .external {
                GridRow {
                    Text("rigctld").foregroundStyle(.secondary)
                    Text("\(settings.rigctldHost):\(String(settings.rigctldPort))")
                        .monospacedDigit()
                }
            } else if !port.isEmpty, settings.rigAccess != .none || settings.ardopPTTMode == .rts {
                GridRow {
                    Text("Anschluss").foregroundStyle(.secondary)
                    Text(
                        settings.rigAccess == .none
                            ? port : "\(port) · \(String(settings.ardopCATBaud)) Baud"
                    )
                    .monospacedDigit()
                    .textSelection(.enabled)
                }
            }
        }
        if settings.rigAccess == .bundled || settings.rigAccess == .external {
            Toggle("Beim Start automatisch verbinden", isOn: $settings.rigAutoConnect)
        }
        if settings.rtsPTTBlockedBySandbox {
            Label(
                "RTS tastet mit dem integrierten ardopcf nicht: die App-Sandbox blockiert die Steuerleitung.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.statusWarn)
            .fixedSize(horizontal: false, vertical: true)
        }
        SettingsLink {
            Text("In den Einstellungen ändern …")
        }
    }
}
