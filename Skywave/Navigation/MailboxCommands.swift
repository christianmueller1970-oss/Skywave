import SwiftUI

/// Was die Menüleiste vom Hauptfenster verlangen kann. Befehle, die
/// einen Dialog des Fensters brauchen (Ordner anlegen, Funk-Dialog,
/// Rückfrage vor dem Löschen), laufen als Anforderung dorthin.
enum MailboxRequest: Equatable, Sendable {
    case newFolder
    case renameFolder
    case deleteFolder
    case emptyTrash
    case deleteMessage
    case exchangeInternet
    case radio(RadioTransportKind)
    case p2p
    case showLog
    case levelAssistant
}

/// Verbindet Menüleiste und Hauptfenster: das Fenster meldet die
/// gewählte Nachricht, die Menüs schicken Anforderungen zurück. Ein
/// Objekt für die ganze App (`AppServices.commands`).
@MainActor @Observable final class MailboxCommandCenter {
    /// Die im Hauptfenster gewählte Nachricht, nil ausserhalb des
    /// Postfachs oder ohne Auswahl.
    var selectedItem: MailItem?

    private(set) var request: MailboxRequest?
    /// Zählt jede Anforderung, damit das Fenster auch zweimal dieselbe
    /// hintereinander bemerkt.
    private(set) var requestSerial = 0

    func send(_ request: MailboxRequest) {
        self.request = request
        requestSerial += 1
    }

    /// Holt die offene Anforderung ab.
    func take() -> MailboxRequest? {
        defer { request = nil }
        return request
    }
}

/// Welche Nachrichten-Befehle gerade etwas tun können — eine Stelle für
/// Menüleiste und Symbolleiste.
struct MessageCommandState: Equatable {
    /// Antworten, Allen antworten, Weiterleiten.
    let canReply: Bool
    let canEditDraft: Bool
    let canToggleRead: Bool
    let canRoute: Bool
    let canMove: Bool
    let canDelete: Bool
    let readTitle: String
    let deleteTitle: String

    init(item: MailItem?) {
        let folder = item?.folder
        canReply = item != nil && folder != .drafts
        canEditDraft = folder == .drafts
        canToggleRead = folder?.isInboxTree == true
        canRoute = folder == .outbox
        canMove = item != nil && folder != .drafts
        canDelete = item != nil
        readTitle = item?.isRead == true ? String(localized: "Als ungelesen markieren") : String(localized: "Als gelesen markieren")
        deleteTitle = folder == .trash ? String(localized: "Endgültig löschen …") : String(localized: "In den Papierkorb legen")
    }
}

/// Welche Ordner-Befehle gerade etwas tun können.
struct FolderCommandState: Equatable {
    /// Unter diesem Ordner entsteht ein neuer: der gezeigte, wenn er
    /// zum Posteingang gehört, sonst der Posteingang.
    let newFolderParent: MailFolder
    /// Umbenennen und Löschen gehen nur für eigene Ordner.
    let canRenameOrDelete: Bool
    let canEmptyTrash: Bool

    init(section: AppSection, trashIsEmpty: Bool) {
        let folder = section.folder
        newFolderParent = folder?.isInboxTree == true ? folder! : .inbox
        if case .custom = folder { canRenameOrDelete = true } else { canRenameOrDelete = false }
        canEmptyTrash = !trashIsEmpty
    }
}

// MARK: - Menüleiste

/// Die Menüs der App: Ablage (Ordner), Nachricht, Funk und die Bereiche
/// unter «Darstellung». Jeder Eintrag ist eine eigene View, weil nur
/// View-Bodies verlässlich auf @Observable-Änderungen reagieren.
struct SkywaveCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            FolderCommandItems()
        }
        CommandMenu("Nachricht") {
            MessageCommandItems()
        }
        CommandMenu("Funk") {
            RadioCommandItems()
        }
        CommandGroup(before: .sidebar) {
            SectionCommandItems()
            Divider()
            Button("Seitenleiste ein-/ausblenden") {
                NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            Divider()
        }
    }
}

@MainActor private enum MainWindow {
    /// Holt das Hauptfenster nach vorn oder öffnet es, wenn es
    /// geschlossen wurde — sonst liefe ein Menübefehl ins Leere.
    static func show(_ openWindow: OpenWindowAction) {
        let window = NSApp.windows.first {
            $0.identifier?.rawValue.hasPrefix("mailbox") == true && $0.isVisible
        }
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "mailbox")
        }
    }
}

private struct FolderCommandItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let store = AppServices.app.workspace?.store
        let state = FolderCommandState(
            section: AppServices.navigation.section,
            trashIsEmpty: store?.items(in: .trash).isEmpty ?? true)

        Button("Neuer Ordner …") { send(.newFolder) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(store == nil)
        Button("Ordner umbenennen …") { send(.renameFolder) }
            .disabled(!state.canRenameOrDelete)
        Button("Ordner löschen …") { send(.deleteFolder) }
            .disabled(!state.canRenameOrDelete)
        Divider()
        Button("Papierkorb leeren …") { send(.emptyTrash) }
            .disabled(!state.canEmptyTrash)
    }

    private func send(_ request: MailboxRequest) {
        MainWindow.show(openWindow)
        AppServices.commands.send(request)
    }
}

