import Darwin
import Foundation
import Observation
import WinlinkKit

/// Hält die Verbindung zum Funkgerät über rigctld: startet den
/// mitgelieferten rigctld (oder dockt an einen fremden an), liest
/// laufend Frequenz und Modus und stellt PTT, QSY und Messwerte bereit.
///
/// Die Verbindung bleibt über die ganze Laufzeit der App offen — rigctld
/// hält den seriellen Port, ardopcf tastet in diesem Fall nicht selbst.
@MainActor @Observable final class RigController {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        /// Verbindungsaufbau gescheitert oder Verbindung verloren; der
        /// Text ist für den Nutzer formuliert.
        case failed(String)
    }

    /// Der Weg zum Funkgerät.
    enum Link: Equatable {
        /// Skywave startet den mitgelieferten rigctld selbst.
        case bundled(RigctldLaunchConfig)
        /// Ein rigctld, den jemand anderes gestartet hat.
        case external(host: String, port: UInt16)
    }

    private(set) var status = Status.disconnected
    /// Zuletzt gelesene Dial-Frequenz; nil ohne Verbindung.
    private(set) var frequencyHz: Int?
    /// Zuletzt gelesener Modus in Hamlib-Schreibweise («PKTUSB»).
    private(set) var modeName: String?
    /// Anzeigename des verbundenen Geräts («Icom IC-705»).
    private(set) var rigName: String?

    var isConnected: Bool { status == .connected }

    /// Erster Port für den mitgelieferten rigctld. Bewusst nicht 4532:
    /// dort lauschen HAM-Tools, wfview und andere.
    static let bundledBasePort: UInt16 = 4534

    /// Abstand der Frequenz-/Modusabfragen. Internal: Test-Naht.
    var pollInterval: Duration = .seconds(1)
    /// So viele Abfragen in Folge dürfen scheitern, bevor die Verbindung
    /// als verloren gilt.
    var pollFailureLimit = 3
    /// Liefert das rigctld-Binary. Internal: Test-Naht.
    var executable: () -> URL? = { Bundle.main.url(forAuxiliaryExecutable: "rigctld") }

    private var process: RigctldProcess?
    private var client: RigctldClient?
    private var pollTask: Task<Void, Never>?
    /// PID des mitgelieferten rigctld — genauer: seines Aufsehers im Kit,
    /// der ein Signal an rigctld weiterreicht — für den synchronen Abbau
    /// beim Beenden der App.
    private(set) var rigctldPID: Int32?
    /// Zählt Verbindungsversuche — ein Trennen während des Aufbaus
    /// macht den laufenden Versuch ungültig.
    private var generation = 0
    private static let firstReadAttempts = 4

    // MARK: - Verbinden und Trennen

    /// Baut die Verbindung auf. Fehler landen in `status`, nicht als
    /// Wurf — die Oberfläche zeigt den Status ohnehin an.
    func connect(_ link: Link, name: String) async {
        guard status != .connecting, status != .connected else { return }
        generation += 1
        let attempt = generation
        status = .connecting
        rigName = name
        frequencyHz = nil
        modeName = nil

        var startedProcess: RigctldProcess?
        do {
            let host: String
            let port: UInt16
            var device = ""
            switch link {
            case .bundled(var config):
                guard let url = executable() else {
                    throw Failure(
                        String(localized: "Der mitgelieferte rigctld fehlt im App-Bundle — bitte Skywave neu installieren."))
                }
                // Ein belegter Port würde die Bereitschaftsprobe täuschen:
                // sie träfe den fremden Dienst statt unseren rigctld.
                guard let free = Self.freeLoopbackPort(startingAt: config.listenPort) else {
                    throw Failure(String(localized: "Kein freier lokaler Port für rigctld gefunden."))
                }
                config.listenPort = free
                device = Self.deviceText(config)
                let child = RigctldProcess(executable: url, config: config)
                startedProcess = child
                do {
                    try await child.start()
                } catch let error as RigctldProcessError {
                    startedProcess = nil
                    throw Failure(Self.describe(error, config: config))
                }
                host = "127.0.0.1"
                port = free
            case .external(let externalHost, let externalPort):
                host = externalHost
                port = externalPort
            }

            // Die erste Abfrage ist der eigentliche Test: rigctld kann
            // laufen, ohne dass das Gerät antwortet.
            //
            // Jeder Versuch öffnet eine frische Verbindung. Die
            // Bereitschaftsprobe des Prozessstarts war für rigctld ein
            // Client, der gleich wieder ging; in dieser Lücke trennt es
            // gelegentlich auch die nächste Verbindung («Socket is not
            // connected»), und eine tote Verbindung erholt sich nicht.
            var connected: (rig: RigctldClient, hz: Int)?
            var reachedDaemon = false
            var readError = ""
            for attempt in 0..<Self.firstReadAttempts {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(300)) }
                guard let candidate = try? await RigctldClient.connect(host: host, port: port)
                else { continue }
                reachedDaemon = true
                do {
                    connected = (candidate, try await candidate.frequency())
                    break
                } catch {
                    readError = "\(error)"
                    await candidate.close()
                }
            }
            guard reachedDaemon else {
                throw Failure(String(localized: "Keine Verbindung zu rigctld an \(host):\(String(port)) — läuft er?"))
            }
            guard let (rig, hz) = connected else {
                throw Failure(String(localized:
                    "Das Funkgerät\(device) antwortet nicht — eingeschaltet? Modell, Port und Baudrate prüfen. (\(readError))"))
            }
            let mode = try? await rig.mode()

            guard attempt == generation else {
                // Inzwischen getrennt: aufräumen, Status nicht anfassen.
                await rig.close()
                await startedProcess?.stop()
                return
            }
            process = startedProcess
            rigctldPID = await startedProcess?.processIdentifier
            client = rig
            frequencyHz = hz
            modeName = mode?.name
            status = .connected
            startPolling(attempt)
        } catch {
            await startedProcess?.stop()
            guard attempt == generation else { return }
            rigName = nil
            status = .failed((error as? Failure)?.message ?? error.localizedDescription)
        }
    }

    /// Trennt die Verbindung und beendet den mitgelieferten rigctld;
    /// danach ist der serielle Port wieder frei.
    func disconnect() async {
        generation += 1
        await teardown()
        status = .disconnected
        rigName = nil
    }

    private func teardown() async {
        pollTask?.cancel()
        pollTask = nil
        let rig = client
        let child = process
        client = nil
        process = nil
        rigctldPID = nil
        frequencyHz = nil
        modeName = nil
        await rig?.close()
        await child?.stop()
    }

    /// Synchroner Abbau für `NSApplication.willTerminate` — dort lässt
    /// sich nicht mehr auf den Actor warten. Bei Absturz oder hartem
    /// Beenden greift stattdessen der Aufseher im Kit (`RigctldProcess`):
    /// rigctld endet, sobald Skywave verschwindet.
    func killOnTerminate() {
        if let pid = rigctldPID {
            kill(pid, SIGTERM)
            rigctldPID = nil
        }
    }

    // MARK: - Abfragen

    private func startPolling(_ attempt: Int) {
        pollTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                guard let self, let rig = self.client, attempt == self.generation else { return }
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                do {
                    let hz = try await rig.frequency()
                    let mode = try? await rig.mode()
                    guard attempt == self.generation else { return }
                    self.frequencyHz = hz
                    if let mode { self.modeName = mode.name }
                    failures = 0
                } catch {
                    failures += 1
                    guard attempt == self.generation else { return }
                    if failures >= self.pollFailureLimit {
                        await self.connectionLost(attempt)
                        return
                    }
                }
            }
        }
    }

    private func connectionLost(_ attempt: Int) async {
        guard attempt == generation else { return }
        generation += 1
        pollTask = nil
        await teardown()
        rigName = nil
        status = .failed(
            String(localized: "Verbindung zum Funkgerät verloren — Kabel und Stromversorgung prüfen, dann neu verbinden."))
    }

    // MARK: - Steuern

    private func connectedClient() throws -> RigctldClient {
        guard let client, status == .connected else {
            throw WinlinkError.remoteError(String(localized: "Das Funkgerät ist nicht verbunden."))
        }
        return client
    }

    func setFrequency(_ hz: Int) async throws {
        try await connectedClient().setFrequency(hz)
        frequencyHz = hz
    }

    func setMode(_ mode: RigctldClient.Mode) async throws {
        try await connectedClient().setMode(mode)
        modeName = mode.name
    }

    /// Liest den Modus samt Filterbreite frisch vom Gerät — für das
    /// Zurückstellen nach einer Sitzung.
    func readMode() async throws -> RigctldClient.Mode {
        try await connectedClient().mode()
    }

    func readFrequency() async throws -> Int {
        try await connectedClient().frequency()
    }

    func setPTT(_ on: Bool) async throws {
        try await connectedClient().setPTT(on)
    }

    /// Ob das Gerät gerade sendet, frisch gelesen.
    func readPTT() async throws -> Bool {
        try await connectedClient().ptt()
    }

    /// ALC 0…1, nur beim Senden aussagekräftig; nil, wenn das Gerät sie
    /// nicht liefert.
    func alc() async -> Double? {
        guard let client else { return nil }
        return try? await client.alc()
    }

    func powerWatts() async -> Double? {
        guard let client else { return nil }
        return try? await client.powerWatts()
    }

    // MARK: - Hilfen

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// Nutzertext für einen gescheiterten rigctld-Start.
    static func describe(_ error: RigctldProcessError, config: RigctldLaunchConfig) -> String {
        let device = deviceText(config)
        switch error {
        case .launchFailed(let reason):
            return String(localized: "Der mitgelieferte rigctld liess sich nicht starten: \(reason)")
        case .terminatedEarly(_, let log):
            let tail = log.filter { !$0.isEmpty }.suffix(2).joined(separator: " · ")
            return String(localized:
                "rigctld konnte das Funkgerät\(device) nicht öffnen — Modell, Port und Baudrate prüfen; hält ein anderes Programm den Port?")
                + (tail.isEmpty ? "" : " (\(tail))")
        case .readyTimeout:
            return String(localized: "rigctld meldet sich nicht\(device) — bitte erneut versuchen.")
        case .portInUse(let port):
            return String(localized:
                "Der Port \(String(port)) für den mitgelieferten rigctld ist bereits belegt — läuft noch ein anderer rigctld? Bitte erneut verbinden.")
        }
    }

    /// True im Testlauf: die Test-App darf das echte Funkgerät des
    /// Nutzers nicht von sich aus verbinden.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// « an /dev/cu… (115200 Baud)» für Fehlermeldungen; leer ohne Gerät.
    static func deviceText(_ config: RigctldLaunchConfig) -> String {
        switch config.connection {
        case .serial(let serial): String(localized: " an \(serial.port) (\(String(serial.baud)) Baud)")
        case .network(let host): String(localized: " an \(host)")
        case .none: ""
        }
    }

    /// Erster freier Loopback-Port ab `start` (höchstens 20 Versuche).
    static func freeLoopbackPort(startingAt start: UInt16) -> UInt16? {
        for offset in 0..<20 {
            let (port, overflow) = start.addingReportingOverflow(UInt16(offset))
            guard !overflow else { return nil }
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            defer { close(fd) }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bound == 0 { return port }
        }
        return nil
    }
}
