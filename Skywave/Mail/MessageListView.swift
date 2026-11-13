import SwiftUI

/// The message list of one folder (middle column), filtered by the
/// toolbar's search field.
struct MessageListView: View {
    @Environment(MailStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(MailboxCommandCenter.self) private var commands

    let folder: MailFolder
    @Binding var selectedID: MailItem.ID?
    var searchText = ""

    private var query: String {
        searchText.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Searching spans ALL folders — what you look for may be filed
    /// anywhere; each result row shows its folder.
    private var items: [MailItem] {
        guard !query.isEmpty else { return store.items(in: folder) }
        return store.allFolders
            .flatMap { store.items(in: $0) }
            .filter { $0.searchBlob.contains(query) }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        if items.isEmpty {
            if query.isEmpty {
                ContentUnavailableView(
                    emptyTitle, systemImage: folder == .trash ? "trash" : "tray",
                    description: folder == .inbox
                        ? Text("Abrufen holt neue Nachrichten vom CMS.") : Text("")
                )
            } else {
                // Not ContentUnavailableView.search — its text follows
                // the system language, the app is German throughout.
                ContentUnavailableView(
                    "Keine Treffer für «\(searchText)»",
                    systemImage: "magnifyingglass",
                    description: Text("Die Suche umfasst alle Ordner.")
                )
            }
        } else {
            List(items, selection: $selectedID) { item in
                MessageRow(item: item, showsFolder: !query.isEmpty)
                    .tag(item.id)
                    .contextMenu {
                        if item.folder == .drafts {
                            Button("Entwurf bearbeiten") {
                                openWindow(
                                    id: "compose",
                                    value: ComposeIntent(mode: .editDraft, mid: item.id))
                            }
                        } else {
                            MoveToFolderMenu(item: item)
                        }
                        if item.folder == .outbox {
                            OutboxRouteMenu(item: item)
                        }
                        if item.folder.isInboxTree {
                            Button(item.isRead ? "Als ungelesen markieren" : "Als gelesen markieren") {
                                store.markRead(item, !item.isRead)
                            }
                        }
                        Divider()
                        Button(
                            item.folder == .trash ? "Endgültig löschen" : "In den Papierkorb legen",
                            role: .destructive
                        ) {
                            // Über dieselbe Stelle wie Menü und Symbolleiste,
                            // damit das Löschen aus dem Papierkorb nachfragt.
                            selectedID = item.id
                            commands.selectedItem = item
                            commands.send(.deleteMessage)
                        }
                    }
            }
            .listStyle(.inset)
        }
    }

    private var emptyTitle: String {
        switch folder {
        case .inbox: String(localized: "Keine Nachrichten")
        case .drafts: String(localized: "Keine Entwürfe")
        case .outbox: String(localized: "Postausgang leer")
        case .sent: String(localized: "Noch nichts gesendet")
        case .trash: String(localized: "Papierkorb ist leer")
        case .custom: String(localized: "Ordner ist leer")
        }
    }
}

/// Submenu listing all folders a message can be filed into
/// (inbox tree and trash, without the current folder).
struct MoveToFolderMenu: View {
    @Environment(MailStore.self) private var store

    let item: MailItem
    /// Called after the move, e.g. to clear the selection.
    var onMove: (() -> Void)?

    var body: some View {
        let targets = store.allFolders.filter {
            ($0.isInboxTree || $0 == .trash) && $0 != item.folder
        }
        Menu("Verschieben nach") {
            ForEach(targets) { target in
                Button {
                    store.move(item, to: target)
                    onMove?()
                } label: {
                    // Nested folders show their full path so equal
                    // names in different parents stay distinguishable.
                    if case .custom(let path) = target {
                        Label(path, systemImage: "folder")
                    } else {
                        Label(
                            target.displayName,
                            systemImage: target == .trash ? "trash" : "tray")
                    }
                }
            }
        }
    }
}

/// Untermenü «Versandweg» für eine Nachricht im Postausgang: beliebig,
/// nur Internet, nur Funk oder zurückhalten.
struct OutboxRouteMenu: View {
    @Environment(MailStore.self) private var store

    let item: MailItem

    var body: some View {
        Menu("Versandweg") {
            Picker(
                "Versandweg",
                selection: Binding(
                    get: { item.route },
                    set: { store.setRoute($0, for: item) })
            ) {
                ForEach(OutboxRoute.allCases) { route in
                    Label(route.displayName, systemImage: route.symbol)
                        .tag(route)
                        .help(route.help)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

private struct MessageRow: View {
    let item: MailItem
    /// True in search results, which mix folders.
    var showsFolder = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(item.isRead ? .clear : Color.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Own mail (drafts, queued, sent) shows the
                    // recipient, everything else the sender.
                    Text([.drafts, .outbox, .sent].contains(item.folder) ? item.to : item.from)
                        .font(.body.weight(item.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let date = item.date {
                        Text(date.formatted(date: .numeric, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Text(item.subject)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if item.attachmentCount > 0 {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if item.folder.isInboxTree, SavedQueryStore.isQueryAddress(item.from) {
                        Image(systemName: "arrow.down.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Antwort auf eine Abfrage (Katalog/Saildocs)")
                    }
                    if item.folder == .outbox, let tag = item.route.tagLabel {
                        Label(tag, systemImage: item.route.symbol)
                            .font(.caption)
                            .foregroundStyle(item.route == .hold ? .statusWarn : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                            .help(item.route.help)
                    }
                    if showsFolder {
                        Spacer()
                        Text(item.folder.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
