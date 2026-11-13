import Foundation
import Observation

/// One reusable mail signature.
struct Signature: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var name = String(localized: "Signatur")
    var text = ""
}

/// All signatures plus which one is the default, persisted as JSON in
/// the data folder (`signatures.json`). Every mutation saves
/// immediately.
@MainActor @Observable final class SignatureStore {
    private(set) var signatures: [Signature] = []
    private(set) var defaultID: Signature.ID?

    private let fileURL: URL

    private struct Persisted: Codable {
        var signatures: [Signature]
        var defaultID: Signature.ID?
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    /// The signature new messages start with (nil = none configured).
    var defaultSignature: Signature? {
        signatures.first { $0.id == defaultID }
    }

    @discardableResult
    func add() -> Signature {
        var signature = Signature()
        // "Signatur", "Signatur 2", "Signatur 3", … without duplicates.
        let names = Set(signatures.map(\.name))
        if names.contains(signature.name) {
            var counter = 2
            while names.contains(String(localized: "Signatur \(counter)")) { counter += 1 }
            signature.name = String(localized: "Signatur \(counter)")
        }
        signatures.append(signature)
        // The first signature becomes the default automatically.
        if defaultID == nil {
            defaultID = signature.id
        }
        save()
        return signature
    }

    func update(_ signature: Signature) {
        guard let index = signatures.firstIndex(where: { $0.id == signature.id }) else { return }
        signatures[index] = signature
        save()
    }

    func remove(_ signature: Signature) {
        signatures.removeAll { $0.id == signature.id }
        if defaultID == signature.id {
            defaultID = signatures.first?.id
        }
        save()
    }

    func setDefault(_ signature: Signature?) {
        defaultID = signature?.id
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        signatures = decoded.signatures
        defaultID = decoded.defaultID
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(
            Persisted(signatures: signatures, defaultID: defaultID))
        else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
