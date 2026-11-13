import Foundation
import Observation
import WinlinkKit

/// A mail folder, mapped onto `DirectoryMailbox`'s layout (`in/`,
/// `out/`, `sent/`) plus what the app adds on top: a drafts directory
/// (`drafts/`), a trash directory (`trash/`) and user-created
/// subfolders below the inbox (`in/<path>`, arbitrarily nested).
enum MailFolder: Hashable, Identifiable, Sendable {
    case inbox
    case drafts
    case outbox
    case sent
    case trash
    /// A user-created folder below the inbox; the payload is its
    /// slash-separated path relative to `in/` (e.g. "QSL/2026").
    case custom(String)

    var id: String { relativePath }

    /// Directory path inside the mailbox root.
    var relativePath: String {
        switch self {
        case .inbox: "in"
        case .drafts: "drafts"
        case .outbox: "out"
        case .sent: "sent"
        case .trash: "trash"
        case .custom(let path): "in/\(path)"
        }
    }

    var displayName: String {
        switch self {
        case .inbox: String(localized: "Posteingang")
        case .drafts: String(localized: "Entwürfe")
        case .outbox: String(localized: "Postausgang")
        case .sent: String(localized: "Gesendet")
        case .trash: String(localized: "Papierkorb")
        case .custom(let path):
            String(path.split(separator: "/").last ?? "?")
        }
    }

    /// Inbox and its subfolders hold received mail: they track unread
    /// state and are valid targets for moving messages.
    var isInboxTree: Bool {
        switch self {
        case .inbox, .custom: true
        default: false
        }
    }
}

/// One message as shown in a folder list — the parsed summary of a
/// `.b2f` file on disk.
struct MailItem: Identifiable, Hashable, Sendable {
    let id: String // MID
    let folder: MailFolder
    let from: String
    let to: String
    let subject: String
    let date: Date?
    let attachmentCount: Int
    var isRead: Bool
    let url: URL
    /// Lowercased subject, addresses and body text in one string, so
    /// the search filter needs no re-parsing of the `.b2f` file.
    let searchBlob: String
    /// Grösse der `.b2f`-Datei — das, was unkomprimiert über die
    /// Leitung ginge; Grundlage für die Zeitabschätzung im Funk-Dialog.
    var sizeBytes: Int = 0
    /// Versandweg-Kennzeichnung; nur im Postausgang von Bedeutung.
    var route: OutboxRoute = .any
}

enum MailFolderError: LocalizedError {
    case invalidName
    case alreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            String(localized: "Bitte einen Ordnernamen ohne «/» angeben.")
        case .alreadyExists(let name):
            String(localized: "Ein Ordner namens «\(name)» existiert hier bereits.")
        }
    }
}

/// The app's view onto the mailbox directory.
///
/// Sessions write through the `handler` (a WinlinkKit
/// `DirectoryMailbox`); the store reads the same directories for the
/// UI and adds what the wire format doesn't have: read/unread state
/// (a JSON sidecar), user folders below the inbox, and a trash.
/// Call `reload()` after every exchange.
@MainActor @Observable final class MailStore {
    /// The session-facing side of the same directory tree.
    let handler: DirectoryMailbox

    private(set) var items: [MailFolder: [MailItem]] = [:]

    /// Slash-separated paths of all user folders below `in/`, sorted so
    /// that parents precede their children.
    private(set) var customFolderPaths: [String] = []

    private let root: URL
    private var readMIDs = Set<String>()

    /// Versandweg je MID im Postausgang (Sidecar `outbox-routing.json`).
    /// Fehlende Einträge bedeuten «beliebig»; Einträge zu Nachrichten,
    /// die den Postausgang verlassen haben, räumt `reload()` weg.
    private var routes: [String: OutboxRoute] = [:]

    private var readStateURL: URL {
        root.appendingPathComponent("readstate.json")
    }

    private var routingURL: URL {
        root.appendingPathComponent("outbox-routing.json")
    }

    private var trashURL: URL {
        root.appendingPathComponent(MailFolder.trash.relativePath, isDirectory: true)
    }

