import Foundation
import Testing

@testable import Skywave

/// Menü- und Symbolleistenbefehle sind nur aktiv, wenn sie etwas tun
/// können.
@MainActor
@Suite struct MailboxCommandTests {
    private func item(_ folder: MailFolder, isRead: Bool = true) -> MailItem {
        MailItem(
            id: "MID1", folder: folder, from: "SERVICE", to: "HB9HJI", subject: "Test",
            date: nil, attachmentCount: 0, isRead: isRead,
            url: URL(fileURLWithPath: "/dev/null"), searchBlob: "")
    }

    @Test func nothingSelectedDisablesEveryMessageCommand() {
        let state = MessageCommandState(item: nil)
        #expect(!state.canReply)
        #expect(!state.canEditDraft)
        #expect(!state.canToggleRead)
        #expect(!state.canRoute)
        #expect(!state.canMove)
        #expect(!state.canDelete)
    }

    @Test func inboxMessageCanBeAnsweredMarkedMovedAndTrashed() {
        let state = MessageCommandState(item: item(.inbox, isRead: false))
        #expect(state.canReply)
        #expect(state.canToggleRead)
        #expect(state.canMove)
        #expect(state.canDelete)
        #expect(!state.canRoute)
        #expect(!state.canEditDraft)
        #expect(state.readTitle == "Als gelesen markieren")
        #expect(state.deleteTitle == "In den Papierkorb legen")
        #expect(MessageCommandState(item: item(.custom("QSL"))).readTitle == "Als ungelesen markieren")
    }

    /// Ein Entwurf wird bearbeitet, nicht beantwortet oder verschoben.
    @Test func draftIsEditedNotAnsweredOrMoved() {
        let state = MessageCommandState(item: item(.drafts))
        #expect(state.canEditDraft)
        #expect(!state.canReply)
        #expect(!state.canMove)
        #expect(state.canDelete)
    }

    @Test func versandwegOnlyInTheOutboxAndTrashDeletesForGood() {
        #expect(MessageCommandState(item: item(.outbox)).canRoute)
        #expect(!MessageCommandState(item: item(.sent)).canRoute)
        #expect(!MessageCommandState(item: item(.sent)).canToggleRead)
        #expect(MessageCommandState(item: item(.trash)).deleteTitle == "Endgültig löschen …")
    }

    @Test func folderCommandsFollowTheShownSection() {
        // Eigener Ordner: umbenennen und löschen gehen, neuer Ordner darunter.
        let own = FolderCommandState(section: .folder(.custom("QSL")), trashIsEmpty: true)
        #expect(own.canRenameOrDelete)
        #expect(own.newFolderParent == .custom("QSL"))
        #expect(!own.canEmptyTrash)

        // Feste Ordner und andere Bereiche: neuer Ordner landet im Posteingang.
        for section in [AppSection.folder(.inbox), .folder(.sent), .gateways, .contacts] {
            let state = FolderCommandState(section: section, trashIsEmpty: false)
            #expect(!state.canRenameOrDelete)
            #expect(state.newFolderParent == .inbox)
            #expect(state.canEmptyTrash)
        }
    }

    /// Tune startet nicht während einer Sitzung, des Assistenten oder mit
    /// externem Modem — «Tune aus» geht dagegen immer.
    @Test func tuneIsBlockedWhileTheRadioIsBusy() {
        func blocked(manual: Bool = false, running: Bool = false, tuning: Bool = false, bundled: Bool = true) -> Bool {
            TuneButton.isBlocked(
                isManualTuning: manual, isRunning: running, isTuning: tuning, usesBundledModem: bundled)
        }
        #expect(!blocked())
        #expect(blocked(running: true))
        #expect(blocked(tuning: true))
        #expect(blocked(bundled: false))
        #expect(!blocked(manual: true, tuning: true))
    }

    /// Übersicht: der Postausgang nach Versandweg.
    @Test func outboxSummaryCountsByRoute() {
        func outbox(_ id: String, _ route: OutboxRoute) -> MailItem {
            var item = MailItem(
                id: id, folder: .outbox, from: "HB9HJI", to: "SERVICE", subject: "Test",
                date: nil, attachmentCount: 0, isRead: true,
                url: URL(fileURLWithPath: "/dev/null"), searchBlob: "")
            item.route = route
            return item
        }
        let empty = OutboxSummary(items: [])
        #expect(empty.headline == "Nichts zu senden")
        #expect(empty.lines.isEmpty)

        #expect(OutboxSummary(items: [outbox("1", .any)]).headline == "1 Nachricht wartet")

        let mixed = OutboxSummary(items: [
            outbox("1", .any), outbox("2", .any), outbox("3", .radio), outbox("4", .hold),
        ])
        #expect(mixed.headline == "4 Nachrichten warten")
        #expect(mixed.lines == ["2 für jeden Weg", "1 nur über Funk", "1 zurückgehalten"])
    }

    /// Dieselbe Anforderung zweimal hintereinander kommt zweimal an.
    @Test func requestsAreCountedAndTakenOnce() {
        let center = MailboxCommandCenter()
        center.send(.emptyTrash)
        let first = center.requestSerial
        #expect(center.take() == .emptyTrash)
        #expect(center.take() == nil)
        center.send(.emptyTrash)
        #expect(center.requestSerial == first + 1)
        #expect(center.take() == .emptyTrash)
        center.send(.radio(.ardop))
        #expect(center.take() == .radio(.ardop))
    }
}
