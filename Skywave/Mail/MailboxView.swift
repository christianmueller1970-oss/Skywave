import AppKit
import SwiftUI

/// Das Hauptfenster: links die Bereiche (Postfach, Funk, Werkzeuge),
/// rechts der gewählte Bereich — im Postfach Nachrichtenliste und
/// Lesebereich.
struct MailboxView: View {
    @Environment(MailStore.self) private var store
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ExchangeController.self) private var exchange
    @Environment(SavedQueryStore.self) private var queries
    @Environment(ConnectionHistoryStore.self) private var history
    @Environment(AppNavigation.self) private var nav
    @Environment(MailboxCommandCenter.self) private var commands
    @Environment(\.openWindow) private var openWindow

    @State private var selectedID: MailItem.ID?
    @State private var searchText = ""
    @State private var showingLog = false
    @State private var radioSheetKind: RadioTransportKind?
    @State private var showingP2P = false
    @State private var showingLevelTuning = false

    // Folder management dialogs.
    @State private var newFolderParent: MailFolder?
    @State private var newFolderName = ""
    @State private var renamingFolder: MailFolder?
    @State private var renameText = ""
    @State private var deletingFolder: MailFolder?
    @State private var confirmingEmptyTrash = false
    @State private var folderError: String?
    @State private var confirmingDeleteMessage = false

    /// Der Ordner, auf den sich Liste und Ordner-Dialoge beziehen — auch
    /// während ein anderer Bereich offen ist.
    private var selectedFolder: MailFolder { nav.section.folder ?? nav.lastFolder }

    private var selectedFolderBinding: Binding<MailFolder> {
        Binding(get: { selectedFolder }, set: { nav.show(.folder($0)) })
    }

    /// Looked up across all folders: search results mix folders, so
    /// the selection may live outside the selected one.
    private var selectedItem: MailItem? {
        guard let selectedID else { return nil }
        if let item = store.items(in: selectedFolder).first(where: { $0.id == selectedID }) {
            return item
        }
        return store.allFolders.lazy
            .flatMap { store.items(in: $0) }
            .first { $0.id == selectedID }
    }

    var body: some View {
        @Bindable var exchange = exchange

        // Die Funk-Leiste steht unter dem ganzen Fenster, nicht als
        // safeAreaInset: die Detailspalte hält den Einzug nicht ein, die
        // Knöpfe am unteren Rand eines Bereichs lägen sonst darunter.
        VStack(spacing: 0) {
            NavigationSplitView {
                sidebar
            } detail: {
                sectionContent
            }
            RadioBar(showingLog: $showingLog)
        }
        .navigationTitle(nav.section.title)
        .toolbar { toolbar }
        .background { ToolbarLabels() }
        .onChange(of: selectedItem, initial: true) { _, item in
            commands.selectedItem = nav.section.folder == nil ? nil : item
        }
        // `initial`: ein Menübefehl kann das geschlossene Hauptfenster erst
        // öffnen — die Anforderung liegt dann schon bereit, bevor diese
        // View existiert, und ginge sonst verloren.
        .onChange(of: commands.requestSerial, initial: true) {
            if let request = commands.take() { handle(request) }
        }
        .confirmationDialog(
            "Nachricht «\(selectedItem?.subject ?? "")» endgültig löschen?",
            isPresented: $confirmingDeleteMessage
        ) {
            Button("Endgültig löschen", role: .destructive) {
                if let item = selectedItem {
                    selectedID = nil
                    store.delete(item)
                }
            }
        } message: {
            Text("Die Nachricht wird endgültig entfernt.")
        }
        .sheet(item: $radioSheetKind) { kind in
            RadioConnectSheet(kind: kind)
        }
        .sheet(isPresented: $showingP2P) {
            P2PConnectSheet()
        }
        .sheet(isPresented: $showingLevelTuning) {
            LevelTuningSheet()
        }
        .alert(
            "Austausch fehlgeschlagen",
            isPresented: Binding(
                get: { exchange.errorMessage != nil },
                set: { if !$0 { exchange.errorMessage = nil } }
            )
        ) {
            Button("OK") { exchange.errorMessage = nil }
        } message: {
            Text(exchange.errorMessage ?? "")
        }
        .onChange(of: nav.section) {
            selectedID = nil
        }
        .onChange(of: store.customFolderPaths) {
            // The selected folder may just have been renamed or deleted.
            if let folder = nav.section.folder, !store.allFolders.contains(folder) {
                nav.show(.folder(.inbox))
            }
        }
        .folderDialogs(
            newFolderParent: $newFolderParent, newFolderName: $newFolderName,
            renamingFolder: $renamingFolder, renameText: $renameText,
            deletingFolder: $deletingFolder,
            confirmingEmptyTrash: $confirmingEmptyTrash,
            folderError: $folderError,
            store: store, selectedFolder: selectedFolderBinding)
    }

    // MARK: - Symbolleiste und Befehle

    /// Die Symbolleiste, überall mit Beschriftung. Vorn die beiden
    /// Hauptschritte, im Postfach dahinter die Befehle zur gewählten
    /// Nachricht; die anderen Bereiche hängen ihre eigenen Knöpfe an.
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Button {
                    handle(.exchangeInternet)
                } label: {
                    Label("über Internet (CMS)", systemImage: "network")
                }
                Divider()
                ForEach(RadioTransportKind.allCases) { kind in
                    Button("über \(kind.displayName) …") { handle(.radio(kind)) }
                }
                Divider()
                Button("Direktverbindung (P2P) …") { handle(.p2p) }
            } label: {
                if exchange.isRunning {
                    Label {
                        Text("Abrufen & Senden")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    Label("Abrufen & Senden", systemImage: "envelope.arrow.triangle.branch")
                }
            } primaryAction: {
                handle(.exchangeInternet)
            }
            .disabled(exchange.isRunning)
            .help(exchangeHelp)

            Button {
                openWindow(id: "compose")
            } label: {
                Label("Neue Nachricht", systemImage: "square.and.pencil")
            }
            .help("Neue Nachricht verfassen (⌘N)")
        }
        if nav.section.folder != nil {
            ToolbarItemGroup {
                let item = selectedItem
                let state = MessageCommandState(item: item)
                if state.canEditDraft {
                    Button {
                        compose(.editDraft)
                    } label: {
                        Label("Bearbeiten", systemImage: "square.and.pencil.circle")
                    }
                    .help("Entwurf weiterschreiben (⌘O)")
                } else {
                    Button {
                        compose(.reply)
                    } label: {
                        Label("Antworten", systemImage: "arrowshape.turn.up.left")
                    }
                    .disabled(!state.canReply)
                    .help("Dem Absender antworten (⌘R) — allen antworten: Menü «Nachricht»")
                    Button {
                        compose(.forward)
                    } label: {
                        Label("Weiterleiten", systemImage: "arrowshape.turn.up.right")
                    }
                    .disabled(!state.canReply)
                    .help("Nachricht samt Anhängen weiterleiten (⇧⌘F)")
                }
                if let item, state.canRoute {
                    Menu {
                        OutboxRouteMenu(item: item)
                    } label: {
                        Label("Versandweg", systemImage: item.route.symbol)
                    }
                    .help("Versandweg: \(item.route.displayName) — \(item.route.help)")
                }
                Menu {
                    if let item, state.canMove {
                        MoveToFolderMenu(item: item, onMove: { selectedID = nil })
                    }
                } label: {
                    Label("Verschieben", systemImage: "folder")
                }
                .disabled(!state.canMove)
                .help("Nachricht in einen anderen Ordner verschieben")
                Button {
                    handle(.deleteMessage)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                .disabled(!state.canDelete)
                .help(state.deleteTitle + " (⌘⌫)")
            }
        }
    }

    private func compose(_ mode: ComposeIntent.Mode) {
        guard let item = selectedItem else { return }
        openWindow(id: "compose", value: ComposeIntent(mode: mode, mid: item.id))
    }

    /// Führt aus, was Menüleiste oder Symbolleiste verlangen.
    private func handle(_ request: MailboxRequest) {
        switch request {
        case .newFolder:
            newFolderName = ""
            newFolderParent = FolderCommandState(
                section: nav.section, trashIsEmpty: true).newFolderParent
        case .renameFolder:
            guard let folder = nav.section.folder, case .custom = folder else { return }
            renameText = folder.displayName
            renamingFolder = folder
        case .deleteFolder:
            guard let folder = nav.section.folder, case .custom = folder else { return }
            deletingFolder = folder
        case .emptyTrash:
            confirmingEmptyTrash = true
        case .deleteMessage:
            guard let item = selectedItem else { return }
            // In den Papierkorb legen ist umkehrbar — ohne Rückfrage.
            // Aus dem Papierkorb löschen ist endgültig und fragt nach.
            if item.folder == .trash {
                confirmingDeleteMessage = true
            } else {
                selectedID = nil
                store.delete(item)
            }
        case .exchangeInternet:
            guard !exchange.isRunning else { return }
            Task { await exchange.exchange(store: store, settings: settings, history: history) }
        case .radio(let kind):
            guard !exchange.isRunning else { return }
            radioSheetKind = kind
        case .p2p:
            guard !exchange.isRunning else { return }
            showingP2P = true
        case .showLog:
            showingLog = true
        case .levelAssistant:
            guard !exchange.isRunning, !exchange.isTuning else { return }
            showingLevelTuning = true
        }
    }

    // MARK: - Bereiche

    /// Der Inhalt rechts der Seitenleiste, je nach gewähltem Bereich.
    @ViewBuilder private var sectionContent: some View {
        switch nav.section {
        case .folder(let folder):
            HSplitView {
                MessageListView(folder: folder, selectedID: $selectedID, searchText: searchText)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 460, maxHeight: .infinity)
                Group {
                    if let item = selectedItem {
                        MessageDetailView(item: item)
                    } else {
                        // Statt einer leeren Fläche: was wartet, wann zuletzt
                        // ausgetauscht wurde, wo das Funkgerät steht.
                        OverviewView()
                    }
                }
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            }
            .searchable(text: $searchText, placement: .toolbar, prompt: "Suchen")
        case .gateways:
            GatewayDirectoryView()
                // Nach dem Verbinden zurück ins Postfach: dort kommt an,
                // was die Sitzung holt.
                .environment(\.finishSection, FinishSectionAction { nav.show(.folder(.inbox)) })
        case .connections:
            ConnectionHistoryView()
        case .logs:
            SessionLogsView()
        case .rig:
            RigPanelView()
        case .contacts:
            ContactsView()
        case .position:
            PositionReportView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Die Meldung liegt danach im Postausgang — dorthin wechseln.
                .environment(\.finishSection, FinishSectionAction { nav.show(.folder(.outbox)) })
        case .queries:
            QueriesSectionView()
                // Der Assistent öffnet das Fenster «Neue Nachricht» und
                // bleibt für die nächste Abfrage stehen.
                .environment(\.finishSection, FinishSectionAction {})
        }
    }

    /// Tooltip des Hauptknopfs: nennt, was ein Internet-Austausch jetzt
    /// mitnehmen würde und was die Kennzeichnung zurückhält.
    private var exchangeHelp: String {
        var text = String(localized: """
            Klick: mit dem Winlink-CMS über Internet austauschen (⇧⌘R). \
            Pfeil: über Funk (VARA/ARDOP) oder direkt zu einer Station (P2P).
            """)
        let going = store.outboundMIDs(for: .internet).count
        let held = store.heldItems(for: .internet).count
        if going > 0 || held > 0 {
            text += "\n"
            text += going == 1 ? String(localized: "1 Nachricht geht über Internet raus") : String(localized: "\(going) Nachrichten gehen über Internet raus")
            if held > 0 {
                text += held == 1 ? String(localized: ", 1 bleibt zurückgehalten") : String(localized: ", \(held) bleiben zurückgehalten")
            }
            text += "."
        }
        return text
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(
            selection: Binding(get: { nav.section }, set: { nav.show($0) })
        ) {
            Section("Postfach") {
                FolderTreeItem(
                    folder: .inbox,
                    row: { AnyView(row(for: $0)) }
                )
                row(for: .drafts)
                row(for: .outbox)
                row(for: .sent)
                row(for: .trash)
            }
            Section("Funk") {
                ForEach(AppSection.radio, id: \.self) { sectionRow($0) }
            }
            Section("Werkzeuge") {
                ForEach(AppSection.tools, id: \.self) { sectionRow($0) }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        // Der Standardknopf für die Seitenleiste landete mit beschrifteter
        // Symbolleiste im Überlauf-Menü; er steht jetzt unter «Darstellung».
        .toolbar(removing: .sidebarToggle)
        .contextMenu(forSelectionType: AppSection.self) { sections in
            if let folder = sections.first?.folder {
                folderContextMenu(for: folder)
            }
        }
    }

    private func row(for folder: MailFolder) -> some View {
        sectionLabel(.folder(folder))
            .badge(badgeCount(for: folder))
            .tag(AppSection.folder(folder))
    }

    private func sectionRow(_ section: AppSection) -> some View {
        sectionLabel(section)
            .tag(section)
    }

    /// Zeile der Seitenleiste mit dem Symbol in der Farbe ihrer Gruppe.
    private func sectionLabel(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbol)
                .foregroundStyle(section.tint)
        }
    }

    @ViewBuilder
    private func folderContextMenu(for folder: MailFolder) -> some View {
        if folder.isInboxTree {
            Button("Neuer Ordner …") {
                newFolderName = ""
                newFolderParent = folder
            }
        }
        if case .custom = folder {
            Button("Umbenennen …") {
                renameText = folder.displayName
                renamingFolder = folder
            }
            Divider()
            Button("Ordner löschen", role: .destructive) {
                deletingFolder = folder
            }
        }
        if folder == .trash {
            Button("Papierkorb leeren", role: .destructive) {
                confirmingEmptyTrash = true
            }
            .disabled(store.items(in: .trash).isEmpty)
        }
    }

    /// Inbox tree: unread. Outbox: everything still queued. Others: nothing.
    private func badgeCount(for folder: MailFolder) -> Int {
        switch folder {
        case .outbox: store.items(in: .outbox).count
        default: folder.isInboxTree ? store.unreadCount(in: folder) : 0
        }
    }
}

