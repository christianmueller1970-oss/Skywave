import SwiftUI
import WinlinkKit

/// Assistent für Saildocs-GRIB-Anfragen: Gebiet (um den Locator
/// vorbelegt), Modell, Auflösung, Vorhersagestunden und Parameter.
/// Erzeugt die Spezifikation und öffnet damit ein Compose-Fenster —
/// der Nutzer sieht die Anfrage vor dem Absenden.
struct GRIBAssistantView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.finishSection) private var finishSection

    @State private var model = CatalogRequest.GRIBSpec.Model.gfs
    @State private var north = ""
    @State private var south = ""
    @State private var west = ""
    @State private var east = ""
    @State private var resolution = 0.5
    @State private var hours: Set<Int> = [0, 24, 48, 72]
    @State private var parameters: Set<String> = ["PRMSL", "WIND"]

    static let hourChoices = [0, 6, 12, 24, 36, 48, 72, 96, 120]

    private var spec: CatalogRequest.GRIBSpec? {
        guard let n = PositionResolver.parseDegrees(north),
            let s = PositionResolver.parseDegrees(south),
            let w = PositionResolver.parseDegrees(west),
            let e = PositionResolver.parseDegrees(east)
        else { return nil }
        let spec = CatalogRequest.GRIBSpec(
            model: model, north: n, south: s, west: w, east: e, resolution: resolution,
            hours: hours.sorted(),
            parameters: CatalogRequest.GRIBSpec.commonParameters.filter(parameters.contains))
        return (try? spec.validate()) == nil ? nil : spec
    }

    /// Grober Richtwert: Gitterpunkte × Zeitpunkte × Parameter, rund
    /// 2 Bytes je Wert nach Kompression — damit niemand 2 MB über
    /// 80 m anfordert.
    private var sizeHint: String? {
        guard let spec else { return nil }
        let points =
            ((spec.north - spec.south) / spec.resolution + 1)
            * ((spec.east - spec.west) / spec.resolution + 1)
        let bytes = Int(points) * spec.hours.count * spec.parameters.count * 2
        return String(localized: "Grössenordnung \(SessionMailbox.kilobytes(bytes)) kB")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Modell", selection: $model) {
                        ForEach(CatalogRequest.GRIBSpec.Model.allCases, id: \.self) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    Picker("Auflösung", selection: $resolution) {
                        ForEach(CatalogRequest.GRIBSpec.resolutions, id: \.self) { value in
                            Text("\(value.formatted())°").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Modell")
                }

                Section {
                    TextField("Nord (°)", text: $north, prompt: Text("51.5"))
                    TextField("Süd (°)", text: $south, prompt: Text("43.5"))
                    TextField("West (°)", text: $west, prompt: Text("5.3"))
                    TextField("Ost (°)", text: $east, prompt: Text("13.3"))
                    Button("Um meinen Locator (±4°)") { prefillAroundLocator() }
                        .disabled(PositionResolver.fromLocator(settings.locator) == nil)
                } header: {
                    Text("Gebiet")
                } footer: {
                    Text("Dezimalgrad, Nord und Ost positiv.")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(Self.hourChoices, id: \.self) { hour in
                            Toggle("+\(hour) h", isOn: binding(for: hour, in: $hours))
                        }
                    }
                } header: {
                    Text("Vorhersage-Stunden")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                        ForEach(CatalogRequest.GRIBSpec.commonParameters, id: \.self) { parameter in
                            Toggle(parameter, isOn: binding(for: parameter, in: $parameters))
                        }
                    }
                } header: {
                    Text("Parameter")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let spec {
                            Text(spec.spec)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            if let sizeHint {
                                Text(sizeHint)
                            }
                        } else {
                            Text("Gebiet unvollständig oder ungültig: Nord über Süd, Ost rechts von West, mindestens eine Stunde und ein Parameter.")
                                .foregroundStyle(.statusWarn)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                // Im Hauptfenster gibt es nichts zu schliessen.
                if finishSection == nil {
                    Button("Abbrechen", role: .cancel) { dismiss() }
                }
                Button("Abfrage verfassen") {
                    guard let spec else { return }
                    openWindow(id: "compose", value: ComposeIntent(mode: .gribSpec, mid: spec.spec))
                    if let finishSection { finishSection.run() } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(spec == nil)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(width: 440)
        .onAppear {
            if north.isEmpty { prefillAroundLocator() }
        }
    }

    private func prefillAroundLocator() {
        guard let position = PositionResolver.fromLocator(settings.locator) else { return }
        let box = CatalogRequest.GRIBSpec.around(
            latitude: position.latitude, longitude: position.longitude)
        north = Self.degrees(box.north)
        south = Self.degrees(box.south)
        west = Self.degrees(box.west)
        east = Self.degrees(box.east)
    }

    private static func degrees(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func binding<T: Hashable>(for value: T, in set: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(value) },
            set: { on in
                if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) }
            })
    }
}
