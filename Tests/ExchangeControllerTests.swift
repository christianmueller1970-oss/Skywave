import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// Minimal in-memory duplex transport (same idea as WinlinkKit's
/// internal test helper, which is not exported).
private actor TestPipe: WinlinkTransport {
    private var inbox = [Data]()
    private var waiter: CheckedContinuation<Data, Never>?
    private var closed = false
    private var peer: TestPipe?

    static func pair() async -> (TestPipe, TestPipe) {
        let a = TestPipe()
        let b = TestPipe()
        await a.connect(to: b)
        await b.connect(to: a)
        return (a, b)
    }

    private func connect(to peer: TestPipe) { self.peer = peer }

    private func deliver(_ data: Data) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: data)
        } else {
            inbox.append(data)
        }
    }

    private func finishReads() {
        closed = true
        waiter?.resume(returning: Data())
        waiter = nil
    }

    func read() async throws -> Data {
        if !inbox.isEmpty { return inbox.removeFirst() }
        if closed { return Data() }
        return await withCheckedContinuation { waiter = $0 }
    }

    func write(_ data: Data) async { await peer?.deliver(data) }

    func close() async { await peer?.finishReads() }
}

/// Reads CR-separated lines from the pipe until one equals `line`.
private func readUntil(_ line: String, on pipe: TestPipe) async throws {
    var buffer = ""
    while true {
        let chunk = try await pipe.read()
        if chunk.isEmpty {
            Issue.record("Connection closed before '\(line)' was received")
            return
        }
        buffer += String(decoding: chunk, as: UTF8.self)
        if buffer.split(separator: "\r").map(String.init).contains(line) {
            return
        }
    }
}

/// Merkt sich die gestellten Pegel — ersetzt das ARDOP-TNC.
private actor FakeDriveModem: LevelTunableModem {
    private(set) var levels = [Int]()
    func setDriveLevel(_ level: Int) async throws { levels.append(level) }
    func sendTwoToneTest() async throws {}
}

