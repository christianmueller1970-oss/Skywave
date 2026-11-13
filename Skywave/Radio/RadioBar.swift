import AppKit
import SwiftUI

/// Die Funk-Leiste am unteren Rand des Hauptfensters, immer sichtbar:
/// links das Funkgerät, in der Mitte der Stand der Sitzung, rechts
/// Sendepegel, Tune und das Protokoll.
struct RadioBar: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange
    @Environment(AppNavigation.self) private var nav

    @Binding var showingLog: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                nav.show(.rig)
            } label: {
                RigStatusLine(compact: true)
                    .font(.caption.monospacedDigit())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .help("Funkgerät — öffnet den Bereich «Funkgerät»")

            Divider().frame(height: 14)
            sessionStatus
            Spacer(minLength: 8)

            if exchange.isStoppingManualTune {
                Text("Beende …")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if exchange.isManualTuning {
                Label("SENDET", systemImage: "dot.radiowaves.up.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.statusError)
            }
            // Mit externem TNC gibt es kein Tune, der Pegel lässt sich aber
            // während der Sitzung trotzdem nachstellen.
            if settings.ardopUseBundled || exchange.canAdjustDriveLevel {
                DriveLevelControl(compact: true)
            }
            if settings.ardopUseBundled {
                TuneButton()
                    .controlSize(.small)
            }
            if exchange.canAbort {
                Button("Abbrechen", role: .destructive) {
                    exchange.abortExchange()
                }
                .controlSize(.small)
                .help("Sitzung abbrechen (⌘.)")
            }
            Button("Protokoll") {
                showingLog = true
            }
            .controlSize(.small)
            .disabled(exchange.log.isEmpty)
            .popover(isPresented: $showingLog, arrowEdge: .bottom) {
                LiveSessionLogView(lines: exchange.log)
            }
            .help("Protokoll der Sitzung (⇧⌘L)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Stand der Sitzung: läuft sie, mit Weg und letzter Protokollzeile;
    /// danach die Zusammenfassung; sonst «Bereit».
    @ViewBuilder private var sessionStatus: some View {
        if exchange.isRunning {
            ProgressView()
                .controlSize(.mini)
            if let path = exchange.activePath {
                // Der Weg bleibt die ganze Sitzung über sichtbar —
                // Funk und Internet sehen im Protokoll sonst gleich aus.
                Label(path.displayName, systemImage: path.symbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(path.isRadio ? .statusWarn : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                    .lineLimit(1)
            }
            Text(exchange.log.last ?? String(localized: "Austausch läuft …"))
                .lineLimit(1)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        } else if let summary = exchange.summary {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.statusOK)
            Text(summary)
                .font(.caption)
                .lineLimit(1)
        } else {
            Text("Bereit")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Sendepegel des ARDOP-Modems. Der Wert landet in den Einstellungen und
/// gilt damit auch für die nächste Sitzung; läuft gerade eine
/// ARDOP-Sitzung oder der Hand-Tune, wirkt er sofort am Modem.
struct DriveLevelControl: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange

    /// Kurzform für die Funk-Leiste.
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Text(compact ? "Pegel" : "Sendepegel")
                .font(compact ? .caption : .body)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(settings.ardopDriveLevel) },
                    set: { settings.ardopDriveLevel = Int($0.rounded()) }),
                in: 0...100, step: 5
            )
            .controlSize(compact ? .small : .regular)
            .frame(minWidth: 90, maxWidth: compact ? 180 : 320)
            .onChange(of: settings.ardopDriveLevel) { _, level in
                exchange.applyDriveLevel(level)
            }
            Text("\(settings.ardopDriveLevel) %")
                .font(compact ? .caption.monospacedDigit() : .body.monospacedDigit())
                .frame(width: compact ? 38 : 48, alignment: .trailing)
        }
        .help(
            "Sendepegel des ARDOP-Modems — so einstellen, dass die ALC am Gerät gerade eben anspricht. Gilt sofort und für die nächste Sitzung.")
    }
}

/// «Tune»: Zweiton für höchstens 15 s am integrierten ardopcf.
struct TuneButton: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange

    /// Ob Tune gerade starten darf. Internal: Test-Naht.
    static func isBlocked(
        isManualTuning: Bool, isRunning: Bool, isTuning: Bool, usesBundledModem: Bool
    ) -> Bool {
        !isManualTuning && (isRunning || isTuning || !usesBundledModem)
    }

    var body: some View {
        Button(exchange.isManualTuning ? "Tune aus" : "Tune") {
            exchange.toggleManualTune(settings: settings)
        }
        .disabled(
            Self.isBlocked(
                isManualTuning: exchange.isManualTuning, isRunning: exchange.isRunning,
                isTuning: exchange.isTuning, usesBundledModem: settings.ardopUseBundled)
                || exchange.isStoppingManualTune
        )
        .help(
            "Zweiton für höchstens 15 s, zum Einstellen von Pegel und ALC. Nur auf freier Frequenz oder in die Kunstlast.")
    }
}

/// Das Protokoll der laufenden oder letzten Sitzung, für Neugierige (und
/// zur Fehlersuche).
struct LiveSessionLogView: View {
    let lines: [String]

    private var joined: String { lines.joined(separator: "\n") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                }
                Spacer()
                Button {
                    NSWorkspace.shared.open(SessionLogStore.logsDirectory)
                } label: {
                    Label("Im Finder zeigen", systemImage: "folder")
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            // One selectable text block so the whole log can be dragged
            // across and copied — per-line Text views can't be.
            ScrollView {
                Text(joined)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 520, height: 360)
    }
}
