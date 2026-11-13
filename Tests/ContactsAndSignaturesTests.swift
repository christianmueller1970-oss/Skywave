import Foundation
import Testing

@testable import Skywave

/// A unique temp file URL for a store's JSON.
private func makeFileURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name)
}

@MainActor
@Suite struct ContactsStoreTests {

    private func makeContact(
        name: String = "", callsign: String = "", email: String = ""
    ) -> Contact {
        var contact = Contact()
        contact.name = name
        contact.callsign = callsign
        if !email.isEmpty {
            contact.addresses = [ContactAddress(label: "E-Mail", address: email)]
        }
        return contact
    }

    @Test func addUpdateRemovePersist() throws {
        let url = makeFileURL("contacts.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ContactsStore(fileURL: url)
        #expect(store.contacts.isEmpty)

        var contact = store.add(makeContact(name: "René", callsign: "HB9ABC"))
        store.add(makeContact(name: "anna", email: "anna@example.com"))
        #expect(store.contacts.count == 2)
        // Sorted case-insensitively by display name.
        #expect(store.sorted.map(\.name) == ["anna", "René"])

        contact.notes = "QSL via Büro"
        store.update(contact)

        // A fresh store over the same file sees everything.
        let reopened = ContactsStore(fileURL: url)
        #expect(reopened.contacts.count == 2)
        #expect(reopened.contacts.first { $0.id == contact.id }?.notes == "QSL via Büro")

        store.remove(contact)
        #expect(ContactsStore(fileURL: url).contacts.count == 1)
    }

    /// A contact without a name falls back to callsign or address.
    @Test func displayNameFallsBack() {
        #expect(makeContact(name: " ", callsign: "HB9ABC").displayName == "HB9ABC")
        #expect(makeContact(name: "René", callsign: "HB9ABC").displayName == "René")
        #expect(makeContact(email: "anna@example.com").displayName == "anna@example.com")
    }

    /// Callsign first, then the extra addresses; blanks are skipped.
    @Test func allAddressesListsCallsignFirst() {
        var contact = makeContact(callsign: "hb9abc", email: "rene@example.com")
        contact.addresses.append(ContactAddress(label: "", address: "  "))
        #expect(contact.allAddresses == ["HB9ABC", "rene@example.com"])
    }

    /// Group names are aggregated over all contacts, deduplicated
    /// case-insensitively, sorted.
    @Test func allGroupsAggregates() throws {
        let url = makeFileURL("contacts.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ContactsStore(fileURL: url)
        var a = makeContact(name: "a", callsign: "HB9AAA")
        a.groups = ["Notfunk", "USKA"]
        var b = makeContact(name: "b", callsign: "HB9BBB")
        b.groups = ["notfunk", " "]
        store.add(a)
        store.add(b)
        #expect(store.allGroups == ["Notfunk", "USKA"])
    }

    /// contacts.json written by the pre-address-book app (flat
    /// name/address/notes) still loads: a callsign-looking address
    /// becomes the callsign, an email becomes an extra address.
    @Test func legacyFormatMigrates() throws {
        let url = makeFileURL("contacts.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let legacy = """
            [
              {"id": "\(UUID().uuidString)", "name": "René", "address": "hb9abc",
               "notes": "QSL via Büro"},
              {"id": "\(UUID().uuidString)", "name": "Anna",
               "address": "anna@example.com", "notes": ""}
            ]
            """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: url)

        let store = ContactsStore(fileURL: url)
        #expect(store.contacts.count == 2)
        let rene = try #require(store.contacts.first { $0.name == "René" })
        #expect(rene.callsign == "HB9ABC")
        #expect(rene.notes == "QSL via Büro")
        let anna = try #require(store.contacts.first { $0.name == "Anna" })
        #expect(anna.callsign.isEmpty)
        #expect(anna.addresses.map(\.address) == ["anna@example.com"])
    }
}

@MainActor
@Suite struct SignatureStoreTests {

    @Test func firstSignatureBecomesDefaultAndPersists() throws {
        let url = makeFileURL("signatures.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = SignatureStore(fileURL: url)
        #expect(store.defaultSignature == nil)

        var first = store.add()
        let second = store.add()
        #expect(store.defaultID == first.id)
        // Auto-numbered names stay unique.
        #expect(store.signatures.map(\.name) == ["Signatur", "Signatur 2"])

        first.text = "73 de HB9HJI"
        store.update(first)
        store.setDefault(second)

        let reopened = SignatureStore(fileURL: url)
        #expect(reopened.signatures.count == 2)
        #expect(reopened.defaultID == second.id)
        #expect(reopened.signatures.first { $0.id == first.id }?.text == "73 de HB9HJI")

        // Removing the default falls back to the first remaining one.
        reopened.remove(second)
        #expect(reopened.defaultID == first.id)
    }
}
