import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// Versandkontrolle auf Store-Ebene: Kennzeichnung, Filter je Weg,
/// Sitzungs-Mailbox.
@MainActor
@Suite struct SessionMailboxTests {

    private func makeStore() -> (MailStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        return (MailStore(root: root), root)
    }

    /// Die Kennzeichnung bestimmt, was je Weg angeboten wird, und
    /// überlebt einen Neustart des Stores.
    @Test func routeFiltersByPathAndPersists() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let anyMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "beliebig", body: "a")
        let radioMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "nur Funk", body: "b")
        let internetMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "nur Internet", body: "c")
        let heldMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "zurückhalten", body: "d")

        func item(_ mid: String) throws -> MailItem {
            try #require(store.items(in: .outbox).first { $0.id == mid })
        }
        store.setRoute(.radio, for: try item(radioMID))
        store.setRoute(.internet, for: try item(internetMID))
        store.setRoute(.hold, for: try item(heldMID))

        let radio = ExchangePath.radio(.ardop, gateway: "HB9AK")
        #expect(store.outboundMIDs(for: .internet) == [anyMID, internetMID])
        #expect(store.outboundMIDs(for: radio) == [anyMID, radioMID])
        #expect(Set(store.heldItems(for: .internet).map(\.id)) == [radioMID, heldMID])
        #expect(Set(store.heldItems(for: radio).map(\.id)) == [internetMID, heldMID])
        #expect(try item(radioMID).route == .radio)
        #expect(try item(anyMID).route == .any)

        let reopened = MailStore(root: root)
        #expect(reopened.outboundMIDs(for: .internet) == [anyMID, internetMID])

        // Zurück auf «beliebig» löscht den Eintrag wieder.
        reopened.setRoute(.any, for: try #require(reopened.items(in: .outbox).first { $0.id == heldMID }))
        #expect(reopened.outboundMIDs(for: .internet).contains(heldMID))
    }

    /// Verlässt eine gekennzeichnete Nachricht den Postausgang, ist die
    /// Kennzeichnung gegenstandslos und wird aufgeräumt.
    @Test func routingIsPrunedWhenMessageLeavesOutbox() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let mid = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "s", body: "b")
        store.setRoute(.hold, for: try #require(store.items(in: .outbox).first))
        let sidecar = root.appendingPathComponent("outbox-routing.json")
        #expect(try String(contentsOf: sidecar, encoding: .utf8).contains(mid))

        await store.handler.markSent(mid, rejected: false)
        store.reload()
        #expect(!(try String(contentsOf: sidecar, encoding: .utf8)).contains(mid))
    }

    /// Die Sitzungs-Mailbox bietet nur die erlaubten MIDs an; die
    /// Abwahl im Dialog schränkt weiter ein.
    @Test func sessionMailboxOffersOnlyAllowedMessages() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let a = try await store.compose(mycall: "HB9HJI", to: "HB9ABC", subject: "a", body: "a")
        let b = try await store.compose(mycall: "HB9HJI", to: "HB9ABC", subject: "b", body: "b")
        let held = try await store.compose(mycall: "HB9HJI", to: "HB9ABC", subject: "h", body: "h")
        store.setRoute(.hold, for: try #require(store.items(in: .outbox).first { $0.id == held }))

        let all = store.makeSessionMailbox(path: .internet)
        #expect(Set(await all.outboundMessages(for: []).map(\.mid)) == [a, b])

        let picked = store.makeSessionMailbox(path: .internet, selection: [b, held])
        #expect(await picked.outboundMessages(for: []).map(\.mid) == [b])
    }

    /// Die Eingangsgrenze gilt nur über Funk — Internet nimmt alles.
    @Test func inboundLimitOnlyAppliesToRadio() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = store.makeSessionMailbox(path: .internet, maxInboundBytes: 10)
        _ = store.makeSessionMailbox(path: .radio(.ardop, gateway: "HB9AK"), maxInboundBytes: 10)
        // Verhalten wird in ExchangeControllerTests über die Pipe geprüft;
        // hier nur die Kilobyte-Darstellung der Zusammenfassung.
        #expect(SessionMailbox.kilobytes(48_123) == "48")
        #expect(SessionMailbox.kilobytes(512) == "0,5")
        #expect(SessionMailbox.kilobytes(0) == "0,0")
    }
}

@MainActor
@Suite struct P2POutboxPreviewTests {
    /// Die P2P-Vorschau zeigt nur Post exklusiv an die Gegenstation,
    /// ohne Zurückgehaltenes und ohne «nur Internet».
    @Test func previewListsOnlyExclusiveRadioMail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)

        let direct = try await store.compose(mycall: "HB9HJI", to: "HB9XYZ", subject: "a", body: "a")
        _ = try await store.compose(mycall: "HB9HJI", to: "HB9XYZ, HB9ABC", subject: "b", body: "b")
        let internetOnly = try await store.compose(mycall: "HB9HJI", to: "hb9xyz", subject: "c", body: "c")
        store.setRoute(.internet, for: try #require(store.items(in: .outbox).first { $0.id == internetOnly }))

        #expect(store.outboxItems(exclusivelyFor: " hb9xyz ").map(\.id) == [direct])
        #expect(store.outboxItems(exclusivelyFor: "HB9ABC").isEmpty)
    }

    @Test func p2pSettingsPersist() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")

        let settings = AppSettingsStore(fileURL: url)
        #expect(settings.p2pKind == .ardop)
        settings.p2pPeer = "hb9xyz"
        settings.p2pKind = .varaHF
        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.p2pPeer == "HB9XYZ")
        #expect(reloaded.p2pKind == .varaHF)
    }
}

@Suite struct P2PDialFrequencyTests {
    @Test func parsesSwissAndPlainKHz() {
        #expect(P2PConnectSheet.dialHz(fromKHz: "3'587,0") == 3_587_000)
        #expect(P2PConnectSheet.dialHz(fromKHz: " 14105.5 ") == 14_105_500)
    }

    /// Unsinn wird verworfen statt beim Umwandeln abzustürzen.
    @Test func rejectsNonFrequencies() {
        for text in ["", "abc", "inf", "-inf", "nan", "1e20", "50", "500000"] {
            #expect(P2PConnectSheet.dialHz(fromKHz: text) == nil)
        }
    }
}
