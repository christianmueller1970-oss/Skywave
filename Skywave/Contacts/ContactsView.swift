import SwiftUI

/// Which slice of the address book the list shows.
private enum ContactFilter: Hashable {
    case all
    case favorites
    case group(String)

    var title: String {
        switch self {
        case .all: String(localized: "Alle Kontakte")
        case .favorites: String(localized: "Favoriten")
        case .group(let name): name
        }
    }
}

/// The contacts window: filter sidebar (all/favorites/groups),
/// searchable list, editing form.
struct ContactsView: View {
    @Environment(ContactsStore.self) private var contacts

    @State private var filter: ContactFilter = .all
    @State private var selectedID: Contact.ID?
    @State private var searchText = ""
    @State private var confirmingDelete = false

    private var selectedContact: Contact? {
        contacts.contacts.first { $0.id == selectedID }
    }

    private var filtered: [Contact] {
        var result = contacts.sorted
        switch filter {
        case .all:
            break
        case .favorites:
            result = result.filter(\.isFavorite)
        case .group(let name):
            result = result.filter { contact in
                contact.groups.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return result }
        return result.filter { $0.matches(query) }
    }

    var body: some View {
        // Bereich im Hauptfenster: die Bereichswahl liegt dort schon in
        // der Seitenleiste, deshalb hier der Filter als Auswahl über der
        // Liste statt einer weiteren Spalte.
        HSplitView {
            VStack(spacing: 0) {
                Picker("Anzeigen", selection: $filter) {
                    Text("Alle Kontakte (\(contacts.contacts.count))").tag(ContactFilter.all)
                    Text("Favoriten").tag(ContactFilter.favorites)
                    if !contacts.allGroups.isEmpty {
                        Divider()
                        ForEach(contacts.allGroups, id: \.self) { group in
                            Text("Gruppe: \(group)").tag(ContactFilter.group(group))
                        }
                    }
                }
                .labelsHidden()
                .padding(8)
                Divider()
                if filtered.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "Keine Kontakte" : "Keine Treffer",
                        systemImage: "person.crop.circle",
                        description: searchText.isEmpty
                            ? Text("Lege mit «+» einen Kontakt an.")
                            : Text("Kein Kontakt passt zur Suche.")
                    )
                } else {
                    List(filtered, selection: $selectedID) { contact in
                        ContactRow(contact: contact)
                            .tag(contact.id)
                    }
                }
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 380, maxHeight: .infinity)

            Group {
                if let contact = selectedContact {
                    ContactForm(contact: contact)
                } else {
                    ContentUnavailableView(
                        "Kein Kontakt ausgewählt",
                        systemImage: "person.crop.circle",
                        description: Text("Wähle einen Kontakt aus oder lege mit «+» einen neuen an.")
                    )
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Kontakte durchsuchen")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    var contact = Contact()
                    if case .group(let name) = filter {
                        contact.groups = [name]
                    }
                    contact.isFavorite = filter == .favorites
                    selectedID = contacts.add(contact).id
                } label: {
                    Label("Neuer Kontakt", systemImage: "plus")
                }
                .help("Neuen Kontakt anlegen")

                Button {
                    confirmingDelete = true
                } label: {
                    Label("Kontakt löschen", systemImage: "minus")
                }
                .disabled(selectedContact == nil)
                .help("Ausgewählten Kontakt löschen")
            }
        }
        .navigationTitle("Kontakte")
        .onChange(of: filter) {
            if let selectedID, !filtered.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        }
        .confirmationDialog(
            "Kontakt «\(selectedContact?.displayName ?? "")» löschen?",
            isPresented: $confirmingDelete
        ) {
            Button("Löschen", role: .destructive) {
                if let contact = selectedContact {
                    contacts.remove(contact)
                    selectedID = nil
                }
            }
        }
    }
}

/// One line in the contact list: name, callsign/address, favorite star.
private struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.displayName)
                    .lineLimit(1)
                if let secondary = secondaryLine {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if contact.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.favorite)
            }
        }
    }

    /// Callsign (plus QTH) below the name — unless the name line
    /// already shows it because there is nothing else.
    private var secondaryLine: String? {
        var parts = [String]()
        if !contact.callsign.isEmpty, contact.displayName != contact.callsign {
            parts.append(contact.callsign)
        } else if contact.callsign.isEmpty,
            let address = contact.addresses.first?.address, !address.isEmpty,
            contact.displayName != address
        {
            parts.append(address)
        }
        if !contact.qth.isEmpty { parts.append(contact.qth) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Edits one contact; every change is written back to the store
/// immediately.
private struct ContactForm: View {
    @Environment(ContactsStore.self) private var contacts

    let contact: Contact

    @State private var draft = Contact()
    /// Groups as free text ("Notfunk, USKA"), parsed on change.
    @State private var groupsText = ""

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("René Muster"))
                TextField("Rufzeichen", text: $draft.callsign, prompt: Text("HB9XYZ"))
                    .autocorrectionDisabled()
                Toggle("Favorit", isOn: $draft.isFavorite)
            } header: {
                Text("Kontakt")
            }

            Section {
                ForEach($draft.addresses) { $address in
                    // Die Adresse steht vorn und bekommt den Platz: sie ist,
                    // was man hier eintragen will. Die Bezeichnung dahinter
                    // ist freiwillig. Ohne sichtbare Feldnamen, sonst wird
                    // die Zeile zu eng und das erste Feld verschluckt Text.
                    HStack {
                        TextField(
                            "Adresse", text: $address.address,
                            prompt: Text("name@example.com")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                        TextField(
                            "Bezeichnung", text: $address.label,
                            prompt: Text("Bezeichnung (optional)")
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .frame(width: 180)
                        Button {
                            draft.addresses.removeAll { $0.id == address.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Adresse entfernen")
                    }
                }
                Button {
                    draft.addresses.append(ContactAddress())
                } label: {
                    Label("Adresse hinzufügen", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Weitere Adressen")
            } footer: {
                Text("Das Rufzeichen ist die Winlink-Adresse; hier stehen zusätzliche Wege wie E-Mail.")
            }

            Section("Station") {
                TextField("QTH / Ort", text: $draft.qth, prompt: Text("Amriswil"))
                TextField("Locator", text: $draft.locator, prompt: Text("JN47PN"))
                    .autocorrectionDisabled()
            }

            Section {
                TextField("Gruppen", text: $groupsText, prompt: Text("Notfunk, USKA"))
            } header: {
                Text("Gruppen")
            } footer: {
                Text("Mehrere Gruppen mit Komma trennen; sie erscheinen links in der Seitenleiste.")
            }

            Section("Notizen") {
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .frame(minHeight: 60)
            }
        }
        .formStyle(.grouped)
        .onAppear { adopt(contact) }
        .onChange(of: contact.id) { adopt(contact) }
        .onChange(of: groupsText) {
            draft.groups = groupsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        .onChange(of: draft) {
            guard draft.id == contact.id, draft != contact else { return }
            contacts.update(draft)
        }
    }

    private func adopt(_ contact: Contact) {
        draft = contact
        groupsText = contact.groups.joined(separator: ", ")
    }
}
