import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// A fresh store rooted in a unique temp directory.
@MainActor
private func makeStore() -> (MailStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
    return (MailStore(root: root), root)
}

@MainActor
@Suite struct MailStoreTests {

    @Test func composeQueuesInOutbox() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let mid = try await store.compose(
            mycall: "HB9HJI", to: "rene@example.com, HB9ABC",
            subject: "Grüezi", body: "Hallo Rene")

        let outbox = store.items(in: .outbox)
        #expect(outbox.count == 1)
        #expect(outbox[0].id == mid)
        #expect(outbox[0].subject == "Grüezi")
        #expect(outbox[0].to.contains("rene@example.com"))
        #expect(outbox[0].to.contains("HB9ABC"))
        #expect(outbox[0].isRead) // only inbox tracks unread
        #expect(store.items(in: .inbox).isEmpty)
    }

    @Test func composeWithCcSetsCarbonCopy() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let mid = try await store.compose(
            mycall: "HB9HJI", to: "LA5NTA", cc: "N0CALL; rene@example.com",
            subject: "Re: Grüezi", body: "Hallo zusammen")

        let message = try #require(store.message(withMID: mid))
        #expect(message.to == [Address(addr: "LA5NTA")])
        #expect(message.cc == [
            Address(addr: "N0CALL"),
            Address(proto: "SMTP", addr: "rene@example.com"),
        ])
    }

    /// Drafts: an incomplete message can be saved, re-saving with the
    /// same MID overwrites instead of duplicating, queueing plus
    /// deleteDraft leaves outbox-only.
    @Test func draftLifecycle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // Incomplete on purpose: no recipient, no body.
        let mid = try store.saveDraft(
            mycall: "HB9HJI", to: "", subject: "Halbfertig", body: "")
        #expect(store.items(in: .drafts).count == 1)
        #expect(store.items(in: .drafts)[0].subject == "Halbfertig")

        // Saving again with the same MID updates the one file.
        let resavedMID = try store.saveDraft(
            mid: mid, mycall: "HB9HJI", to: "HB9ABC",
            subject: "Fertig", body: "Hallo")
        #expect(resavedMID == mid)
        let drafts = store.items(in: .drafts)
        #expect(drafts.count == 1)
        #expect(drafts[0].subject == "Fertig")
        #expect(drafts[0].to == "HB9ABC")

        // Queue the finished draft, then drop the draft copy —
        // the compose window's flow.
        try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "Fertig", body: "Hallo")
        store.deleteDraft(mid: mid)
        #expect(store.items(in: .drafts).isEmpty)
        #expect(store.items(in: .outbox).count == 1)
    }

    /// Deleting a draft from the list moves it to the trash like any
    /// other message.
    @Test func draftDeleteMovesToTrash() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try store.saveDraft(mycall: "HB9HJI", to: "", subject: "Weg damit", body: "")
        let draft = try #require(store.items(in: .drafts).first)
        store.delete(draft)
        #expect(store.items(in: .drafts).isEmpty)
        #expect(store.items(in: .trash).count == 1)
    }

    /// The search blob matches subject, addresses and body text,
    /// lowercased.
    @Test func searchBlobCoversSubjectAddressesAndBody() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        try await store.compose(
            mycall: "HB9HJI", to: "rene@example.com",
            subject: "Antennenbau", body: "Der neue Dipol ist 2x19.5m lang.")

        let item = try #require(store.items(in: .outbox).first)
        #expect(item.searchBlob.contains("antennenbau"))
        #expect(item.searchBlob.contains("rene@example.com"))
        #expect(item.searchBlob.contains("dipol"))
        #expect(!item.searchBlob.contains("yagi"))
    }

    @Test func composeRejectsMissingRecipient() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await #expect(throws: WinlinkError.self) {
            try await store.compose(
                mycall: "HB9HJI", to: " ", subject: "x", body: "y")
        }
        #expect(store.items(in: .outbox).isEmpty)
    }

    /// A message received through the session handler shows up in the
    /// inbox as unread; the read flag survives a store restart.
    @Test func inboundListsUnreadAndReadStatePersists() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var message = B2Message(mycall: "HB9ABC")
        message.addTo("HB9HJI")
        message.setSubject("Test inbound")
        message.setBody("Hallo\n")
        try await store.handler.prepare()
        try await store.handler.processInbound(message)
        store.reload()

        let item = try #require(store.items(in: .inbox).first)
        #expect(!item.isRead)
        #expect(store.unreadCount == 1)

        store.markRead(item)
        #expect(store.unreadCount == 0)

        // New store over the same root: read state must persist.
        let reopened = MailStore(root: root)
        #expect(reopened.unreadCount == 0)
        #expect(reopened.items(in: .inbox).count == 1)
    }

    /// markSent (as called by the session) moves a message from outbox
    /// to sent; the store sees it after reload.
    @Test func sentMessagesMoveFolders() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let mid = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "s", body: "b")
        await store.handler.markSent(mid, rejected: false)
        store.reload()

        #expect(store.items(in: .outbox).isEmpty)
        #expect(store.items(in: .sent).count == 1)
        #expect(store.items(in: .sent)[0].id == mid)
    }

    /// Deleting moves to the trash first; deleting there is final.
    @Test func deleteMovesToTrashThenRemoves() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "s", body: "b")
        let item = try #require(store.items(in: .outbox).first)

        store.delete(item)
        #expect(store.items(in: .outbox).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: item.url.path))
        #expect(store.items(in: .trash).count == 1)

        let trashed = try #require(store.items(in: .trash).first)
        store.delete(trashed)
        #expect(store.items(in: .trash).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: trashed.url.path))
    }

    @Test func emptyTrashRemovesEverything() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        for subject in ["eins", "zwei"] {
            _ = try await store.compose(
                mycall: "HB9HJI", to: "HB9ABC", subject: subject, body: "b")
        }
        for item in store.items(in: .outbox) {
            store.delete(item)
        }
        #expect(store.items(in: .trash).count == 2)

        store.emptyTrash()
        #expect(store.items(in: .trash).isEmpty)
    }

    /// Custom folders below the inbox: create, list, move a message in,
    /// rename (message stays), delete (message lands in the trash).
    @Test func customFolderLifecycle() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        var message = B2Message(mycall: "HB9ABC")
        message.addTo("HB9HJI")
        message.setSubject("QSL bitte")
        message.setBody("73\n")
        try await store.handler.prepare()
        try await store.handler.processInbound(message)
        store.reload()

        let folder = try store.createFolder(named: "QSL")
        let nested = try store.createFolder(named: "2026", under: folder)
        #expect(store.customFolderPaths == ["QSL", "QSL/2026"])

        // Duplicate and invalid names are refused.
        #expect(throws: MailFolderError.self) {
            try store.createFolder(named: "QSL")
        }
        #expect(throws: MailFolderError.self) {
            try store.createFolder(named: "a/b")
        }

        let item = try #require(store.items(in: .inbox).first)
        store.move(item, to: nested)
        #expect(store.items(in: .inbox).isEmpty)
        #expect(store.items(in: nested).count == 1)
        // Moved received mail keeps tracking unread state.
        #expect(store.items(in: nested)[0].isRead == false)
        #expect(store.unreadCount == 1)

        let renamed = try store.renameFolder(folder, to: "QSL-Karten")
        #expect(store.customFolderPaths == ["QSL-Karten", "QSL-Karten/2026"])
        #expect(store.items(in: .custom("QSL-Karten/2026")).count == 1)

        store.deleteFolder(renamed)
        #expect(store.customFolderPaths.isEmpty)
        #expect(store.items(in: .trash).count == 1)
    }

    /// The reading pane gets the full message back, body included.
    @Test func fullMessageRoundtrip() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "Umlaute üöä",
            body: "Grüsse aus Amriswil")
        let item = try #require(store.items(in: .outbox).first)
        let message = try #require(store.message(for: item))

        #expect(message.subject == "Umlaute üöä")
        // The wire format enforces CRLF line endings (B2 spec).
        #expect(message.bodyText == "Grüsse aus Amriswil\r\n")
    }
}
