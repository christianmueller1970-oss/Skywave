import Foundation
import Observation

/// One additional way to reach a contact besides the callsign —
/// usually an email address. `label` is free text ("Privat", "QRL").
struct ContactAddress: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var label = ""
    var address = ""

    init(id: UUID = UUID(), label: String = "", address: String = "") {
        self.id = id
        self.label = label
        self.address = address
    }

    /// Beim Einlesen: steht die Adresse im Feld «Bezeichnung» und das
    /// Adressfeld ist leer, gehört sie ins Adressfeld. So war es bis 0.8.0
    /// leicht zu verwechseln — die Bezeichnung stand vorn. Nur beim Laden,
    /// nie während des Tippens.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        if address.trimmingCharacters(in: .whitespaces).isEmpty, label.contains("@") {
            address = label.trimmingCharacters(in: .whitespaces)
            label = ""
        }
    }
}

/// One address-book entry.
struct Contact: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name = ""
    /// Winlink callsign (HB9XYZ) — the primary address.
    var callsign = ""
    /// Further addresses (email etc.), sendable like the callsign.
    var addresses: [ContactAddress] = []
    var qth = ""
    var locator = ""
    /// Free-form group names; the sidebar aggregates them.
    var groups: [String] = []
    var isFavorite = false
    var notes = ""

    /// What the UI shows as the primary line.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if !callsign.isEmpty { return callsign }
        return addresses.first?.address ?? ""
    }

    /// Everything that can go into a To: field — callsign first.
    var allAddresses: [String] {
        var result = [String]()
        let call = callsign.trimmingCharacters(in: .whitespaces)
        if !call.isEmpty { result.append(call.uppercased()) }
        result += addresses.map { $0.address.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return result
    }

    /// Case-insensitive match over every field, for the list filter.
    func matches(_ query: String) -> Bool {
        let blob = ([name, callsign, qth, locator, notes]
            + allAddresses + groups)
            .joined(separator: "\n").lowercased()
        return blob.contains(query)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, callsign, addresses, qth, locator, groups, isFavorite, notes
    }

    private enum LegacyKeys: String, CodingKey {
        case address
    }

    init() {}

    /// Also reads the pre-address-book schema (`name`/`address`/`notes`):
    /// its flat address becomes the callsign, or an email entry.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        callsign = try container.decodeIfPresent(String.self, forKey: .callsign) ?? ""
        addresses =
            try container.decodeIfPresent([ContactAddress].self, forKey: .addresses) ?? []
        qth = try container.decodeIfPresent(String.self, forKey: .qth) ?? ""
        locator = try container.decodeIfPresent(String.self, forKey: .locator) ?? ""
        groups = try container.decodeIfPresent([String].self, forKey: .groups) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""

        if callsign.isEmpty, addresses.isEmpty,
            let legacyContainer = try? decoder.container(keyedBy: LegacyKeys.self),
            let legacy = try legacyContainer.decodeIfPresent(String.self, forKey: .address),
            !legacy.isEmpty
        {
            if legacy.contains("@") {
                addresses = [ContactAddress(label: "E-Mail", address: legacy)]
            } else {
                callsign = legacy.uppercased()
            }
        }
    }
}

/// The address book, persisted as JSON in the data folder
/// (`contacts.json`). Every mutation saves immediately.
@MainActor @Observable final class ContactsStore {
    private(set) var contacts: [Contact] = []

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    /// Contacts sorted for display (by name, case-insensitive).
    var sorted: [Contact] {
        contacts.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Every group name in use, for the sidebar. Groups exist only as
    /// labels on contacts — an empty group disappears by itself.
    var allGroups: [String] {
        var seen = Set<String>()
        var result = [String]()
        for contact in contacts {
            for group in contact.groups {
                let trimmed = group.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted
                else { continue }
                result.append(trimmed)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    func add(_ contact: Contact = Contact()) -> Contact {
        contacts.append(contact)
        save()
        return contact
    }

    func update(_ contact: Contact) {
        guard let index = contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        contacts[index] = contact
        save()
    }

    func remove(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([Contact].self, from: data)
        else { return }
        contacts = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(contacts) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
