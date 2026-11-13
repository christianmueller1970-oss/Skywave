import Foundation
import WinlinkKit

/// Die Mailbox-Sicht einer einzelnen Sitzung: wickelt die
/// `DirectoryMailbox` ein und setzt die Versandkontrolle durch.
///
/// - Ausgang: nur die MIDs in `allowedMIDs` werden angeboten — der
///   Store berechnet sie aus der Kennzeichnung (`OutboxRoute`) für den
///   Weg der Sitzung, der Verbindungsdialog kann einzelne abwählen.
/// - Eingang: über Funk werden Nachrichten über `maxInboundBytes`
///   zurückgestellt (`=`), das CMS bietet sie beim nächsten Mal wieder
///   an — etwa beim nächsten Internet-Abruf. 0 = keine Grenze.
///
/// Alles andere geht unverändert an die innere Mailbox.
actor SessionMailbox: MailboxHandler {
    private let inner: DirectoryMailbox
    private let allowedMIDs: Set<String>
    private let maxInboundBytes: Int
    private let logLine: (@Sendable (String) -> Void)?

    /// Eine zurückgestellte eingehende Nachricht, für die Zusammenfassung.
    struct Deferred: Equatable, Sendable {
        let mid: String
        let subject: String
        let sizeBytes: Int
    }

    private(set) var deferred: [Deferred] = []

    init(
        inner: DirectoryMailbox, allowedMIDs: Set<String>, maxInboundBytes: Int = 0,
        logLine: (@Sendable (String) -> Void)? = nil
    ) {
        self.inner = inner
        self.allowedMIDs = allowedMIDs
        self.maxInboundBytes = max(0, maxInboundBytes)
        self.logLine = logLine
    }

    func prepare() async throws {
        try await inner.prepare()
    }

    func outboundMessages(for forwarders: [Address]) async -> [B2Message] {
        await inner.outboundMessages(for: forwarders)
            .filter { allowedMIDs.contains($0.mid) }
    }

    func markSent(_ mid: String, rejected: Bool) async {
        await inner.markSent(mid, rejected: rejected)
    }

    func markDeferred(_ mid: String) async {
        await inner.markDeferred(mid)
    }

    func processInbound(_ message: B2Message) async throws {
        try await inner.processInbound(message)
    }

    func inboundAnswer(for proposal: Proposal) async -> ProposalAnswer {
        let answer = await inner.inboundAnswer(for: proposal)
        guard answer == .accept, maxInboundBytes > 0,
            proposal.uncompressedSize > maxInboundBytes
        else { return answer }

        let subject = proposal.pendingMessage?.subject ?? proposal.proposalTitle
        deferred.append(
            Deferred(mid: proposal.messageID, subject: subject, sizeBytes: proposal.uncompressedSize))
        logLine?(String(localized:
            "Zurückgestellt: «\(subject)» (\(Self.kilobytes(proposal.uncompressedSize)) kB, Grenze \(Self.kilobytes(maxInboundBytes)) kB)"))
        return .defer_
    }

    /// «48» für 48'123 Bytes; unter 1 kB «0,5».
    static func kilobytes(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1000
        return kb < 10 ? String(format: "%.1f", kb).replacingOccurrences(of: ".", with: ",") : String(Int(kb.rounded()))
    }
}
