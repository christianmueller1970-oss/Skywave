import SwiftUI

/// Bereich «Abfragen»: Inhalte per Winlink-Mail anfordern. Links die
/// Katalog-Vorlagen und die gespeicherten Abfragen, rechts der
/// GRIB-Assistent oder die Verwaltung der gespeicherten Abfragen. Jede
/// Abfrage öffnet ein Fenster «Neue Nachricht».
struct QueriesSectionView: View {
    @Environment(SavedQueryStore.self) private var queries
    @Environment(\.openWindow) private var openWindow

    private enum Pane: Hashable {
        case grib
        case manage
    }
    @State private var pane = Pane.grib

    var body: some View {
        HStack(spacing: 0) {
            List {
                Section("Katalog") {
                    ForEach(CatalogTemplate.allCases) { template in
                        Button {
                            openWindow(
                                id: "compose",
                                value: ComposeIntent(mode: .catalog, mid: template.rawValue))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.menuTitle)
                                Text(template.help)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Gespeicherte Abfragen") {
                    if queries.queries.isEmpty {
                        Text("Noch keine gespeicherten Abfragen.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(queries.queries) { query in
                        Button {
                            openWindow(
                                id: "compose",
                                value: ComposeIntent(mode: .savedQuery, mid: query.id.uuidString))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(query.name)
                                Text("an \(query.to)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Abfragen verwalten …") {
                        pane = .manage
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)

            Divider()

            VStack(spacing: 0) {
                Picker("Ansicht", selection: $pane) {
                    Text("GRIB-Wetterdaten").tag(Pane.grib)
                    Text("Gespeicherte Abfragen verwalten").tag(Pane.manage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(10)
                Divider()
                switch pane {
                case .grib:
                    GRIBAssistantView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                case .manage:
                    SavedQueryManagerView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Abfragen")
    }
}
