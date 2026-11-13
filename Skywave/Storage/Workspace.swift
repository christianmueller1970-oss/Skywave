import Foundation
import Observation

/// All stores over one data folder. Created as soon as the folder is
/// known; replaced wholesale when the user picks a different one.
@MainActor @Observable final class Workspace {
    let root: URL
    let settings: AppSettingsStore
    let store: MailStore
    let contacts: ContactsStore
    let signatures: SignatureStore
    let gateways: GatewayStore
    let queries: SavedQueryStore
    let history: ConnectionHistoryStore

    init(root: URL) {
        self.root = root
        settings = AppSettingsStore(
            fileURL: root.appendingPathComponent("settings.json"))
        store = MailStore(
            root: root.appendingPathComponent("Mailbox", isDirectory: true))
        contacts = ContactsStore(
            fileURL: root.appendingPathComponent("contacts.json"))
        signatures = SignatureStore(
            fileURL: root.appendingPathComponent("signatures.json"))
        gateways = GatewayStore(
            fileURL: root.appendingPathComponent("gateways.json"))
        queries = SavedQueryStore(
            fileURL: root.appendingPathComponent("queries.json"))
        history = ConnectionHistoryStore(
            fileURL: root.appendingPathComponent("connection-history.json"))
    }
}

/// App-level root object: owns the storage location and the workspace
/// over it. `workspace` stays nil until the user granted a folder.
@MainActor @Observable final class AppModel {
    let location = StorageLocation()
    private(set) var workspace: Workspace?

    init() {
        if let root = location.root {
            workspace = Workspace(root: root)
        }
    }

    /// Folder picker (first launch or Settings ▸ «Ordner ändern»);
    /// existing data is copied along, the old folder stays untouched.
    func chooseFolder() {
        guard let root = location.chooseFolder() else { return }
        workspace = Workspace(root: root)
    }
}
