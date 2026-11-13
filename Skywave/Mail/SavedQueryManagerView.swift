import SwiftUI
import WinlinkKit

/// Gespeicherte Abfragen verwalten: Liste links, Editor rechts. Teil des
/// Bereichs «Abfragen» im Hauptfenster.
struct SavedQueryManagerView: View {
    @Environment(SavedQueryStore.self) private var queries

    @State private var selectedID: SavedQuery.ID?

    private var selectedQuery: SavedQuery? {
        queries.query(id: selectedID ?? UUID())
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(queries.queries, selection: $selectedID) { query in
                    Text(query.name)
                        .lineLimit(1)
                        .tag(query.id)
                }
                .listStyle(.plain)

                Divider()
                HStack(spacing: 0) {
                    Button {
                        selectedID = queries.add(to: CatalogRequest.inquiryAddress, subject: "REQUEST").id
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 24, height: 24)
                    }
                    .help("Neue Abfrage anlegen")
                    Button {
                        if let query = selectedQuery {
                            queries.remove(query)
                            selectedID = queries.queries.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 24, height: 24)
                    }
                    .disabled(selectedQuery == nil)
                    .help("Abfrage löschen")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .frame(width: 200)

            Divider()

            if let query = selectedQuery {
                SavedQueryForm(query: query)
            } else {
                ContentUnavailableView(
                    "Keine Abfragen",
                    systemImage: "arrow.down.doc",
                    description: Text("Im Fenster «Neue Nachricht» «Als Abfrage speichern» wählen oder hier mit «+» anlegen. Gespeicherte Abfragen erscheinen links in der Liste.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            selectedID = queries.queries.first?.id
        }
    }
}

/// Bearbeitet eine Abfrage; jede Änderung landet sofort im Store.
private struct SavedQueryForm: View {
    @Environment(SavedQueryStore.self) private var queries

    let query: SavedQuery

    @State private var draft = SavedQuery()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $draft.name)
            TextField("An", text: $draft.to, prompt: Text("INQUIRY oder query@saildocs.com"))
                .autocorrectionDisabled()
            TextField("Betreff", text: $draft.subject, prompt: Text("REQUEST"))
            TextEditor(text: $draft.body)
                .font(.body.monospaced())
            Text("Text der Anfrage: ein Katalog-Item je Zeile, oder «send …»-Zeilen für Saildocs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .onAppear { draft = query }
        .onChange(of: query.id) { _, _ in draft = query }
        .onChange(of: draft) { _, newValue in
            guard newValue.id == query.id, newValue != query else { return }
            queries.update(newValue)
        }
    }
}