@MainActor
@Suite struct ExchangeControllerTests {
    /// Hand-Tune: Ein Burst startet nur, wenn er vor der Frist endet —
    /// mit 5-s-Bursts und 200 ms Pause passt in 15 s kein dritter.
    @Test func manualTuneBurstMustEndBeforeDeadline() {
        let start = ContinuousClock.now
        let deadline = start + ExchangeController.manualTuneLimit
        let burst = ArdopModem.twoToneDuration
        let gap = burst + .milliseconds(200)
        #expect(ExchangeController.burstFits(before: deadline, startingAt: start, burst: burst))
        #expect(
            ExchangeController.burstFits(before: deadline, startingAt: start + gap, burst: burst))
        #expect(
            !ExchangeController.burstFits(
                before: deadline, startingAt: start + gap + gap, burst: burst))
    }

    /// Der Pegel-Regler: ohne Sitzung passiert nichts, mit Modem kommt
    /// nur der zuletzt gestellte Wert an.
    @Test func driveLevelReachesActiveModemCoalesced() async throws {
        let controller = ExchangeController()
        let modem = FakeDriveModem()
        controller.driveLevelDebounce = .milliseconds(40)

        controller.applyDriveLevel(40)  // keine Sitzung
        try await Task.sleep(for: .milliseconds(120))
        #expect(await modem.levels.isEmpty)

        controller.activeDriveModem = modem
        controller.applyDriveLevel(60)
        controller.applyDriveLevel(55)  // überholt 60
        try await Task.sleep(for: .milliseconds(250))
        #expect(await modem.levels == [55])
        #expect(controller.log.last == "Sendepegel 55 %")
    }


    /// A scripted no-traffic session: the controller reports success,
    /// collects the log and reloads the store.
    @Test func scriptedEmptyExchange() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()

        // The fake CMS on the far end.
        let cms = Task {
            await server.write(Data("[WL2K-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("Test CMS >\r".utf8))
            try await readUntil("FF", on: server)
            await server.write(Data("FQ\r".utf8))
        }

        try await controller.run(
            over: client, targetcall: "wl2k", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store)
        try await cms.value

        #expect(controller.errorMessage == nil)
        // No isolated-test-server warning: the default host is
        // production, the warning only fires for cms-z.
        #expect(controller.summary == "Keine neuen Nachrichten.")
        #expect(!controller.log.isEmpty)
        #expect(!controller.isRunning)
    }

    /// The session announces Skywave (not WinlinkKit) as the client SID.
    @Test func sessionAnnouncesSkywaveSID() async throws {
        #expect(ExchangeController.userAgent.name == "Skywave")
        #expect(!ExchangeController.userAgent.name.contains("-"))
    }

    /// The radio session runs against a gateway callsign instead of
    /// the fixed CMS target — same seam, different targetcall.
    @Test func runWithGatewayTargetcall() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()

        // The fake RMS gateway on the far end.
        let rms = Task {
            await server.write(Data("[RMS-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("HB9AK >\r".utf8))
            try await readUntil("FF", on: server)
            await server.write(Data("FQ\r".utf8))
        }

        try await controller.run(
            over: client, targetcall: "HB9AK", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store)
        try await rms.value

        #expect(controller.errorMessage == nil)
        #expect(controller.summary == "Keine neuen Nachrichten.")
    }

    /// The persisted ARDOP bandwidth string parses in all its forms.
    @Test func ardopBandwidthValidation() {
        #expect(ExchangeController.ardopBandwidth(from: "2000MAX")?.max == 2000)
        #expect(ExchangeController.ardopBandwidth(from: "2000MAX")?.forced == false)
        #expect(ExchangeController.ardopBandwidth(from: "500FORCED")?.forced == true)
        #expect(ExchangeController.ardopBandwidth(from: "500")?.max == 500)
        // Nil falls back to the default instead of failing.
        #expect(ExchangeController.ardopBandwidth(from: nil) != nil)
        #expect(ExchangeController.ardopBandwidth(from: "kaputt") == nil)
        #expect(ExchangeController.ardopBandwidth(from: "300") == nil)
    }

    /// A user-initiated abort ends the session with "Abgebrochen."
    /// and no error alert.
    @Test func abortSuppressesErrorAlert() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()

        // Like the radio path: closing the "modem" unblocks the session.
        controller.canAbort = true
        controller.abortAction = { await server.close() }

        let session = Task {
            try await controller.run(
                over: client, targetcall: "HB9AK", password: nil,
                mycall: "HB9HJI", locator: "JN47PN", store: store)
        }

        // Fake gateway: greet, wait for the client's FF, then — instead
        // of answering — the user aborts.
        await server.write(Data("[RMS-5.0-B2FWIHJM$]\r".utf8))
        await server.write(Data("HB9AK >\r".utf8))
        try await readUntil("FF", on: server)
        controller.abortExchange()

        try await session.value
        #expect(controller.summary == "Abgebrochen.")
        #expect(controller.errorMessage == nil)
        #expect(controller.log.contains("Abbruch angefordert …"))
    }

    /// A session error must not hide messages that already arrived —
    /// the user would otherwise burn air time on a pointless retry.
    @Test func errorReportsPartialTraffic() {
        let controller = ExchangeController()
        controller.fail(
            with: WinlinkError.connectionClosed,
            partial: TrafficStats(received: ["MID1", "MID2"]))
        #expect(
            controller.errorMessage?.contains(
                "Bereits übertragen: 2 Nachrichten empfangen.") == true)
    }

    /// Same for a user abort: the summary names what already made it.
    @Test func abortReportsPartialTraffic() {
        let controller = ExchangeController()
        controller.canAbort = true
        controller.abortAction = {}
        controller.abortExchange()
        controller.fail(
            with: WinlinkError.connectionClosed,
            partial: TrafficStats(received: ["MID1"], sent: ["MID2"]))
        #expect(
            controller.summary
                == "Abgebrochen — bereits übertragen: 1 Nachricht gesendet, 1 Nachricht empfangen.")
        #expect(controller.errorMessage == nil)
    }

    /// A failed PTT un-key aborts the session and warns loudly — the
    /// radio may still be transmitting (MacWinlink beta21 lesson).
    @Test func pttFailureAbortsSessionWithWarning() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()

        // Like the radio path: closing the "modem" unblocks the session.
        controller.canAbort = true
        controller.abortAction = { await server.close() }

        let session = Task {
            try await controller.run(
                over: client, targetcall: "HB9AK", password: nil,
                mycall: "HB9HJI", locator: "JN47PN", store: store)
        }

        await server.write(Data("[RMS-5.0-B2FWIHJM$]\r".utf8))
        await server.write(Data("HB9AK >\r".utf8))
        try await readUntil("FF", on: server)
        controller.failPTT(keyOn: false, error: "connection lost")

        try await session.value
        #expect(controller.errorMessage?.contains("nicht enttasten") == true)
        #expect(controller.summary == nil)
        #expect(controller.log.contains("Breche Sitzung wegen PTT-Fehler ab …"))
    }
}