    init(root: URL) {
        self.root = root
        self.handler = DirectoryMailbox(root: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        loadReadState()
        loadRouting()
        reload()
    }

    // MARK: - Listing

    /// All folders in sidebar order: inbox tree first, then drafts,
    /// outbox, sent and trash.
    var allFolders: [MailFolder] {
        [.inbox] + customFolderPaths.map(MailFolder.custom)
            + [.drafts, .outbox, .sent, .trash]
    }

    /// Re-scans all folders from disk.
    func reload() {
        customFolderPaths = discoverCustomFolders()
        var result = [MailFolder: [MailItem]]()
        for folder in allFolders {
            result[folder] = scan(folder)
        }
        items = result
        pruneRouting()
    }

    func items(in folder: MailFolder) -> [MailItem] {
        items[folder] ?? []
    }

    /// Unread messages across the inbox and all its subfolders.
    var unreadCount: Int {
        items.reduce(0) { count, entry in
            entry.key.isInboxTree
                ? count + entry.value.filter { !$0.isRead }.count
                : count
        }
    }

    func unreadCount(in folder: MailFolder) -> Int {
        items(in: folder).filter { !$0.isRead }.count
    }

    private func directoryURL(for folder: MailFolder) -> URL {
        root.appendingPathComponent(folder.relativePath, isDirectory: true)
    }

    /// Finds every directory below `in/`, depth-first, as relative paths.
    private func discoverCustomFolders() -> [String] {
        let inbox = directoryURL(for: .inbox)
        guard let enumerator = FileManager.default.enumerator(
            at: inbox, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var paths = [String]()
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { continue }
            let path = url.standardizedFileURL.path
                .replacingOccurrences(of: inbox.standardizedFileURL.path + "/", with: "")
            paths.append(path)
        }
        return paths.sorted()
    }

    private func scan(_ folder: MailFolder) -> [MailItem] {
        let dir = directoryURL(for: folder)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        return files
            .filter { $0.pathExtension == "b2f" }
            .compactMap { url -> MailItem? in
                guard let data = try? Data(contentsOf: url),
                    let message = try? B2Message(parsing: data)
                else { return nil }
                let to = message.to.map(\.description).joined(separator: ", ")
                return MailItem(
                    id: message.mid,
                    folder: folder,
                    from: message.from.description,
                    to: to,
                    subject: message.subject,
                    date: message.date,
                    attachmentCount: message.files.count,
                    // Only received mail (inbox tree) tracks unread state.
                    isRead: !folder.isInboxTree || readMIDs.contains(message.mid),
                    url: url,
                    searchBlob: [message.subject, message.from.description, to, message.bodyText]
                        .joined(separator: "\n").lowercased(),
                    sizeBytes: data.count,
                    route: folder == .outbox ? routes[message.mid] ?? .any : .any
                )
            }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Parses the full message for the reading pane.
    func message(for item: MailItem) -> B2Message? {
        guard let data = try? Data(contentsOf: item.url) else { return nil }
        return try? B2Message(parsing: data)
    }

    /// Finds a message by MID across all folders (used by compose
    /// windows, which outlive the reading pane's selection).
    func message(withMID mid: String) -> B2Message? {
        for folder in allFolders {
            if let item = items(in: folder).first(where: { $0.id == mid }) {
                return message(for: item)
            }
        }
        return nil
    }

    // MARK: - Folder management

    /// Creates a new folder below the inbox (or below another custom
    /// folder). Returns the new folder.
    @discardableResult
    func createFolder(named name: String, under parent: MailFolder = .inbox) throws -> MailFolder {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else {
            throw MailFolderError.invalidName
        }
        guard parent.isInboxTree else { throw MailFolderError.invalidName }

        let path: String =
            if case .custom(let parentPath) = parent { "\(parentPath)/\(name)" } else { name }
        let url = directoryURL(for: .custom(path))
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw MailFolderError.alreadyExists(name)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        reload()
        return .custom(path)
    }

    /// Renames a custom folder; subfolders move with it.
    /// Returns the renamed folder.
    @discardableResult
    func renameFolder(_ folder: MailFolder, to newName: String) throws -> MailFolder {
        guard case .custom(let path) = folder else { throw MailFolderError.invalidName }
        let newName = newName.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, !newName.contains("/") else {
            throw MailFolderError.invalidName
        }

        var components = path.split(separator: "/").map(String.init)
        components[components.count - 1] = newName
        let newPath = components.joined(separator: "/")
        guard newPath != path else { return folder }

        let target = directoryURL(for: .custom(newPath))
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw MailFolderError.alreadyExists(newName)
        }
        try FileManager.default.moveItem(at: directoryURL(for: folder), to: target)
        reload()
        return .custom(newPath)
    }

    /// Deletes a custom folder: its messages (subfolders included) move
    /// to the trash, the directory itself is removed.
    func deleteFolder(_ folder: MailFolder) {
        guard case .custom = folder else { return }
        let url = directoryURL(for: folder)

        try? FileManager.default.createDirectory(
            at: trashURL, withIntermediateDirectories: true)
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil)
        {
            for case let file as URL in enumerator where file.pathExtension == "b2f" {
                moveFile(file, into: trashURL)
            }
        }
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    // MARK: - Moving & deleting messages

    /// Moves a message into another folder (inbox tree or trash).
    func move(_ item: MailItem, to folder: MailFolder) {
        guard folder != item.folder, folder.isInboxTree || folder == .trash else { return }
        let dir = directoryURL(for: folder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        moveFile(item.url, into: dir)
        reload()
    }

    /// Moving keeps the file name (`<MID>.b2f`). If the target already
    /// has this MID it is the same message — drop the source copy.
    private func moveFile(_ source: URL, into directory: URL) {
        let target = directory.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: source)
            }
        }
    }

    // MARK: - Read state & deletion

    func markRead(_ item: MailItem, _ read: Bool = true) {
        if read {
            readMIDs.insert(item.id)
        } else {
            readMIDs.remove(item.id)
        }
        saveReadState()
        reload()
    }

    /// Moves a message to the trash; messages already in the trash are
    /// removed permanently.
    func delete(_ item: MailItem) {
        if item.folder == .trash {
            try? FileManager.default.removeItem(at: item.url)
            readMIDs.remove(item.id)
            saveReadState()
        } else {
            move(item, to: .trash)
        }
        reload()
    }

    /// Permanently removes everything in the trash.
    func emptyTrash() {
        for item in items(in: .trash) {
            try? FileManager.default.removeItem(at: item.url)
            readMIDs.remove(item.id)
        }
        saveReadState()
        reload()
    }

    private func loadReadState() {
        guard let data = try? Data(contentsOf: readStateURL),
            let mids = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return }
        readMIDs = mids
    }

    private func saveReadState() {
        guard let data = try? JSONEncoder().encode(readMIDs) else { return }
        try? data.write(to: readStateURL)
    }

    // MARK: - Versandkontrolle

    /// Kennzeichnet eine Nachricht im Postausgang für einen Weg.
    func setRoute(_ route: OutboxRoute, for item: MailItem) {
        guard item.folder == .outbox else { return }
        if route == .any {
            routes[item.id] = nil
        } else {
            routes[item.id] = route
        }
        saveRouting()
        reload()
    }

    /// Nachrichten im Postausgang, die ausschliesslich an `call` gehen
    /// und über Funk raus dürfen — das, was eine P2P-Sitzung mit dieser
    /// Station anbietet.
    func outboxItems(exclusivelyFor call: String) -> [MailItem] {
        let address = Address(string: call.trimmingCharacters(in: .whitespaces).uppercased())
        let path = ExchangePath.p2p(.ardop, peer: address.addr)
        return items(in: .outbox).filter { item in
            item.route.allows(path) && (message(for: item)?.isOnlyReceiver(address) ?? false)
        }
    }

    /// MIDs im Postausgang, die über `path` raus dürfen.
    func outboundMIDs(for path: ExchangePath) -> Set<String> {
        Set(items(in: .outbox).filter { $0.route.allows(path) }.map(\.id))
    }

    /// Nachrichten im Postausgang, die ihre Kennzeichnung für `path`
    /// zurückhält (nur anderer Weg oder «zurückhalten»).
    func heldItems(for path: ExchangePath) -> [MailItem] {
        items(in: .outbox).filter { !$0.route.allows(path) }
    }

    /// Die Mailbox für eine Sitzung über `path`. `selection` schränkt
    /// die angebotenen Nachrichten zusätzlich ein (Abwahl im Dialog);
    /// nil heisst alle für den Weg erlaubten.
    func makeSessionMailbox(
        path: ExchangePath, selection: Set<String>? = nil, maxInboundBytes: Int = 0,
        logLine: (@Sendable (String) -> Void)? = nil
    ) -> SessionMailbox {
        var allowed = outboundMIDs(for: path)
        if let selection {
            allowed.formIntersection(selection)
        }
        return SessionMailbox(
            inner: handler, allowedMIDs: allowed,
            maxInboundBytes: path.isRadio ? maxInboundBytes : 0,
            logLine: logLine)
    }

    private func loadRouting() {
        guard let data = try? Data(contentsOf: routingURL),
            let decoded = try? JSONDecoder().decode([String: OutboxRoute].self, from: data)
        else { return }
        routes = decoded
    }

    private func saveRouting() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(routes) else { return }
        try? data.write(to: routingURL)
    }

    /// Einträge zu Nachrichten vergessen, die nicht mehr im Postausgang
    /// liegen — gesendet oder gelöscht; die Kennzeichnung ist dann
    /// gegenstandslos.
    private func pruneRouting() {
        let outbox = Set(items(in: .outbox).map(\.id))
        let pruned = routes.filter { outbox.contains($0.key) }
        guard pruned.count != routes.count else { return }
        routes = pruned
        saveRouting()
    }

    // MARK: - Composing

    /// Creates a message and queues it in the outbox. `to` and `cc`
    /// accept multiple addresses separated by comma or semicolon.
    @discardableResult
    func compose(
        mycall: String, to: String, cc: String = "", subject: String, body: String,
        attachments: [B2File] = []
    ) async throws -> String {
        var message = B2Message(mycall: mycall)
        for address in Self.splitAddresses(to) {
            message.addTo(address)
        }
        for address in Self.splitAddresses(cc) {
            message.addCc(address)
        }
        message.setSubject(subject)
        message.setBody(body.hasSuffix("\n") ? body : body + "\n")
        for file in attachments {
            message.addFile(file)
        }
        try await queue(message)
        return message.mid
    }

    /// Validiert eine fertige Nachricht und legt sie in den Postausgang —
    /// für alles, was nicht aus dem Compose kommt (Positionsmeldung).
    func queue(_ message: B2Message) async throws {
        try message.validate()
        try await handler.addOutbound(message)
        reload()
    }

    // MARK: - Drafts

    /// Saves (or overwrites) a draft in `drafts/`. Passing the MID of
    /// an existing draft keeps it stable, so repeated saves update one
    /// file instead of accumulating copies. Drafts are deliberately
    /// not validated — incomplete messages are the point.
    /// Returns the draft's MID.
    @discardableResult
    func saveDraft(
        mid: String? = nil, mycall: String, to: String, cc: String = "",
        subject: String, body: String, attachments: [B2File] = []
    ) throws -> String {
        var message = B2Message(mycall: mycall)
        if let mid {
            message.header.set("Mid", mid)
        }
        for address in Self.splitAddresses(to) {
            message.addTo(address)
        }
        for address in Self.splitAddresses(cc) {
            message.addCc(address)
        }
        message.setSubject(subject)
        message.setBody(body.isEmpty || body.hasSuffix("\n") ? body : body + "\n")
        for file in attachments {
            message.addFile(file)
        }
        let dir = directoryURL(for: .drafts)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try message.bytes().write(to: dir.appendingPathComponent("\(message.mid).b2f"))
        reload()
        return message.mid
    }

    /// Removes a draft file, e.g. after the message was queued.
    func deleteDraft(mid: String) {
        let url = directoryURL(for: .drafts).appendingPathComponent("\(mid).b2f")
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private static func splitAddresses(_ string: String) -> [String] {
        string.split(whereSeparator: { ",;".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
