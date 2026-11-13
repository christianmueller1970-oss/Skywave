import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// Funkbetrieb über den RigController: QSY, Zurückstellen und PTT gegen
/// das echte mitgelieferte rigctld mit Hamlibs Dummy-Gerät.
@MainActor
@Suite(.serialized) struct RigExchangeTests {
    private func makeSettings() -> (AppSettingsStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        return (store, dir)
    }

    /// Einstellungen wie nach dem Einrichten im Tab «Funkgerät», mit dem
    /// Dummy-Gerät statt eines Transceivers.
    private func makeBundledDummy() throws -> (ExchangeController, RigController, AppSettingsStore, URL) {
        let (settings, dir) = makeSettings()
        let dummy = try #require(RigProfileCatalog.bundled.profile(id: "hamlib-dummy"))
        settings.rigAccess = .bundled
        settings.selectRigProfile(dummy)
        let rig = RigController()
        rig.pollInterval = .milliseconds(100)
        let exchange = ExchangeController()
        exchange.rig = rig
        return (exchange, rig, settings, dir)
    }

    /// Der Dialog verbindet das Gerät selbst, wenn es eingerichtet, aber
    /// noch nicht verbunden ist; QSY stellt Frequenz und USB-D ein, das
    /// Zurückstellen bringt den alten Stand wieder.
    @Test func qsyViaRigConnectsSetsAndRestores() async throws {
        let (exchange, rig, settings, dir) = try makeBundledDummy()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(settings.rigQSYAvailable)
        #expect(rig.status == .disconnected)

        // Ausgangslage am «Gerät»: 80 m LSB.
        _ = try await exchange.connectedRig(settings: settings)
        try await rig.setFrequency(3_774_000)
        try await rig.setMode(RigctldClient.Mode(name: "LSB", passbandHz: 2400))

        let snapshot = try await exchange.qsyViaRig(to: 3_611_500, settings: settings)
        #expect(snapshot == .rig(
            frequencyHz: 3_774_000, mode: RigctldClient.Mode(name: "LSB", passbandHz: 2400)))
        #expect(try await rig.readFrequency() == 3_611_500)
        #expect(try await rig.readMode().name == "PKTUSB")
        #expect(exchange.log.contains { $0.contains("über rigctld") })

        await exchange.restoreRig(snapshot, settings: settings)
        #expect(try await rig.readFrequency() == 3_774_000)
        #expect(try await rig.readMode().name == "LSB")

        await rig.disconnect()
    }

    /// PTT über den RigController: tasten und entsichern kommen am
    /// Gerät an.
    @Test func keyViaRigKeysAndUnkeys() async throws {
        let (exchange, rig, settings, dir) = try makeBundledDummy()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(settings.usesBundledRigPTT)
        _ = try await exchange.connectedRig(settings: settings)

        await exchange.keyViaRig(true, rig: rig)
        #expect(try await rig.readPTT())
        await exchange.keyViaRig(false, rig: rig)
        #expect(try await rig.readPTT() == false)
        #expect(!exchange.log.contains { $0.contains("fehlgeschlagen") })

        await rig.disconnect()
    }

    /// Ohne Verbindung scheitert das Tasten auch im Wiederholversuch —
    /// die Sitzung wird mit PTT-Fehler abgebrochen statt stumm zu senden.
    /// App-Ende in der Sendephase: der Handler der Sitzung hat getastet,
    /// das Beenden entsichert am Gerät, und ein verspätetes «PTT ein»
    /// des Modems kommt danach nicht mehr durch.
    @Test func terminationUnkeysAndBlocksLateKeying() async throws {
        let (exchange, rig, settings, dir) = try makeBundledDummy()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try await exchange.connectedRig(settings: settings)
        #expect(!exchange.needsUnkeyOnTermination)

        let handler = exchange.pttHandlerViaRig(rig)
        #expect(exchange.needsUnkeyOnTermination)
        await handler(true)
        #expect(try await rig.readPTT())

        await exchange.unkeyForTermination()
        #expect(try await rig.readPTT() == false)

        await handler(true)
        #expect(try await rig.readPTT() == false)
        #expect(!exchange.log.contains { $0.contains("fehlgeschlagen") })

        await rig.disconnect()
    }

    /// Beginnt das App-Ende in der Wartezeit vor dem Wiederholversuch,
    /// wird nicht noch einmal getastet (Codex-Review 2026-11-12).
    @Test func terminationDuringRetryPauseDoesNotKeyAgain() async throws {
        let (exchange, rig, _, dir) = try makeBundledDummy()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Nicht verbunden: der erste Versuch scheitert sofort, dann 200 ms Pause.
        let keying = Task { await exchange.keyViaRig(true, rig: rig) }
        try await Task.sleep(for: .milliseconds(60))
        await exchange.unkeyForTermination(limit: .milliseconds(50))
        await keying.value
        // Ohne die Sperre scheiterte der Wiederholversuch und meldete einen PTT-Fehler.
        #expect(!exchange.log.contains { $0.contains("fehlgeschlagen") })
    }

    /// Ein Gerät, das nicht antwortet, hält das Beenden nicht auf.
    @Test func terminationUnkeyGivesUpAfterLimit() async throws {
        let (exchange, rig, _, dir) = try makeBundledDummy()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Nicht verbunden: das Entsichern scheitert, die Sperre greift trotzdem.
        _ = exchange.pttHandlerViaRig(rig)
        let clock = ContinuousClock()
        let started = clock.now
        await exchange.unkeyForTermination(limit: .milliseconds(300))
        #expect(clock.now - started < .seconds(2))
        #expect(exchange.isTerminating)
        #expect(!exchange.mayKey(true))
        #expect(exchange.mayKey(false))
    }

    @Test func keyViaRigWithoutConnectionFailsThePTT() async throws {
        let exchange = ExchangeController()
        let rig = RigController()

        await exchange.keyViaRig(true, rig: rig)
        #expect(exchange.log.contains { $0.contains("PTT ein fehlgeschlagen") })
    }

    /// Ist nichts eingerichtet, sagt die Meldung, wo das geht.
    @Test func connectedRigWithoutSetupExplainsWhereToGo() async throws {
        let (settings, dir) = makeSettings()
        defer { try? FileManager.default.removeItem(at: dir) }
        settings.rigAccess = .bundled  // noch kein Modell gewählt
        let exchange = ExchangeController()
        exchange.rig = RigController()

        do {
            _ = try await exchange.connectedRig(settings: settings)
            Issue.record("erwartet einen Fehler")
        } catch let error as WinlinkError {
            guard case .remoteError(let message) = error else {
                Issue.record("unerwartet: \(error)")
                return
            }
            #expect(message.contains("Funkgerät"))
        }
    }
}
