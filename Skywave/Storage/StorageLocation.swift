import AppKit
import Foundation
import Observation

/// Where Skywave keeps its user data: one folder (typically
/// Dokumente/Skywave) holding the mailbox, contacts, signatures and
/// settings as plain files.
///
/// The app is sandboxed, so the user grants access once through an
/// open panel; a security-scoped bookmark keeps the grant across
/// launches. Only the bookmark itself lives in UserDefaults — it is
/// machine-specific plumbing, not user data.
@MainActor @Observable final class StorageLocation {
    private static let bookmarkKey = "dataFolderBookmark"

    /// The granted data folder, nil until the user picked one.
    private(set) var root: URL?

    init() {
        root = Self.resolveBookmark()
    }

    /// Restores access from the saved bookmark, refreshing it when
    /// macOS marks it stale. Returns nil when there is no bookmark or
    /// the folder is gone.
    private static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data, options: [.withSecurityScope],
                relativeTo: nil, bookmarkDataIsStale: &isStale),
            url.startAccessingSecurityScopedResource(),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        if isStale, let fresh = try? url.bookmarkData(options: [.withSecurityScope]) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    /// Asks the user for the data folder and migrates existing data
    /// into it. Returns the new root, or nil if the user cancelled.
    @discardableResult
    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Diesen Ordner verwenden")
        panel.message = String(localized: """
            Ordner für die Skywave-Daten wählen — z. B. einen neuen Ordner \
            «Skywave» in deinen Dokumenten (unten links «Neuer Ordner»).
            """)
        panel.directoryURL = Self.realDocumentsFolder()

        guard panel.runModal() == .OK, let chosen = panel.url else { return nil }
        // Access to the chosen folder covers its descendants, so the
        // data root (possibly a created subfolder) can be bookmarked.
        _ = chosen.startAccessingSecurityScopedResource()
        let url = Self.dataRoot(within: chosen)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope]) else {
            return nil
        }

        Self.migrate(into: url, from: root)

        // Swap the grant: keep holding the old scope until the new one
        // is active, then persist the new bookmark.
        _ = url.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        root = url
        return url
    }

    /// The actual data root for a folder the user picked. Choosing a
    /// non-empty folder that is not already a Skywave data folder
    /// (say, Dokumente itself) must not spray files between the
    /// user's documents — use a «Skywave» subfolder instead.
    static func dataRoot(within chosen: URL) -> URL {
        let fm = FileManager.default
        let isDataFolder =
            fm.fileExists(atPath: chosen.appendingPathComponent("settings.json").path)
            || fm.fileExists(atPath: chosen.appendingPathComponent("Mailbox").path)
        let visibleEntries =
            ((try? fm.contentsOfDirectory(atPath: chosen.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
        if isDataFolder || visibleEntries.isEmpty || chosen.lastPathComponent == "Skywave" {
            return chosen
        }
        return chosen.appendingPathComponent("Skywave", isDirectory: true)
    }

    /// Copies existing data into `root` — from the previous data
    /// folder when switching, otherwise from the legacy location in
    /// the app container. Never overwrites: a folder that already has
    /// data keeps it.
    static func migrate(into root: URL, from oldRoot: URL?) {
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let source = oldRoot ?? legacy
        for name in ["Mailbox", "contacts.json", "signatures.json", "settings.json"] {
            let src = source.appendingPathComponent(name)
            let dst = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path)
            else { continue }
            try? fm.copyItem(at: src, to: dst)
        }
        // First move out of the container: carry the settings that
        // used to live in UserDefaults over into settings.json.
        AppSettingsStore.seedFromLegacyDefaults(
            fileURL: root.appendingPathComponent("settings.json"))
    }

    /// The user's real ~/Documents — `homeDirectoryForCurrentUser`
    /// points into the sandbox container, so ask the passwd database.
    private static func realDocumentsFolder() -> URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }
}
