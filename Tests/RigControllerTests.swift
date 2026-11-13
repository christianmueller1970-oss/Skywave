import Darwin
import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// Wartet, bis `condition` gilt, höchstens `timeout`.
@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5), _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

@Suite struct RigProfileTests {
    @Test func bundledCatalogHasKnownRigs() throws {
        let catalog = RigProfileCatalog.bundled
        #expect(catalog.profiles.count >= 30)
        #expect(catalog.brands.contains("Icom"))
        let ic705 = try #require(catalog.profile(id: "icom-ic705"))
        #expect(ic705.hamlibRigNumber == 3085)
        #expect(ic705.defaultCIVAddress == "0xA4")
    }

    @Test func icomLaunchConfigUsesProfileDefaultsAndOverrides() throws {
        let ic705 = try #require(RigProfileCatalog.bundled.profile(id: "icom-ic705"))
        let standard = ic705.launchConfig(serialPort: "/dev/cu.usbserial-1", listenPort: 4534)
        #expect(standard.model == 3085)
        #expect(standard.civAddress == "0xA4")
        #expect(
            standard.connection
                == .serial(.init(port: "/dev/cu.usbserial-1", baud: 115200)))

        let custom = ic705.launchConfig(
            serialPort: "/dev/cu.usbserial-1", baud: 19200, civAddress: "0x94", listenPort: 4534)
        #expect(custom.civAddress == "0x94")
        #expect(custom.connection == .serial(.init(port: "/dev/cu.usbserial-1", baud: 19200)))
    }

    @Test func dummyRigNeedsNoPort() throws {
        let dummy = try #require(RigProfileCatalog.bundled.profile(id: "hamlib-dummy"))
        let config = dummy.launchConfig(serialPort: "", listenPort: 4534)
        #expect(config.connection == .none)
        #expect(config.civAddress == nil)
    }
}

/// Gegen den echten mitgelieferten rigctld mit Hamlibs Dummy-Gerät —
/// kein Funkgerät nötig.
@MainActor
@Suite(.serialized) struct RigControllerTests {
    private func dummyLink() -> RigController.Link {
        .bundled(RigctldLaunchConfig(model: 1, listenPort: UInt16.random(in: 42000..<48000)))
    }

    @Test func bundledDummyRigConnectsControlsAndDisconnects() async throws {
        let rig = RigController()
        rig.pollInterval = .milliseconds(100)

        await rig.connect(dummyLink(), name: "Hamlib Dummy")
        #expect(rig.status == .connected, "\(rig.status)")
        #expect(rig.rigName == "Hamlib Dummy")
        #expect(rig.frequencyHz != nil)
        let pid = try #require(rig.rigctldPID)

        try await rig.setFrequency(3_611_500)
        try await rig.setMode(.dataUSB)
        try await rig.setPTT(true)
        try await rig.setPTT(false)
        // Die laufende Abfrage bestätigt, was das Gerät meldet.
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.frequencyHz == 3_611_500)
        #expect(rig.modeName == "PKTUSB")
        #expect(try await rig.readMode().name == "PKTUSB")

        await rig.disconnect()
        #expect(rig.status == .disconnected)
        #expect(rig.frequencyHz == nil)
        #expect(rig.rigctldPID == nil)
        // rigctld ist wirklich weg — sonst bliebe der Port belegt.
        #expect(kill(pid, 0) != 0)
    }

    @Test func missingSerialDeviceFailsWithReadableMessage() async throws {
        let rig = RigController()
        let ic705 = try #require(RigProfileCatalog.bundled.profile(id: "icom-ic705"))
        let config = ic705.launchConfig(
            serialPort: "/dev/cu.skywave-gibt-es-nicht",
            listenPort: UInt16.random(in: 42000..<48000))

        await rig.connect(.bundled(config), name: ic705.displayName)
        guard case .failed(let message) = rig.status else {
            Issue.record("erwartet .failed, ist \(rig.status)")
            return
        }
        #expect(message.contains("/dev/cu.skywave-gibt-es-nicht"), "\(message)")
        #expect(rig.rigctldPID == nil)
        #expect(rig.rigName == nil)
    }

    @Test func externalRigctldThatIsNotRunningFails() async {
        let rig = RigController()
        let port = RigController.freeLoopbackPort(startingAt: 48100) ?? 48100
        await rig.connect(.external(host: "127.0.0.1", port: port), name: "rigctld")
        guard case .failed(let message) = rig.status else {
            Issue.record("erwartet .failed, ist \(rig.status)")
            return
        }
        #expect(message.contains("127.0.0.1:\(port)"))
    }

    /// Stirbt rigctld unterwegs (Kabel gezogen, Gerät aus), merkt es die
    /// Abfrage und meldet den Verlust statt alter Werte. Hier ein fremder
    /// rigctld, den der Test selbst startet und beendet.
    @Test func dyingRigctldIsReportedAsLost() async throws {
        let url = try #require(Bundle.main.url(forAuxiliaryExecutable: "rigctld"))
        let port = RigController.freeLoopbackPort(startingAt: 49300) ?? 49300
        let daemon = Process()
        daemon.executableURL = url
        daemon.arguments = ["-m", "1", "-T", "127.0.0.1", "-t", String(port)]
        daemon.standardOutput = FileHandle.nullDevice
        daemon.standardError = FileHandle.nullDevice
        try daemon.run()
        defer { if daemon.isRunning { daemon.terminate() } }

        let rig = RigController()
        rig.pollInterval = .milliseconds(100)
        rig.pollFailureLimit = 2
        // rigctld braucht einen Moment, bis es lauscht.
        for _ in 0..<20 where rig.status != .connected {
            await rig.connect(.external(host: "127.0.0.1", port: port), name: "rigctld")
            if rig.status != .connected { try await Task.sleep(for: .milliseconds(200)) }
        }
        #expect(rig.status == .connected, "\(rig.status)")

        daemon.terminate()
        let lost = await waitUntil(timeout: .seconds(8)) {
            if case .failed = rig.status { return true }
            return false
        }
        #expect(lost)
        #expect(rig.frequencyHz == nil)
    }

    @Test func occupiedPortIsSkipped() async throws {
        let first = RigController()
        let second = RigController()
        let port = UInt16.random(in: 48200..<49000)
        let link = RigController.Link.bundled(RigctldLaunchConfig(model: 1, listenPort: port))

        await first.connect(link, name: "A")
        await second.connect(link, name: "B")
        #expect(first.status == .connected, "\(first.status)")
        #expect(second.status == .connected, "\(second.status)")
        #expect(first.rigctldPID != second.rigctldPID)

        await first.disconnect()
        await second.disconnect()
    }

    @Test func runningUnderTestsIsDetected() {
        #expect(RigController.isRunningTests)
    }

    @Test func killOnTerminateEndsRigctld() async throws {
        let rig = RigController()
        await rig.connect(dummyLink(), name: "Hamlib Dummy")
        let pid = try #require(rig.rigctldPID)

        rig.killOnTerminate()
        let gone = await waitUntil { kill(pid, 0) != 0 }
        #expect(gone)
        await rig.disconnect()
    }
}