/// Reads CR-separated lines from the pipe until one starts with `prefix`.
private func readUntil(prefix: String, on pipe: TestPipe) async throws {
    var buffer = ""
    while true {
        let chunk = try await pipe.read()
        if chunk.isEmpty {
            Issue.record("Connection closed before a '\(prefix)' line was received")
            return
        }
        buffer += String(decoding: chunk, as: UTF8.self)
        if buffer.split(separator: "\r").contains(where: { $0.hasPrefix(prefix) }) {
            return
        }
    }
}

/// The `F>` checksum: negated 8-bit sum of the proposal lines, CR included.
private func blockPrompt(_ lines: [String]) -> String {
    var sum = 0
    for line in lines {
        for scalar in line.unicodeScalars { sum += Int(scalar.value) }
        sum += 13
    }
    return String(format: "F> %02X", (-sum) & 0xff)
}

@MainActor
@Suite struct VersandkontrolleTests {

    /// Eine als «zurückhalten» gekennzeichnete Nachricht wird dem CMS
    /// nicht angeboten und bleibt im Postausgang; die Zusammenfassung
    /// sagt das.
    @Test func heldMessageIsNotOffered() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let sentMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "geht raus", body: "a")
        let heldMID = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "bleibt", body: "b")
        store.setRoute(.hold, for: try #require(store.items(in: .outbox).first { $0.id == heldMID }))

        let (client, server) = await TestPipe.pair()
        let cms = Task {
            await server.write(Data("[WL2K-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("Test CMS >\r".utf8))
            try await readUntil(prefix: "F>", on: server)
            // Das CMS kennt die Nachricht schon — abgelehnt zählt als
            // erledigt, ohne dass Daten fliessen müssen.
            await server.write(Data("FS -\r".utf8))
            await server.write(Data("FF\r".utf8))
            try await readUntil("FQ", on: server)
        }

        try await controller.run(
            over: client, targetcall: "wl2k", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store, path: .internet)
        try await cms.value

        #expect(controller.errorMessage == nil)
        #expect(controller.summary == "Keine neuen Nachrichten, 1 zurückgehalten.")
        #expect(store.items(in: .outbox).map(\.id) == [heldMID])
        #expect(store.items(in: .sent).map(\.id) == [sentMID])
        #expect(controller.log.contains("1 Nachricht bleibt zurückgehalten im Postausgang"))
    }

    /// Über Funk wird eine Nachricht über der Grenze zurückgestellt
    /// (`=`), nicht geladen — und die Zusammenfassung nennt sie.
    @Test func largeInboundIsDeferredOverRadio() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()
        let proposal = "FC EM ABCDEFGHIJKL 48123 9000 0"
        let rms = Task {
            await server.write(Data("[RMS-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("HB9AK >\r".utf8))
            try await readUntil("FF", on: server)
            await server.write(Data(";PM: HB9HJI ABCDEFGHIJKL 9000 HB9ABC Grosses Bild\r".utf8))
            await server.write(Data((proposal + "\r").utf8))
            await server.write(Data((blockPrompt([proposal]) + "\r").utf8))
            try await readUntil("FS =", on: server)
            try await readUntil("FF", on: server)
            await server.write(Data("FQ\r".utf8))
        }

        try await controller.run(
            over: client, targetcall: "HB9AK", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store,
            path: .radio(.ardop, gateway: "HB9AK"), maxInboundBytes: 20_000)
        try await rms.value

        #expect(controller.errorMessage == nil)
        #expect(controller.summary == "Keine neuen Nachrichten, 1 zurückgestellt (48 kB).")
        #expect(store.items(in: .inbox).isEmpty)
        #expect(controller.log.contains { $0.hasPrefix("Zurückgestellt: «Grosses Bild» (48 kB") })
    }

    /// Dieselbe Grenze greift über Internet nicht.
    @Test func inboundLimitIgnoredOverInternet() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()
        let proposal = "FC EM ABCDEFGHIJKL 48123 9000 0"
        let cms = Task {
            await server.write(Data("[WL2K-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("Test CMS >\r".utf8))
            try await readUntil("FF", on: server)
            await server.write(Data((proposal + "\r").utf8))
            await server.write(Data((blockPrompt([proposal]) + "\r").utf8))
            try await readUntil("FS +", on: server)
            // Kein Nachrichtentransfer im Test: Verbindung beenden.
            await server.close()
        }

        try? await controller.run(
            over: client, targetcall: "wl2k", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store,
            path: .internet, maxInboundBytes: 20_000)
        try await cms.value
        #expect(!controller.log.contains { $0.hasPrefix("Zurückgestellt") })
    }
}

@MainActor
@Suite struct GatewayHistoryTests {

    /// Eine Sitzung landet mit Ergebnis, Dauer und Statistik in der
    /// Historie; ein Abbruch wird als solcher vermerkt.
    @Test func sessionOutcomeIsRecorded() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root)
        let history = ConnectionHistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let controller = ExchangeController()

        let (client, server) = await TestPipe.pair()
        let rms = Task {
            await server.write(Data("[RMS-5.0-B2FWIHJM$]\r".utf8))
            await server.write(Data("HB9AK >\r".utf8))
            try await readUntil("FF", on: server)
            await server.write(Data("FQ\r".utf8))
        }
        let started = Date()
        try await controller.run(
            over: client, targetcall: "HB9AK", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store)
        try await rms.value
        #expect(controller.lastRunOutcome == .success)

        controller.recordHistory(
            history, started: started, gateway: "HB9AK", kind: .ardop, centerHz: 3_614_500)
        let record = try #require(history.records.first)
        #expect(record.outcome == .success)
        #expect(record.gateway == "HB9AK")
        #expect(record.kind == .ardop)
        #expect(record.band == "80 m")
        #expect(record.errorText == nil)
        #expect(record.durationSeconds >= 0)

        // Ohne Sitzung (Modem schon gescheitert): fehlgeschlagen mit Text.
        controller.errorMessage = "Kein Modem"
        let failed = ExchangeController()
        failed.errorMessage = "Kein Modem"
        failed.recordHistory(history, started: started, gateway: "HB9AK", kind: .varaHF, centerHz: nil)
        #expect(history.records.first?.outcome == .failed)
        #expect(history.records.first?.errorText == "Kein Modem")
        #expect(history.lastSuccess(gateway: "HB9AK", kind: .ardop)?.id == record.id)
    }
}

@MainActor
@Suite struct P2PExchangeTests {

    /// Empfangsbereit angerufen: Skywave tauscht als Master aus, gibt
    /// nur die Post exklusiv an den Anrufer heraus und nimmt dessen
    /// Post an. Die Gegenstation ist eine echte B2FSession.
    @Test func listenedSessionExchangesOnlyPeerMail() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(root: root.appendingPathComponent("me"))
        let peerBox = DirectoryMailbox(root: root.appendingPathComponent("peer"))
        let controller = ExchangeController()

        let forPeer = try await store.compose(
            mycall: "HB9HJI", to: "HB9XYZ", subject: "Direkt", body: "Hallo HB9XYZ")
        let other = try await store.compose(
            mycall: "HB9HJI", to: "HB9ABC", subject: "Fremd", body: "bleibt hier")
        var incoming = B2Message(mycall: "HB9XYZ")
        incoming.addTo("HB9HJI")
        incoming.setSubject("Antwort")
        incoming.setBody("73\n")
        try await peerBox.addOutbound(incoming)

        let (mine, theirs) = await TestPipe.pair()
        let peer = Task {
            let session = B2FSession(
                mycall: "HB9XYZ", targetcall: "HB9HJI", locator: "JN47", mailbox: peerBox)
            return try await session.exchange(over: theirs)
        }
        try await controller.run(
            over: mine, targetcall: "HB9XYZ", password: nil,
            mycall: "HB9HJI", locator: "JN47PN", store: store,
            path: .p2p(.ardop, peer: "HB9XYZ"), isMaster: true)
        let peerStats = try await peer.value

        #expect(controller.errorMessage == nil)
        #expect(peerStats.received.count == 1)
        #expect(store.items(in: .sent).map(\.id) == [forPeer])
        #expect(store.items(in: .outbox).map(\.id) == [other])
        #expect(store.items(in: .inbox).map(\.subject) == ["Antwort"])
    }

    @Test func pathNamesShowPeerAndListening() {
        #expect(ExchangePath.p2p(.ardop, peer: "HB9XYZ").displayName == "ARDOP P2P ↔ HB9XYZ")
        #expect(ExchangePath.p2p(.varaHF, peer: nil).displayName == "VARA HF P2P · empfangsbereit")
        #expect(ExchangePath.p2p(.ardop, peer: nil).isRadio)
        #expect(OutboxRoute.radio.allows(.p2p(.ardop, peer: "HB9XYZ")))
        #expect(!OutboxRoute.internet.allows(.p2p(.ardop, peer: "HB9XYZ")))
        #expect(RadioLinkMode.peerListen.path(.ardop) == .p2p(.ardop, peer: nil))
        #expect(!RadioLinkMode.peerCall("HB9XYZ").usesPassword)
        #expect(RadioLinkMode.gateway("HB9AK").usesPassword)
    }
}