// MARK: - Folder tree

/// One folder in the sidebar; renders its subfolders recursively in a
/// DisclosureGroup (expanded by default).
private struct FolderTreeItem: View {
    @Environment(MailStore.self) private var store

    let folder: MailFolder
    let row: (MailFolder) -> AnyView

    @State private var isExpanded = true

    private var children: [MailFolder] {
        store.customFolderPaths
            .filter { path in
                switch folder {
                case .inbox: !path.contains("/")
                case .custom(let parent):
                    path.hasPrefix(parent + "/")
                        && !path.dropFirst(parent.count + 1).contains("/")
                default: false
                }
            }
            .map(MailFolder.custom)
    }

    var body: some View {
        if children.isEmpty {
            row(folder)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(children) { child in
                    FolderTreeItem(folder: child, row: row)
                }
            } label: {
                row(folder)
            }
        }
    }
}

// MARK: - Folder dialogs

extension View {
    /// All alerts/dialogs for folder management, in one place to keep
    /// the main view readable.
    fileprivate func folderDialogs(
        newFolderParent: Binding<MailFolder?>, newFolderName: Binding<String>,
        renamingFolder: Binding<MailFolder?>, renameText: Binding<String>,
        deletingFolder: Binding<MailFolder?>,
        confirmingEmptyTrash: Binding<Bool>,
        folderError: Binding<String?>,
        store: MailStore, selectedFolder: Binding<MailFolder>
    ) -> some View {
        self
            .alert(
                "Neuer Ordner in «\(newFolderParent.wrappedValue?.displayName ?? "")»",
                isPresented: Binding(
                    get: { newFolderParent.wrappedValue != nil },
                    set: { if !$0 { newFolderParent.wrappedValue = nil } }
                )
            ) {
                TextField("Name", text: newFolderName)
                Button("Anlegen") {
                    guard let parent = newFolderParent.wrappedValue else { return }
                    do {
                        selectedFolder.wrappedValue = try store.createFolder(
                            named: newFolderName.wrappedValue, under: parent)
                    } catch {
                        folderError.wrappedValue = error.localizedDescription
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert(
                "Ordner «\(renamingFolder.wrappedValue?.displayName ?? "")» umbenennen",
                isPresented: Binding(
                    get: { renamingFolder.wrappedValue != nil },
                    set: { if !$0 { renamingFolder.wrappedValue = nil } }
                )
            ) {
                TextField("Name", text: renameText)
                Button("Umbenennen") {
                    guard let folder = renamingFolder.wrappedValue else { return }
                    do {
                        let renamed = try store.renameFolder(
                            folder, to: renameText.wrappedValue)
                        if selectedFolder.wrappedValue == folder {
                            selectedFolder.wrappedValue = renamed
                        }
                    } catch {
                        folderError.wrappedValue = error.localizedDescription
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog(
                "Ordner «\(deletingFolder.wrappedValue?.displayName ?? "")» löschen?",
                isPresented: Binding(
                    get: { deletingFolder.wrappedValue != nil },
                    set: { if !$0 { deletingFolder.wrappedValue = nil } }
                )
            ) {
                Button("Ordner löschen", role: .destructive) {
                    guard let folder = deletingFolder.wrappedValue else { return }
                    store.deleteFolder(folder)
                }
            } message: {
                Text("Enthaltene Nachrichten wandern in den Papierkorb, Unterordner werden entfernt.")
            }
            .confirmationDialog(
                "Papierkorb leeren?",
                isPresented: confirmingEmptyTrash
            ) {
                Button("Endgültig löschen", role: .destructive) {
                    store.emptyTrash()
                }
            } message: {
                Text("Alle Nachrichten im Papierkorb werden endgültig entfernt.")
            }
            .alert(
                "Ordner-Aktion fehlgeschlagen",
                isPresented: Binding(
                    get: { folderError.wrappedValue != nil },
                    set: { if !$0 { folderError.wrappedValue = nil } }
                )
            ) {
                Button("OK") { folderError.wrappedValue = nil }
            } message: {
                Text(folderError.wrappedValue ?? "")
            }
    }
}

/// Schaltet die Symbolleiste des Fensters fest auf «Symbol und Text».
/// SwiftUI zeigt Beschriftungen sonst nur, wenn der Nutzer das über
/// «Symbolleiste anpassen» wählt — hier sollen sie immer stehen.
private struct ToolbarLabels: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? Probe)?.apply()
    }

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            // Die Toolbar entsteht mitunter erst nach dem Einhängen.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let toolbar = window?.toolbar else { return }
            toolbar.displayMode = .iconAndLabel
            toolbar.allowsUserCustomization = false
            if #available(macOS 15.0, *) {
                toolbar.allowsDisplayModeCustomization = false
            }
        }
    }
}
