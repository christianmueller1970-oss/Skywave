import MapKit
import SwiftUI
import WinlinkKit

/// Fenster «Positionsmeldung»: Rufzeichen, Standortquelle mit sichtbarer
/// Genauigkeit, kleine Karte zur Kontrolle, UTC-Zeit und Kommentar.
/// «In Postausgang legen» erzeugt die Winlink-Meldung an QTH; sie geht
/// beim nächsten Austausch mit — Versandweg wie jede andere Nachricht.
struct PositionReportView: View {
    @Environment(MailStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.finishSection) private var finishSection

    @State private var source: PositionSource = .locator
    @State private var manualLatitude = ""
    @State private var manualLongitude = ""
    @State private var comment = ""
    @State private var location = LocationProvider()
    @State private var camera: MapCameraPosition = .automatic
    @State private var errorMessage: String?
    @State private var now = Date()

    private var mycall: String { settings.effectiveCallsign }

    private var resolved: ResolvedPosition? {
        switch source {
        case .locator:
            PositionResolver.fromLocator(settings.locator)
        case .manual:
            PositionResolver.fromManual(latitude: manualLatitude, longitude: manualLongitude)
        case .locationService:
            location.fix.map {
                PositionResolver.fromService(
                    latitude: $0.latitude, longitude: $0.longitude,
                    accuracyMeters: $0.accuracyMeters, timestamp: $0.timestamp)
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        resolved.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private static let utcFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Rufzeichen", value: mycall.isEmpty ? "—" : mycall)
                    LabeledContent("Zeit (UTC)", value: Self.utcFormatter.string(from: now))

                    Picker("Standortquelle", selection: $source) {
                        ForEach(PositionSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch source {
                    case .locator:
                        LabeledContent("Locator", value: settings.locator.isEmpty ? "—" : settings.locator)
                        if settings.locator.isEmpty {
                            Text("Kein Locator hinterlegt — Einstellungen (⌘,) → Allgemein.")
                                .font(.caption)
                                .foregroundStyle(.statusWarn)
                        }
                    case .manual:
                        TextField("Breite (Dezimalgrad)", text: $manualLatitude, prompt: Text("47.5483"))
                        TextField("Länge (Dezimalgrad)", text: $manualLongitude, prompt: Text("9.2955"))
                        Text("Nord und Ost positiv, Süd und West negativ. Komma oder Punkt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case .locationService:
                        HStack {
                            Button(location.fix == nil ? "Standort ermitteln" : "Erneut ermitteln") {
                                location.request()
                            }
                            .disabled(location.isRequesting)
                            if location.isRequesting {
                                ProgressView().controlSize(.small)
                            }
                        }
                        if let error = location.errorText {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.statusWarn)
                        }
                    }

                    if let resolved {
                        LabeledContent("Position", value: resolved.coordinateText)
                        LabeledContent("Genauigkeit", value: resolved.accuracyText)
                    } else {
                        Text(missingPositionText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Standort")
                }

                Section {
                    if let coordinate {
                        Map(position: $camera) {
                            Marker(mycall.isEmpty ? "Position" : mycall, coordinate: coordinate)
                        }
                        .mapStyle(.standard(elevation: .flat))
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        ContentUnavailableView(
                            "Keine Position", systemImage: "map",
                            description: Text("Die Karte zeigt den Punkt, sobald eine Position vorliegt.")
                        )
                        .frame(height: 180)
                    }
                } footer: {
                    Text("Ohne Internet bleibt die Karte leer; die Koordinaten oben gelten trotzdem.")
                }

                Section {
                    TextField("Kommentar", text: $comment, prompt: Text("QRV, alles OK"), axis: .vertical)
                        .lineLimit(2...3)
                    HStack {
                        Spacer()
                        Text("\(comment.count)/\(PositionReport.commentLimit)")
                            .font(.caption)
                            .foregroundStyle(
                                comment.count > PositionReport.commentLimit ? .statusWarn : .secondary)
                    }
                } header: {
                    Text("Kommentar")
                } footer: {
                    Text("""
                        Die Meldung geht als Nachricht an QTH in den Postausgang und erscheint \
                        nach dem Austausch auf winlink.org/userPositions.
                        """)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                // Im Hauptfenster gibt es nichts zu schliessen.
                if finishSection == nil {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                Button("In Postausgang legen") { queue() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(resolved == nil || mycall.isEmpty)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 460)
        .onAppear(perform: prefill)
        .onChange(of: coordinate?.latitude) { _, _ in recenter() }
        .onChange(of: coordinate?.longitude) { _, _ in recenter() }
        .onChange(of: source) { _, newValue in settings.positionSource = newValue }
        .alert(
            "Positionsmeldung nicht möglich",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var missingPositionText: String {
        switch source {
        case .locator: String(localized: "Kein gültiger Locator.")
        case .manual: String(localized: "Breite und Länge als Dezimalgrad eingeben.")
        case .locationService: String(localized: "Noch kein Standort ermittelt.")
        }
    }

    private func prefill() {
        now = Date()
        source = settings.positionSource
        if let lat = settings.manualLatitude, let lon = settings.manualLongitude {
            manualLatitude = String(format: "%.5f", lat)
            manualLongitude = String(format: "%.5f", lon)
        }
        recenter()
    }

    private func recenter() {
        guard let coordinate else { return }
        camera = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.12)))
    }

    private func queue() {
        guard let resolved else { return }
        if source == .manual {
            settings.manualLatitude = resolved.latitude
            settings.manualLongitude = resolved.longitude
        }
        let report = PositionResolver.report(position: resolved, comment: comment)
        Task {
            do {
                try await store.queue(report.message(mycall: mycall))
                if let finishSection { finishSection.run() } else { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