private struct MessageCommandItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let item = AppServices.commands.selectedItem
        let store = AppServices.app.workspace?.store
        let state = MessageCommandState(item: item)

        Button("Antworten") { compose(.reply) }
            .keyboardShortcut("r")
            .disabled(!state.canReply)
        Button("Allen antworten") { compose(.replyAll) }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!state.canReply)
        Button("Weiterleiten") { compose(.forward) }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(!state.canReply)
        Button("Entwurf bearbeiten") { compose(.editDraft) }
            .keyboardShortcut("o")
            .disabled(!state.canEditDraft)
        Divider()
        Button(state.readTitle) {
            if let item { store?.markRead(item, !item.isRead) }
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .disabled(!state.canToggleRead)
        if let item, let store, state.canRoute {
            OutboxRouteMenu(item: item).environment(store)
        } else {
            // Ein leeres Untermenü bliebe anklickbar — als Eintrag ist es grau.
            Button("Versandweg") {}.disabled(true)
        }
        if let item, let store, state.canMove {
            MoveToFolderMenu(item: item).environment(store)
        } else {
            Button("Verschieben nach") {}.disabled(true)
        }
        Divider()
        Button(state.deleteTitle) {
            MainWindow.show(openWindow)
            AppServices.commands.send(.deleteMessage)
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(!state.canDelete)
    }

    private func compose(_ mode: ComposeIntent.Mode) {
        guard let item = AppServices.commands.selectedItem else { return }
        openWindow(id: "compose", value: ComposeIntent(mode: mode, mid: item.id))
    }
}

private struct RadioCommandItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let exchange = AppServices.exchange
        let ready = AppServices.app.workspace != nil && !exchange.isRunning

        Button("Abrufen & Senden über Internet") { send(.exchangeInternet) }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!ready)
        Divider()
        ForEach(RadioTransportKind.allCases) { kind in
            Button("Abrufen & Senden über \(kind.displayName) …") { send(.radio(kind)) }
                .disabled(!ready)
        }
        Button("Direktverbindung (P2P) …") { send(.p2p) }
            .disabled(!ready)
        Divider()
        Button("Sitzung abbrechen") { exchange.abortExchange() }
            .keyboardShortcut(".")
            .disabled(!exchange.canAbort)
        Button("Protokoll der Sitzung anzeigen") { send(.showLog) }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(exchange.log.isEmpty)
        Divider()
        RigCommandItems()
    }

    private func send(_ request: MailboxRequest) {
        MainWindow.show(openWindow)
        AppServices.commands.send(request)
    }
}

/// Funkgerät verbinden und trennen, Tune und Pegel-Assistent.
private struct RigCommandItems: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let exchange = AppServices.exchange
        let rig = AppServices.rig
        let settings = AppServices.app.workspace?.settings
        let busy = exchange.isRunning || exchange.isTuning
        let usesRigctld = settings?.rigAccess == .bundled || settings?.rigAccess == .external

        if rig.isConnected {
            Button("Funkgerät trennen") { Task { await rig.disconnect() } }
                .disabled(busy)
        } else {
            Button("Funkgerät verbinden") {
                guard let target = settings?.rigLink else { return }
                Task { await rig.connect(target.link, name: target.name) }
            }
            .disabled(!usesRigctld || settings?.rigLink == nil || busy || rig.status == .connecting)
        }
        Button(exchange.isManualTuning ? "Tune aus" : "Tune") {
            if let settings { exchange.toggleManualTune(settings: settings) }
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .disabled(
            settings == nil
                || TuneButton.isBlocked(
                    isManualTuning: exchange.isManualTuning, isRunning: exchange.isRunning,
                    isTuning: exchange.isTuning, usesBundledModem: settings?.ardopUseBundled ?? false)
                || exchange.isStoppingManualTune)
        Button("Pegel-Assistent …") {
            AppServices.navigation.show(.rig)
            MainWindow.show(openWindow)
            AppServices.commands.send(.levelAssistant)
        }
        .disabled(settings?.ardopUseBundled != true || busy)
    }
}

/// Die Bereiche des Hauptfensters unter «Darstellung».
private struct SectionCommandItems: View {
    @Environment(\.openWindow) private var openWindow

    private static let folders: [(MailFolder, KeyEquivalent)] = [
        (.inbox, "1"), (.drafts, "2"), (.outbox, "3"), (.sent, "4"), (.trash, "5"),
    ]
    private static let others: [(AppSection, KeyEquivalent)] = [
        (.gateways, "g"), (.connections, "h"), (.logs, "j"), (.rig, "t"),
        (.contacts, "k"), (.position, "p"), (.queries, "a"),
    ]

    var body: some View {
        ForEach(Self.folders, id: \.0) { folder, key in
            Button(folder.displayName) { show(.folder(folder)) }
                .keyboardShortcut(key, modifiers: .command)
        }
        Divider()
        ForEach(Self.others, id: \.0) { section, key in
            Button(section.title) { show(section) }
                .keyboardShortcut(key, modifiers: [.command, .shift])
        }
    }

    private func show(_ section: AppSection) {
        AppServices.navigation.show(section)
        MainWindow.show(openWindow)
    }
}
