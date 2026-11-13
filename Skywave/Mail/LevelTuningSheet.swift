// Der Pegel-Assistent stammt aus HAM-Tools. Skywave nutzt Systemfarben
// (folgt der System-Erscheinung), die Messwerte kommen aus dem rigctld.
import SwiftUI
import WinlinkKit

/// Der Pegel-Assistent: sendet einen Zweiton und regelt den Sendepegel
/// so ein, dass die ALC des Funkgeräts gerade eben anspricht.
///
/// Der Vorgang tastet den Sender — deshalb steht die Warnung vor dem
/// Start und nicht im Kleingedruckten, und ein Abbruch ist jederzeit
/// erreichbar.
struct LevelTuningSheet: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange
    @Environment(\.dismiss) private var dismiss

    @State private var controller: LevelTuningController?
    @State private var startError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    warning
                    if let controller {
                        liveReadout(controller)
                        measurements(controller)
                    } else {
                        explanation
                    }
                    if let startError {
                        Label(startError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.statusWarn)
                    }
                }
                .padding(16)
            }
            Divider()
            buttons
        }
        .frame(width: 520, height: 560)
    }

    private var header: some View {
        HStack {
            Label("Sendepegel einstellen", systemImage: "waveform")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(12)
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.statusWarn)
            Text("Der Assistent **sendet** — mehrere Sekunden je Stufe. Nur auf einer freien Frequenz oder in die Kunstlast, und mit angeschlossener Antenne bzw. Dummy-Load.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("So läuft es ab")
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            Text("Der Assistent sendet einen Zweiton und erhöht den Pegel Stufe für Stufe, bis die ALC-Anzeige des Geräts anspricht. Übernommen wird die Stufe **darunter** — dort greift die Regelung noch nicht, und genau das ist das Ziel: Was die ALC begrenzt, verzerrt sie auch. Jede Stufe dauert fünf Sekunden, der ganze Durchlauf also bis zu einer Minute.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !canMeasureLikely {
                Text("Für dieses Setup kann die ALC nicht gelesen werden — der Assistent sendet den Ton, die ALC liest du am Gerät ab. Messen geht über rigctld oder, bei PTT über VOX, über CI-V; bei PTT über CI-V oder RTS hält ardopcf den seriellen Port, dann kommt Skywave nicht ans Gerät.")
                    .font(.caption)
                    .foregroundStyle(.statusWarn)
            }
            LabeledContent("Aktueller Pegel:") {
                Text("\(settings.ardopDriveLevel) %").monospacedDigit()
            }
            .font(.callout)
        }
    }

    private func liveReadout(_ controller: LevelTuningController) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.phase {
            case .idle:
                Text("Bereit.").foregroundStyle(.secondary)
            case .starting:
                Label("Modem startet …", systemImage: "hourglass")
            case .measuring(let level):
                Label("Sendet bei \(String(level)) % …", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.statusWarn)
            case .finished(let level):
                VStack(alignment: .leading, spacing: 4) {
                    Label("Empfehlung: \(String(level)) %", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.statusOK)
                    // Die Leistung bei diesem Pegel ist der eigentliche
                    // Beleg: volle Leistung bei ruhiger ALC.
                    if let watts = wattsAt(level: level, in: controller) {
                        Text("Volle Leistung bei ruhiger ALC — \(String(format: "%.1f W", watts)) gemessen.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .rigInputTooLow(let peak):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Der Pegel reicht nicht aus", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.statusWarn)
                    Text(rigInputAdvice(peak))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.statusWarn)
            }
            HStack(spacing: 20) {
                readout("ALC", controller.currentALC.map { String(format: "%.2f", $0) })
                readout("Leistung", controller.currentWatts.map { String(format: "%.1f W", $0) })
            }
        }
        .font(.callout)
        .foregroundStyle(.primary)
    }

    /// Gemessene Leistung bei einem Pegel aus der Messreihe.
    private func wattsAt(level: Int, in controller: LevelTuningController) -> Double? {
        controller.samples.first { $0.level == level }?.watts
    }

    /// Was zu tun ist, wenn die ALC bis zum vollen Pegel schweigt: Dann
    /// kommt beim Gerät zu wenig NF an, und daran ändert der Regler in
    /// der App nichts mehr.
    private func rigInputAdvice(_ peakWatts: Double?) -> String {
        let reached = peakWatts.map { String(format: "%.1f W", $0) }
            ?? String(localized: "unbekannt")
        return String(localized: "Die ALC hat bis 100 % nicht angesprochen — erreicht wurden \(reached). Liegt das deutlich unter der Leistung, die am Gerät eingestellt ist, kommt zu wenig NF an: Dann ist der Eingangspegel im Funkgerät zu niedrig (bei Icom «USB MOD Level» unter MENU ▸ SET ▸ Connectors). Dort anheben, bis die Leistung stimmt, und erneut messen — der Regler hier bleibt so lange wirkungslos.")
    }

    private func readout(_ title: LocalizedStringKey, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "—").monospacedDigit()
        }
    }

    @ViewBuilder
    private func measurements(_ controller: LevelTuningController) -> some View {
        if !controller.samples.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Messungen")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                ForEach(controller.samples) { sample in
                    HStack {
                        Text("\(sample.level) %").monospacedDigit().frame(width: 50, alignment: .leading)
                        Text(sample.alc.map { String(format: "ALC %.2f", $0) } ?? "ALC —")
                            .monospacedDigit()
                        Spacer()
                        Text(sample.watts.map { String(format: "%.1f W", $0) } ?? "—")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            if let controller, case .finished(let level) = controller.phase {
                Button("\(String(level)) % übernehmen") {
                    settings.ardopDriveLevel = level
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
            if controller?.isRunning == true {
                Button("Abbrechen", role: .destructive) { controller?.stop() }
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Schliessen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // Bewusst ohne Return-Kürzel: der Start tastet den Sender,
                // das soll nicht versehentlich beim Öffnen passieren.
                Button("Messung starten") { start() }
                    .disabled(exchange.isRunning || exchange.isTuning)
                    .help(
                        exchange.isRunning
                            ? "Eine Winlink-Sitzung läuft — die Messung startet erst danach."
                            : exchange.isTuning
                                ? "Tune läuft im Hauptfenster — zuerst dort beenden."
                                : "Startet den Zweiton — der Sender wird getastet.")
            }
        }
        .padding(12)
    }

    /// Die Messquelle dieses Laufs. Sie steht erst fest, wenn das Modem
    /// aufgebaut ist — welcher Weg misst, hängt davon ab, wer den
    /// seriellen Port hält.
    @State private var sessionBox = SessionBox()

    @Observable final class SessionBox {
        var readALC: () async -> Float? = { nil }
        var readWatts: () async -> Double? = { nil }
        var canMeasure = false
    }

    /// Ob dieses Setup voraussichtlich messen kann — vor dem Start, nur
    /// aus den Einstellungen abgeleitet.
    private var canMeasureLikely: Bool {
        if settings.rigctldEnabled || settings.rigUseBundled { return true }
        return settings.ardopPTTMode == .none && !settings.ardopSerialPort.isEmpty
    }

    private func start() {
        startError = nil
        let box = sessionBox
        let tuner = LevelTuningController(
            measurable: { box.canMeasure },
            readALC: { await box.readALC() },
            readWatts: { await box.readWatts() }
        ) {
            let session = try await exchange.makeTuningSession(settings: settings)
            box.readALC = session.readALC
            box.readWatts = session.readWatts
            box.canMeasure = session.canMeasure
            return (session.modem, {
                box.canMeasure = false
                await session.teardown()
            })
        }
        controller = tuner
        tuner.start()
    }
}
