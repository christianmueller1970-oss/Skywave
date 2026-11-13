import AVFoundation
import Foundation
import Observation
import WinlinkKit

/// Runs one B2F exchange with the CMS ("Abrufen & Senden") — via
/// internet or a radio modem — and exposes its progress to the UI:
/// session log, running state, result summary and user-readable errors.
@MainActor @Observable final class ExchangeController {
    private(set) var isRunning = false
    /// True, solange Pegel-Assistent oder Hand-Tune das Modem halten.
    /// Beide teilen sich mit der Funk-Sitzung ardopcf, Audio und PTT —
    /// sie sperren sich darüber gegenseitig.
    private(set) var isTuning = false
    private(set) var log = [String]()
    private(set) var summary: String?

    /// Verkehr und Zeitpunkt des letzten erfolgreichen Austauschs —
    /// für Menüleisten-Status und Auto-Abruf-Benachrichtigung.
    private(set) var lastStats: TrafficStats?
    private(set) var lastSuccessDate: Date?

    /// Der Weg der laufenden Sitzung — die Statuszeile zeigt ihn, damit
    /// klar ist, ob gerade Internet oder Funk dran ist.
    private(set) var activePath: ExchangePath?

    /// Ergebnis der letzten B2F-Sitzung für die Verbindungs-Historie:
    /// auch ein Abbruch oder Fehler hat Statistik (was vorher durchkam).
    private(set) var lastRunStats: TrafficStats?
    private(set) var lastRunOutcome: ConnectionRecord.Outcome?

    /// Mirrors every log line to a timestamped file so sessions survive
    /// app restarts and can be copied or reviewed later.
    private let sessionLog = SessionLogStore()

    /// True while a radio session can be aborted; the status bar shows
    /// an "Abbrechen" button. Telnet sessions are quick and stay
    /// abort-less. Settable for tests only.
    var canAbort = false

    /// User-readable error of the last exchange; the UI binds an alert
    /// to this.
    var errorMessage: String?

    /// Closes the active modem, unblocking the session (test seam).
    var abortAction: (@Sendable () async -> Void)?
    private var didAbort = false

    /// Das laufende ARDOP-Modem, solange die Funk-Sitzung steht oder der
    /// Hand-Tune läuft. Der Pegel-Regler stellt darüber den Sendepegel
    /// live nach. Nil ohne Sitzung und bei VARA (kennt kein DRIVELEVEL).
    /// Internal: Test-Naht.
    var activeDriveModem: (any LevelTunableModem)?
    private var driveLevelTask: Task<Void, Never>?
    /// Rasche Reglerbewegungen zusammenfassen; es zählt der letzte Wert.
    var driveLevelDebounce: Duration = .milliseconds(150)
    /// True, solange der Sendepegel live nachgestellt werden kann —
    /// in der Funk-Sitzung wie beim Hand-Tune.
    var canAdjustDriveLevel: Bool { activeDriveModem != nil }
    /// Hand-Tune läuft: Zweiton am laufenden Modem, Sender getastet.
    private(set) var isManualTuning = false
    /// «Tune aus» gedrückt, Abbau läuft noch (Burst klingt aus).
    private(set) var isStoppingManualTune = false
    private var manualTuneTask: Task<Void, Never>?
    /// Obergrenze fürs Hand-Tune, damit ein vergessener Knopf den Sender
    /// nicht minutenlang tastet.
    static let manualTuneLimit: Duration = .seconds(15)

    /// Set when a rigctld PTT command failed mid-session; overrides the
    /// error wording so the user learns the radio may still be keyed.
    private var pttFailure: (keyOn: Bool, error: String)?

    /// Entsichert über den PTT-Weg der laufenden Sitzung (oder des
    /// Tune), solange Skywave selbst tastet. Das App-Ende ruft es auf,
    /// bevor die Hilfsprozesse enden: rigctld löst die PTT beim Beenden
    /// nicht von sich aus, der Sender bliebe getastet (2026-11-12 am
    /// IC-7300 gesehen). Nil, wenn ardopcf selbst tastet oder nichts läuft.
    private var terminationUnkey: (@MainActor () async -> Void)?
    /// Die App endet: es wird nicht mehr getastet, nur noch entsichert.
    private(set) var isTerminating = false
    /// Ob das App-Ende auf ein Entsichern warten muss.
    var needsUnkeyOnTermination: Bool { terminationUnkey != nil }

    /// Entsichert vor dem App-Ende und sperrt weiteres Tasten. Wartet
    /// höchstens `limit` — ein Gerät, das nicht antwortet, darf das
    /// Beenden nicht aufhalten.
    func unkeyForTermination(limit: Duration = .seconds(2)) async {
        isTerminating = true
        guard let unkey = terminationUnkey else { return }
        final class Once { var done = false }
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @MainActor () -> Void = {
                guard !once.done else { return }
                once.done = true
                continuation.resume()
            }
            Task { @MainActor in
                await unkey()
                finish()
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                finish()
            }
        }
    }

    /// Falsch für ein «PTT ein», sobald die App endet — ein verspätetes
    /// Tasten des Modems käme sonst nach dem Entsichern am Gerät an.
    func mayKey(_ on: Bool) -> Bool { !(on && isTerminating) }

    /// PTT-Handler für das Modem über den `RigController`; merkt zugleich
    /// das Entsichern fürs App-Ende vor. Internal: Test-Naht.
    func pttHandlerViaRig(_ controller: RigController) -> @Sendable (Bool) async -> Void {
        terminationUnkey = { [weak self] in await self?.unkeyViaRig() }
        return { on in await self.keyViaRig(on, rig: controller) }
    }

    /// Which step the exchange is in — determines how a thrown error
    /// is worded for the user.
    private enum Phase {
        case qsy(qrg: String, viaRig: Bool)
        case modemStart
        case modemConnect(RadioTransportKind, host: String, port: UInt16)
        case rigConnect
        case dial(gateway: String)
        case listen(RadioTransportKind)
        case session
    }
    private var phase = Phase.session

    /// Rig state saved before an automatic QSY, put back after the
    /// session — over the same path the QSY took. Internal: Test-Naht.
    enum RigSnapshot: Equatable {
        /// CI-V direkt (ardopcf owns the port during the session).
        case civ(frequencyHz: Int, mode: CIVClient.OperatingMode)
        /// Über den `RigController` (rigctld, mitgeliefert oder fremd).
        case rig(frequencyHz: Int, mode: RigctldClient.Mode)
    }

    /// Die Verbindung zum Funkgerät über rigctld; die App hängt sie beim
    /// Start ein. Nil in Tests ohne Funkgerät.
    var rig: RigController?

    /// The bundled ardopcf child process while one is running; kept so
    /// app termination can also tear it down.
    private var ardopProcess: ArdopProcess?

    /// PID of the bundled ardopcf, cached so the app-termination hook
    /// can send a synchronous SIGINT without awaiting the actor.
    private(set) var ardopPID: Int32?

    /// Stops a still-running bundled ardopcf (app quit safety net).
    func shutdownModem() async {
        ardopPID = nil
        let process = ardopProcess
        ardopProcess = nil
        await process?.stop()
    }

    /// Synchronous kill for NSApplication.willTerminate — ardopcf
    /// shuts down cleanly on SIGINT.
    func killModemOnTerminate() {
        if let pid = ardopPID {
            kill(pid, SIGINT)
            ardopPID = nil
        }
    }

    /// The app's Winlink client name (SID). Must be registered with
    /// the Winlink Development Team for production CMS servers.
    static var userAgent: (name: String, version: String) {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return (name: "Skywave", version: version ?? "0.0")
    }

    /// Host of the exchange in progress, for user-readable messages.
    private var activeHost = SettingsKeys.defaultCMSHost

    /// Dials the configured CMS and exchanges mail.
    func exchange(
        store: MailStore, settings: AppSettingsStore, history: ConnectionHistoryStore? = nil
    ) async {
        // One keychain read per exchange — every read can trigger a
        // macOS keychain consent dialog, so don't also go through
        // `isConfigured` (which reads the password again).
        let password = Keychain.password() ?? ""
        let mycall = settings.effectiveCallsign
        guard !mycall.isEmpty, !password.isEmpty else {
            errorMessage =
                String(localized: "Bitte zuerst Rufzeichen und Winlink-Passwort in den Einstellungen (⌘,) hinterlegen.")
            return
        }
        guard !isRunning else { return }

        let host = settings.cmsHost
        let port = settings.effectiveCMSPort
        activeHost = host
        phase = .session
        isRunning = true
        activePath = .internet
        let started = Date()
        lastRunStats = nil
        lastRunOutcome = nil
        log = []
        sessionLog.startNewSession()
        summary = nil
        didAbort = false
        pttFailure = nil
        defer {
            isRunning = false
            activePath = nil
        }

        append(String(localized: "Austausch über Internet (CMS)"))
        append(String(localized: "Verbinde mit \(host):\(String(port)) …"))
        do {
            let transport = try await TelnetTransport.dialCMS(
                mycall: mycall, host: host, port: port)
            append(String(localized: "Verbunden, starte B2F-Austausch"))
            try await run(
                over: transport, targetcall: TelnetTransport.cmsTargetCall,
                password: password, mycall: mycall, locator: settings.locator,
                store: store, path: .internet)
        } catch {
            fail(with: error)
            store.reload()
        }
        recordHistory(history, started: started, gateway: host, kind: nil, centerHz: nil)
    }

    /// Dials an RMS gateway over a radio modem and exchanges mail.
    /// `bandwidth` is the raw dialog value: Hz for VARA HF, an
    /// `ArdopBandwidth` string ("2000MAX") for ARDOP, nil for VARA FM.
    /// A non-nil `dialHz` (from the gateway picker) triggers the
    /// automatic QSY to that dial frequency in USB-D — ARDOP with the
    /// integrated TNC and CAT (CI-V) PTT only.
    ///
    /// `selection` sind die im Dialog gewählten Postausgangs-MIDs; nil
    /// bietet alles an, was die Kennzeichnung für Funk zulässt.
    /// `centerHz` ist die Kanalfrequenz aus dem Verzeichnis, nur für die
    /// Historie (Band); `dialHz` steuert den QSY.
    func exchangeRadio(
        kind: RadioTransportKind, gateway: String, bandwidth: String?,
        dialHz: Int? = nil, centerHz: Int? = nil, selection: Set<String>? = nil,
        store: MailStore, settings: AppSettingsStore, history: ConnectionHistoryStore? = nil
    ) async {
        let target = gateway.trimmingCharacters(in: .whitespaces).uppercased()
        guard !target.isEmpty else {
            errorMessage = String(localized: "Bitte ein Gateway-Rufzeichen angeben.")
            return
        }
        await radioSession(
            kind: kind, link: .gateway(target), bandwidth: bandwidth, dialHz: dialHz,
            centerHz: centerHz, selection: selection, store: store, settings: settings,
            history: history)
    }

    /// P2P: ruft eine andere Station direkt, ohne Gateway und ohne
    /// Winlink-Passwort. Angeboten werden nur Nachrichten, die
    /// ausschliesslich an diese Station adressiert sind (WinlinkKit
    /// filtert nach ihrem ;FW).
    func exchangeP2P(
        kind: RadioTransportKind, peer: String, bandwidth: String?, dialHz: Int? = nil,
        selection: Set<String>? = nil,
        store: MailStore, settings: AppSettingsStore, history: ConnectionHistoryStore? = nil
    ) async {
        let target = peer.trimmingCharacters(in: .whitespaces).uppercased()
        guard !target.isEmpty else {
            errorMessage = String(localized: "Bitte das Rufzeichen der Gegenstation angeben.")
            return
        }
        await radioSession(
            kind: kind, link: .peerCall(target), bandwidth: bandwidth, dialHz: dialHz,
            centerHz: nil, selection: selection, store: store, settings: settings,
            history: history)
    }

    /// P2P: empfangsbereit — wartet, bis eine Station anruft, und
    /// tauscht dann als Master aus. Mit `keepListening` geht es nach
    /// einer erfolgreichen Sitzung wieder auf Empfang, bis «Abbrechen».
    func listenP2P(
        kind: RadioTransportKind, dialHz: Int? = nil, keepListening: Bool = false,
        store: MailStore, settings: AppSettingsStore, history: ConnectionHistoryStore? = nil
    ) async {
        repeat {
            // Jeder Durchgang stellt die Frequenz neu ein: mit
            // «QRG zurückstellen» steht das Gerät nach einer Sitzung
            // wieder auf der alten Frequenz.
            await radioSession(
                kind: kind, link: .peerListen, bandwidth: nil, dialHz: dialHz, centerHz: nil,
                selection: nil, store: store, settings: settings, history: history)
        } while keepListening && lastRunOutcome == .success && !didAbort && errorMessage == nil
    }

    /// Gemeinsamer Funkpfad für Gateway, P2P-Ruf und P2P-Empfang:
    /// Modem starten, QSY, PTT, Verbindung aufbauen bzw. abwarten,
    /// B2F-Sitzung, aufräumen.
    private func radioSession(
        kind: RadioTransportKind, link mode: RadioLinkMode, bandwidth: String?,
        dialHz: Int?, centerHz: Int?, selection: Set<String>?,
        store: MailStore, settings: AppSettingsStore, history: ConnectionHistoryStore?
    ) async {
        let mycall = settings.effectiveCallsign
        // Das Passwort nur lesen, wenn es gebraucht wird — jeder Zugriff
        // kann einen Schlüsselbund-Dialog auslösen.
        let password = mode.usesPassword ? (Keychain.password() ?? "") : ""
        guard !mycall.isEmpty, !mode.usesPassword || !password.isEmpty else {
            errorMessage =
                mode.usesPassword
                ? String(localized: "Bitte zuerst Rufzeichen und Winlink-Passwort in den Einstellungen (⌘,) hinterlegen.")
                : String(localized: "Bitte zuerst das Rufzeichen in den Einstellungen (⌘,) hinterlegen.")
            return
        }
        var remote = mode.target
        var ardopBandwidth: ArdopBandwidth?
        if kind == .ardop, !mode.isListen {
            guard let parsed = Self.ardopBandwidth(from: bandwidth) else {
                errorMessage = String(localized: "Ungültige ARDOP-Bandbreite: \(bandwidth ?? "—")")
                return
            }
            ardopBandwidth = parsed
        }
        guard !isRunning else { return }
        guard !isTuning else {
            errorMessage =
                String(localized: "Pegel-Assistent oder Tune läuft noch — bitte zuerst dort beenden.")
            return
        }

        let path = mode.path(kind)
        let maxInboundBytes = settings.radioInboundMaxKB * 1000
        isRunning = true
        activePath = path
        let started = Date()
        lastRunStats = nil
        lastRunOutcome = nil
        log = []
        sessionLog.startNewSession()
        summary = nil
        didAbort = false
        pttFailure = nil
        defer {
            isRunning = false
            activePath = nil
            canAbort = false
            abortAction = nil
            activeDriveModem = nil
            driveLevelTask?.cancel()
            driveLevelTask = nil
        }
        append(String(localized: "Austausch über \(path.displayName)"))
        if maxInboundBytes > 0 {
            append(String(localized: "Eingang über Funk begrenzt auf \(settings.radioInboundMaxKB) kB je Nachricht"))
        }

        // Set before the modem starts, restored after it stopped — in
        // between ardopcf owns the serial port, so no CI-V access then.
        var rigSnapshot: RigSnapshot?

        do {
            switch kind {
            case .varaHF, .varaFM:
                let config = settings.varaConfig
                phase = .modemConnect(kind, host: config.host, port: config.commandPort)
                append(String(localized: "Verbinde mit VARA-Modem an \(config.host):\(String(config.commandPort)) …"))
                let modem = try await VaraModem.connect(
                    mode: kind == .varaFM ? .fm : .hf, mycall: mycall, config: config)
                await modem.setLogLine { line in
                    Task { @MainActor in self.append("vara: \(line)") }
                }
                abortAction = { await modem.close() }
                canAbort = true
                if let version = try? await modem.version() {
                    append(String(localized: "Modem: VARA \(version)"))
                }
                do {
                    let link: VaraConnection
                    switch mode {
                    case .gateway(let target), .peerCall(let target):
                        phase = .dial(gateway: target)
                        append(String(localized: "Rufe \(target) — über Funk kann das dauern …"))
                        link = try await modem.dial(
                            target, bandwidth: kind == .varaHF ? bandwidth : nil,
                            p2p: mode.isPeer)
                    case .peerListen:
                        phase = .listen(kind)
                        append(String(localized: "Empfangsbereit für \(mycall) über \(kind.displayName) — warte auf Anruf …"))
                        link = try await modem.listen(p2p: true)
                    }
                    remote = link.remoteCall ?? remote
                    try await startSession(
                        over: link, kind: kind, mode: mode, remote: remote,
                        password: password, mycall: mycall, settings: settings, store: store,
                        selection: selection, maxInboundBytes: maxInboundBytes)
                } catch {
                    await modem.close()
                    throw error
                }
                await modem.close()

            case .ardop:
                if let dialHz {
                    if settings.civQSYAvailable {
                        rigSnapshot = try await qsy(to: dialHz, settings: settings)
                    } else if settings.rigQSYAvailable {
                        rigSnapshot = try await qsyViaRig(to: dialHz, settings: settings)
                    } else {
                        append(String(localized:
                            "QRG bitte von Hand einstellen: \(GatewayChannel.kilohertz(dialHz)) kHz Dial, USB-D."))
                    }
                }
                var config = settings.ardopConfig
                if settings.ardopUseBundled {
                    let launch = settings.ardopLaunchConfig
                    config = launch.modemConfig
                    phase = .modemStart
                    try await ensureMicrophoneAccess()
                    guard
                        let executable = Bundle.main.url(forAuxiliaryExecutable: "ardopcf")
                    else {
                        throw WinlinkError.remoteError(
                            String(localized: "Das integrierte ardopcf fehlt im App-Bundle — bitte Skywave neu installieren."))
                    }
                    append(String(localized: "Starte integriertes ardopcf-Modem …"))
                    let process = ArdopProcess(executable: executable, config: launch)
                    ardopProcess = process
                    Task {
                        for await line in process.logLines {
                            await MainActor.run { self.append("ardopcf: \(line)") }
                        }
                    }
                    do {
                        try await process.start()
                    } catch {
                        ardopProcess = nil
                        throw error
                    }
                    ardopPID = await process.processIdentifier
                    append(String(localized: "ardopcf läuft (Port \(String(launch.controlPort)))."))
                }
                defer {
                    // Backstop only — the normal paths await
                    // shutdownModem() before getting here.
                    if let process = ardopProcess {
                        ardopProcess = nil
                        ardopPID = nil
                        Task { await process.stop() }
                    }
                }
                phase = .modemConnect(kind, host: config.host, port: config.controlPort)
                append(String(localized: "Verbinde mit ARDOP-TNC an \(config.host):\(String(config.controlPort)) …"))
                let modem: ArdopModem
                do {
                    modem = try await ArdopModem.connect(
                        mycall: mycall, gridSquare: settings.locator, config: config)
                } catch {
                    // Stop a bundled ardopcf deterministically — the
                    // QRG restore below needs the serial port free.
                    await shutdownModem()
                    throw error
                }
                await modem.setLogLine { line in
                    Task { @MainActor in self.append("ardop: \(line)") }
                }
                abortAction = { await modem.close() }
                canAbort = true
                if let version = try? await modem.version() {
                    append(String(localized: "TNC: \(version)"))
                }
                // Sendepegel setzen. Das TNC startet sonst mit voller
                // Amplitude, die auf einem Dateneingang übersteuert.
                activeDriveModem = modem
                do {
                    try await modem.setDriveLevel(settings.ardopDriveLevel)
                    append(String(localized: "Sendepegel \(settings.ardopDriveLevel) %"))
                } catch {
                    // Kein Grund die Sitzung abzubrechen — das TNC sendet
                    // dann mit seiner Vorgabe, wie bisher auch.
                    append(String(localized: "Warnung: Sendepegel konnte nicht gesetzt werden (\(String(describing: error)))"))
                }
                var rig: RigctldClient?
                // Tastet Skywave über den mitgelieferten rigctld, wird am
                // Ende auf jedem Weg entsichert — auch nach einem Fehler.
                var keysViaRigController = false
                defer { terminationUnkey = nil }
                do {
                    if settings.usesBundledRigPTT {
                        phase = .rigConnect
                        let controller = try await connectedRig(settings: settings)
                        keysViaRigController = true
                        append(String(localized: "PTT über \(controller.rigName ?? "rigctld")"))
                        await modem.setPTTHandler(pttHandlerViaRig(controller))
                    }
                    if settings.rigctldEnabled {
                        let host = settings.rigctldHost
                        let port = UInt16(clamping: settings.rigctldPort)
                        phase = .rigConnect
                        append(String(localized: "Verbinde mit rigctld an \(host):\(String(port)) für PTT …"))
                        do {
                            rig = try await RigctldClient.connect(host: host, port: port)
                        } catch {
                            throw WinlinkError.remoteError(String(localized: """
                                Keine Verbindung zu rigctld (\(host):\(String(port))) — \
                                ohne PTT würde nichts gesendet. Läuft rigctld? \
                                In den Einstellungen (Funk) den Host leeren, um \
                                PTT über rigctld zu deaktivieren.
                                """))
                        }
                        let pttRig = rig
                        terminationUnkey = { try? await pttRig?.setPTT(false) }
                        await modem.setPTTHandler { on in
                            guard await self.mayKey(on) else { return }
                            do {
                                try await pttRig?.setPTT(on)
                            } catch {
                                // Without PTT nothing is transmitted, and a
                                // failed un-key can leave the rig on the air —
                                // one retry, then abort loudly instead of
                                // limping on.
                                do {
                                    try await Task.sleep(for: .milliseconds(200))
                                    guard await self.mayKey(on) else { return }
                                    try await pttRig?.setPTT(on)
                                } catch {
                                    Task { @MainActor in
                                        self.failPTT(keyOn: on, error: "\(error)")
                                    }
                                }
                            }
                        }
                    }
                    let link: ArdopConnection
                    switch mode {
                    case .gateway(let target), .peerCall(let target):
                        phase = .dial(gateway: target)
                        append(String(localized: "Rufe \(target) — über Funk kann das dauern …"))
                        link = try await modem.dial(target, bandwidth: ardopBandwidth)
                    case .peerListen:
                        phase = .listen(kind)
                        append(String(localized: "Empfangsbereit für \(mycall) über \(kind.displayName) — warte auf Anruf …"))
                        link = try await modem.listen()
                    }
                    remote = link.remoteCall ?? remote
                    try await startSession(
                        over: link, kind: kind, mode: mode, remote: remote,
                        password: password, mycall: mycall, settings: settings, store: store,
                        selection: selection, maxInboundBytes: maxInboundBytes)
                } catch {
                    await modem.close()
                    if keysViaRigController { await unkeyViaRig() }
                    await rig?.close()
                    await shutdownModem()
                    throw error
                }
                await modem.close()
                if keysViaRigController { await unkeyViaRig() }
                await rig?.close()
                await shutdownModem()
            }
        } catch {
            fail(with: error)
            store.reload()
        }
        // Ein Empfang ohne Anrufer ist kein Verbindungsversuch.
        if let remote {
            recordHistory(history, started: started, gateway: remote, kind: kind, centerHz: centerHz)
        }

        // All paths above have stopped the modem by now; the serial
        // port is free again for the restore.
        //
        // Zurueckgestellt wird nur auf Wunsch: standardmaessig bleibt
        // das Geraet auf dem Kanal des Gateways stehen, damit der
        // naechste Ruf ohne erneutes Umstimmen laeuft.
        if let rigSnapshot, settings.restoreQRGAfterSession {
            await restoreRig(rigSnapshot, settings: settings)
        }
    }

    /// Sets dial frequency and USB-D over CI-V and returns the state
    /// to restore afterwards. The port is opened and closed right here
    /// so ardopcf can claim it next.
    private func qsy(to dialHz: Int, settings: AppSettingsStore) async throws -> RigSnapshot {
        let qrg = GatewayChannel.kilohertz(dialHz)
        phase = .qsy(qrg: qrg, viaRig: false)
        append(String(localized: "Stelle \(qrg) kHz Dial, USB-D per CI-V ein …"))
        let civ = try await CIVClient.connect(
            serialPort: settings.ardopSerialPort,
            baud: settings.ardopCATBaud,
            radioAddress: settings.civAddress)
        do {
            let oldHz = try await civ.frequency()
            let oldMode = try await civ.operatingMode()
            do {
                try await civ.setFrequency(dialHz)
                try await civ.setOperatingMode(.usbData)
            } catch {
                // Half-done QSY: put back what already changed while
                // the port is still ours, then abort the session.
                try? await civ.setFrequency(oldHz)
                try? await civ.setOperatingMode(oldMode)
                throw error
            }
            await civ.close()
            let fate =
                settings.restoreQRGAfterSession
                ? String(localized: "wird nach der Sitzung wiederhergestellt")
                : String(localized: "bleibt nach der Sitzung stehen")
            append(String(localized:
                "QRG \(GatewayChannel.kilohertz(oldHz)) kHz (\(oldMode)) → \(qrg) kHz (USB-D) — \(fate)."))
            return .civ(frequencyHz: oldHz, mode: oldMode)
        } catch {
            await civ.close()
            throw error
        }
    }

    /// Der verbundene `RigController`. Steht die Verbindung noch nicht,
    /// wird sie hier aufgebaut — wer im Dialog «Verbinden» drückt, soll
    /// nicht erst in die Einstellungen müssen.
    func connectedRig(settings: AppSettingsStore) async throws -> RigController {
        guard let rig else {
            throw WinlinkError.remoteError(String(localized: "Die Verbindung zum Funkgerät ist nicht verfügbar."))
        }
        if !rig.isConnected, let target = settings.rigLink {
            append(String(localized: "Verbinde mit \(target.name) …"))
            await rig.connect(target.link, name: target.name)
        }
        guard rig.isConnected else {
            if case .failed(let message) = rig.status {
                throw WinlinkError.remoteError(message)
            }
            throw WinlinkError.remoteError(String(localized:
                "Das Funkgerät ist nicht verbunden — bitte im Tab «Funkgerät» der Einstellungen einrichten und verbinden."))
        }
        return rig
    }

    /// QSY über rigctld: Frequenz und USB-D (Hamlib: PKTUSB) einstellen,
    /// den vorherigen Stand zurückgeben. Internal: Test-Naht.
    func qsyViaRig(to dialHz: Int, settings: AppSettingsStore) async throws -> RigSnapshot {
        let qrg = GatewayChannel.kilohertz(dialHz)
        phase = .qsy(qrg: qrg, viaRig: true)
        let rig = try await connectedRig(settings: settings)
        append(String(localized: "Stelle \(qrg) kHz Dial, USB-D über rigctld ein …"))
        let oldHz = try await rig.readFrequency()
        let oldMode = try await rig.readMode()
        do {
            try await rig.setFrequency(dialHz)
            try await rig.setMode(.dataUSB)
        } catch {
            // Halb fertiges QSY: zurückstellen, was schon geändert ist.
            try? await rig.setFrequency(oldHz)
            try? await rig.setMode(oldMode)
            throw error
        }
        let fate =
            settings.restoreQRGAfterSession
            ? String(localized: "wird nach der Sitzung wiederhergestellt")
            : String(localized: "bleibt nach der Sitzung stehen")
        append(String(localized:
            "QRG \(GatewayChannel.kilohertz(oldHz)) kHz (\(oldMode)) → \(qrg) kHz (USB-D) — \(fate)."))
        return .rig(frequencyHz: oldHz, mode: oldMode)
    }

    /// Tastet über den `RigController`; ein Wiederholversuch, danach
    /// Abbruch der Sitzung — ohne PTT wird nichts gesendet, und ein
    /// misslungenes Entsichern lässt den Sender in der Luft.
    /// Internal: Test-Naht.
    func keyViaRig(_ on: Bool, rig: RigController) async {
        guard mayKey(on) else { return }
        do {
            try await rig.setPTT(on)
        } catch {
            do {
                try await Task.sleep(for: .milliseconds(200))
                // Das App-Ende kann in der Wartezeit begonnen und schon
                // entsichert haben — dann nicht noch einmal tasten.
                guard mayKey(on) else { return }
                try await rig.setPTT(on)
            } catch {
                failPTT(keyOn: on, error: "\(error)")
            }
        }
    }

    /// Entsichert über den `RigController`, in einem frischen Task: der
    /// Aufrufer ist oft gerade abgebrochen worden, und ein abgebrochener
    /// Task erreichte das Gerät nicht mehr.
    private func unkeyViaRig() async {
        guard let rig else { return }
        await Task { try? await rig.setPTT(false) }.value
    }

    /// Puts frequency and mode back the way they were before the QSY.
    /// Best effort: a failure is logged, never raised as session error.
    func restoreRig(_ snapshot: RigSnapshot, settings: AppSettingsStore) async {
        switch snapshot {
        case .civ(let frequencyHz, let mode):
            append(String(localized:
                "Stelle QRG \(GatewayChannel.kilohertz(frequencyHz)) kHz (\(mode)) wieder her …"))
            do {
                let civ = try await CIVClient.connect(
                    serialPort: settings.ardopSerialPort,
                    baud: settings.ardopCATBaud,
                    radioAddress: settings.civAddress)
                do {
                    try await civ.setFrequency(frequencyHz)
                    try await civ.setOperatingMode(mode)
                } catch {
                    await civ.close()
                    throw error
                }
                await civ.close()
            } catch {
                append(String(localized: "Warnung: QRG-Wiederherstellung fehlgeschlagen: \(String(describing: error))"))
            }
        case .rig(let frequencyHz, let mode):
            append(String(localized:
                "Stelle QRG \(GatewayChannel.kilohertz(frequencyHz)) kHz (\(mode)) wieder her …"))
            do {
                guard let rig, rig.isConnected else {
                    throw WinlinkError.remoteError(String(localized: "Funkgerät nicht mehr verbunden"))
                }
                try await rig.setFrequency(frequencyHz)
                try await rig.setMode(mode)
            } catch {
                append(String(localized: "Warnung: QRG-Wiederherstellung fehlgeschlagen: \(String(describing: error))"))
            }
        }
    }

    /// Aborts the running radio session by closing the modem; the
    /// blocked session then unwinds with an error that is reported as
    /// "Abgebrochen." instead of an alert.
    func abortExchange() {
        guard canAbort, let abortAction else { return }
        didAbort = true
        canAbort = false
        append(String(localized: "Abbruch angefordert …"))
        Task { await abortAction() }
    }

    /// A PTT command failed even after the retry. Abort the session by
    /// closing the modem — `fail(with:)` then words the error around the
    /// PTT failure instead of the follow-on connection error.
    func failPTT(keyOn: Bool, error: String) {
        guard pttFailure == nil else { return }
        pttFailure = (keyOn, error)
        append(
            keyOn
                ? String(localized: "rigctld: PTT ein fehlgeschlagen: \(error)")
                : String(localized: "rigctld: PTT aus fehlgeschlagen: \(error)"))
        append(String(localized: "Breche Sitzung wegen PTT-Fehler ab …"))
        canAbort = false
        let action = abortAction
        Task { await action?() }
    }

    /// Parses the persisted/dialog ARDOP bandwidth string ("500",
    /// "2000MAX", "500FORCED"). Nil input falls back to the default.
    static func ardopBandwidth(from string: String?) -> ArdopBandwidth? {
        ArdopBandwidth(parsing: string ?? SettingsKeys.defaultArdopBandwidth)
    }

    /// The bundled ardopcf records RX audio, which macOS gates behind
    /// the microphone permission. Ask before launching it so the TCC
    /// prompt appears at a clear moment.
    /// Baut ein Modem nur zum Pegeleinstellen auf und liefert es samt
    /// Abbau und einem rigctld für die Messwerte zurück.
    ///
    /// Kein B2F, keine Gegenstelle — nur Zweiton. Der rigctld ist
    /// derselbe, über den auch getastet wird; ohne ihn gibt es keine
    /// Messung, wohl aber den Ton zum Einstellen von Hand.
    /// Ein Modem zum Pegeleinstellen, samt Messquelle und Abbau.
    struct TuningSession {
        let modem: any LevelTunableModem
        let readALC: () async -> Float?
        let readWatts: () async -> Double?
        /// Entsichert sofort über den PTT-Weg, der auch tastet — ohne
        /// Abbau. Für «Tune aus», bevor der Burst ausgeklungen ist.
        let unkey: () async -> Void
        let teardown: () async -> Void
        /// Ob überhaupt gemessen werden kann. Falsch heisst: Ton ja,
        /// Zahlen nein — der Nutzer liest die ALC am Gerät ab.
        let canMeasure: Bool
    }

    /// Baut das Modem zum Pegeleinstellen auf und wählt die Messquelle.
    ///
    /// Welcher Weg misst, hängt daran, wer den seriellen Port hält: Bei
    /// PTT über CI-V oder RTS öffnet **ardopcf** ihn selbst, dann kommt
    /// die App nicht mehr ans Gerät. Übrig bleiben rigctld und — wenn
    /// über VOX getastet wird und der Port frei bleibt — CI-V.
    func makeTuningSession(
        settings: AppSettingsStore
    ) async throws -> TuningSession {
        guard settings.ardopUseBundled else {
            throw WinlinkError.remoteError(
                String(localized: "Der Pegel-Assistent braucht das integrierte ardopcf (Einstellungen → Funk)."))
        }
        guard !isRunning else {
            throw WinlinkError.remoteError(
                String(localized: "Eine Winlink-Sitzung läuft — der Pegel-Assistent startet erst danach."))
        }
        // Assistent und Hand-Tune teilen sich ardopcf, Audio und PTT —
        // ein zweiter Aufbau würde denselben Prozess doppelt starten.
        guard !isTuning else {
            throw WinlinkError.remoteError(
                String(localized: "Pegel-Assistent oder Tune läuft bereits — bitte zuerst beenden."))
        }
        isTuning = true
        let process: ArdopProcess
        let launch = settings.ardopLaunchConfig
        do {
            try await ensureMicrophoneAccess()
            guard let executable = Bundle.main.url(forAuxiliaryExecutable: "ardopcf") else {
                throw WinlinkError.remoteError(
                    String(localized: "Das integrierte ardopcf fehlt im App-Bundle — bitte Skywave neu installieren."))
            }
            process = ArdopProcess(executable: executable, config: launch)
            try await process.start()
        } catch {
            isTuning = false
            throw error
        }
        do {
            let modem = try await ArdopModem.connect(
                mycall: settings.callsign, gridSquare: settings.locator,
                config: launch.modemConfig)

            // PTT verdrahten — ohne das geht die NF raus, während das
            // Gerät auf Empfang steht. ardopcf tastet nur selbst, wenn es
            // dafür konfiguriert wurde (CI-V oder RTS).
            var rig: RigctldClient?
            var unkey: () async -> Void = {}
            // Mit dem mitgelieferten rigctld tastet und misst der
            // RigController — er hält den Port ohnehin.
            var controller: RigController?
            if settings.rigUseBundled {
                controller = try await connectedRig(settings: settings)
            }
            if settings.usesBundledRigPTT, let controller {
                await modem.setPTTHandler { on in
                    guard await self.mayKey(on) else { return }
                    try? await controller.setPTT(on)
                }
                unkey = { try? await controller.setPTT(false) }
            } else if settings.rigctldEnabled {
                let client = try await RigctldClient.connect(
                    host: settings.rigctldHost,
                    port: UInt16(clamping: settings.rigctldPort))
                rig = client
                await modem.setPTTHandler { on in
                    guard await self.mayKey(on) else { return }
                    try? await client.setPTT(on)
                }
                unkey = { try? await client.setPTT(false) }
            }
            let closeRig = rig
            let unkeyOnTeardown = unkey
            if settings.usesBundledRigPTT || rig != nil {
                terminationUnkey = { await unkeyOnTeardown() }
            }

            // Messquelle wählen, in dieser Reihenfolge.
            var readALC: () async -> Float? = { nil }
            var readWatts: () async -> Double? = { nil }
            var canMeasure = false
            var civForMeter: CIVClient?

            if let controller {
                readALC = { await controller.alc().map { Float($0) } }
                readWatts = { await controller.powerWatts() }
                canMeasure = true
            } else if let client = rig {
                // Derselbe rigctld, über den getastet wird — er verträgt
                // Abfragen zwischen den PTT-Befehlen.
                readALC = { (try? await client.alc()).map { Float($0) } }
                readWatts = { try? await client.powerWatts() }
                canMeasure = true
            } else if settings.ardopPTTMode == .none,
                !settings.ardopSerialPort.trimmingCharacters(in: .whitespaces).isEmpty
            {
                // VOX: ardopcf braucht den Port nicht, also ist er frei.
                if let civ = try? await CIVClient.connect(
                    serialPort: settings.ardopSerialPort,
                    baud: settings.ardopCATBaud,
                    radioAddress: settings.civAddress)
                {
                    civForMeter = civ
                    readALC = { (try? await civ.alc()).map { Float($0) } }
                    canMeasure = true
                }
            }
            let closeCIV = civForMeter

            return TuningSession(
                modem: modem, readALC: readALC, readWatts: readWatts,
                unkey: unkeyOnTeardown,
                teardown: {
                    // Ein Sender, der nach einem Fehler getastet bleibt,
                    // ist der schlimmste Ausgang dieses Vorgangs.
                    //
                    // In einem frischen Task: Der Abbau wird oft aus einem
                    // gerade abgebrochenen Task gerufen («Tune aus»,
                    // Abbrechen im Assistenten). Dort enden PTT-Befehle und
                    // Sleeps sofort mit CancellationError, ohne das Gerät
                    // zu erreichen — der Sender bliebe getastet. Ein neuer
                    // Task erbt den Abbruch nicht.
                    await Task {
                        await unkeyOnTeardown()
                        await modem.close()
                        if let closeCIV { await closeCIV.close() }
                        if let closeRig { await closeRig.close() }
                        await process.stop()
                        await MainActor.run {
                            self.terminationUnkey = nil
                            self.isTuning = false
                        }
                    }.value
                },
                canMeasure: canMeasure)
        } catch {
            await process.stop()
            isTuning = false
            throw error
        }
    }

    /// Stellt den Sendepegel am laufenden ARDOP-Modem nach (Regler im
    /// Hauptfenster). Ohne Modem passiert nichts — der Wert steht dann
    /// in den Einstellungen und greift beim nächsten Verbindungsaufbau.
    func applyDriveLevel(_ level: Int) {
        guard let modem = activeDriveModem else { return }
        driveLevelTask?.cancel()
        let debounce = driveLevelDebounce
        driveLevelTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            do {
                try await modem.setDriveLevel(level)
                self?.append(String(localized: "Sendepegel \(level) %"))
            } catch {
                self?.append(String(localized: "Warnung: Sendepegel konnte nicht gesetzt werden (\(String(describing: error)))"))
            }
        }
    }

    /// Ob ein Zweiton-Burst, der bei `start` beginnt, noch vollständig
    /// vor `deadline` endet. Internal: Test-Naht.
    static func burstFits(
        before deadline: ContinuousClock.Instant, startingAt start: ContinuousClock.Instant,
        burst: Duration
    ) -> Bool {
        start + burst <= deadline
    }

    /// Hand-Tune: Zweiton senden, bis der Knopf erneut gedrückt wird oder
    /// `manualTuneLimit` erreicht ist; der Pegel-Regler wirkt
    /// währenddessen live. Modemaufbau, PTT und Abbau laufen über
    /// `makeTuningSession` — derselbe Weg wie beim Pegel-Assistenten,
    /// inklusive Entsichern des Senders am Ende.
    func toggleManualTune(settings: AppSettingsStore) {
        if isManualTuning { stopManualTune() } else { startManualTune(settings: settings) }
    }

    func stopManualTune() {
        manualTuneTask?.cancel()
    }

    private func startManualTune(settings: AppSettingsStore) {
        guard !isManualTuning, !isRunning, !isTuning, manualTuneTask == nil else { return }
        manualTuneTask = Task { [weak self] in
            guard let self else { return }
            defer { manualTuneTask = nil }
            let session: TuningSession
            do {
                session = try await makeTuningSession(settings: settings)
            } catch {
                if let winlink = error as? WinlinkError, case .remoteError(let message) = winlink {
                    errorMessage = message
                } else {
                    errorMessage = String(localized: "Tune liess sich nicht starten: \(error.localizedDescription)")
                }
                return
            }
            isManualTuning = true
            activeDriveModem = session.modem
            append(String(localized: "Tune: Zweiton, Pegel \(settings.ardopDriveLevel) %"))
            let burstGap = ArdopModem.twoToneDuration + .milliseconds(200)
            var burstEndsAt = ContinuousClock.now
            do {
                try await session.modem.setDriveLevel(settings.ardopDriveLevel)
                let deadline = ContinuousClock.now + Self.manualTuneLimit
                // Ein Burst dauert fünf Sekunden und endet von selbst; der
                // nächste wird erst angenommen, wenn der alte vorbei ist.
                // Gestartet wird er nur, wenn er noch ganz vor die Frist
                // passt — sonst sendet der letzte Burst über sie hinaus.
                while Self.burstFits(
                    before: deadline, startingAt: .now, burst: ArdopModem.twoToneDuration)
                {
                    try Task.checkCancellation()
                    try await session.modem.sendTwoToneTest()
                    burstEndsAt = ContinuousClock.now + burstGap
                    try await Task.sleep(for: burstGap)
                }
                append(String(localized: "Tune: Zeitlimit erreicht."))
            } catch is CancellationError {
                append(String(localized: "Tune beendet."))
            } catch {
                append(String(localized: "Warnung: Tune abgebrochen (\(String(describing: error)))"))
            }
            activeDriveModem = nil
            driveLevelTask?.cancel()
            driveLevelTask = nil
            isStoppingManualTune = true
            // Erst entsichern — sofort, über den PTT-Weg der Sitzung und
            // in einem frischen Task, der den Abbruch nicht erbt. Dann den
            // laufenden Burst ausklingen lassen, damit ardopcfs eigenes
            // «PTT FALSE» noch über die offene Verbindung ankommt und kein
            // verspätetes «PTT TRUE» mehr unterwegs ist. Erst danach Modem
            // und Prozess abbauen, was ein zweites Mal entsichert.
            await Task { await session.unkey() }.value
            let remaining = burstEndsAt - ContinuousClock.now
            if remaining > .zero {
                try? await Task { try await Task.sleep(for: remaining) }.value
            }
            await session.teardown()
            isManualTuning = false
            isStoppingManualTune = false
        }
    }

    private func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .audio) { return }
        default:
            break
        }
        throw WinlinkError.remoteError(String(localized: """
            Skywave braucht Zugriff auf das Mikrofon (Audio-Eingang), um das \
            Funksignal zu empfangen. Bitte in Systemeinstellungen → \
            Datenschutz & Sicherheit → Mikrofon für Skywave erlauben.
            """))
    }

    /// The transport-agnostic core — also the test seam.
    func run(
        over transport: any WinlinkTransport, targetcall: String,
        password: String?, mycall: String, locator: String, store: MailStore,
        path: ExchangePath = .internet, selection: Set<String>? = nil,
        maxInboundBytes: Int = 0, isMaster: Bool = false
    ) async throws {
        let logLine: @Sendable (String) -> Void = { line in
            Task { @MainActor in self.append(line) }
        }
        let mailbox = store.makeSessionMailbox(
            path: path, selection: selection, maxInboundBytes: maxInboundBytes,
            logLine: logLine)
        // Zurückgehalten: durch die Kennzeichnung oder die Abwahl im
        // Dialog — vor der Sitzung bekannt, damit die Zusammenfassung
        // nicht «keine neuen Nachrichten» sagt, wenn welche warten.
        var held = store.heldItems(for: path).count
        if let selection {
            held += store.outboundMIDs(for: path).subtracting(selection).count
        }
        if held > 0 {
            append(held == 1
                ? String(localized: "1 Nachricht bleibt zurückgehalten im Postausgang")
                : String(localized: "\(held) Nachrichten bleiben zurückgehalten im Postausgang"))
        }

        let session = B2FSession(
            mycall: mycall,
            targetcall: targetcall,
            locator: locator,
            mailbox: mailbox
        )
        session.isMaster = isMaster
        // P2P: nur Post exklusiv an die Gegenstation — auch wenn sie
        // kein ;FW schickt und damit wie ein CMS aussähe.
        if case .p2p(_, let peer?) = path {
            session.outboundRecipients = [Address(string: peer)]
        }
        session.secureLoginPassword = password
        session.userAgent = Self.userAgent
        session.logLine = logLine

        do {
            let stats = try await session.exchange(over: transport)
            let deferred = await mailbox.deferred
            var text = summaryText(for: stats, held: held, deferred: deferred)
            // cms-z accepts messages but has an isolated store: nothing
            // is delivered anywhere, and pending production mail is not
            // visible. Without this hint a successful test session looks
            // like a broken app.
            if activeHost == SettingsKeys.testCMSHost {
                text += String(localized: " — Achtung: \(SettingsKeys.testCMSHost) ist ein isolierter Testserver, Nachrichten werden nicht zugestellt.")
            }
            summary = text
            lastStats = stats
            lastSuccessDate = Date()
            lastRunStats = stats
            lastRunOutcome = .success
            append(String(localized: "Fertig. \(text)"))
        } catch {
            // Inbound messages are committed one by one, so the session's
            // stats still tell the user what arrived before the error.
            fail(with: error, partial: session.stats)
            lastRunStats = session.stats
            lastRunOutcome = didAbort ? .aborted : .failed
        }
        store.reload()
    }

    /// Verbindung steht: Weg in der Statuszeile nachführen (beim Empfang
    /// ist der Anrufer erst jetzt bekannt) und die Sitzung fahren — als
    /// Master, wenn wir angerufen wurden.
    private func startSession(
        over link: some WinlinkTransport, kind: RadioTransportKind, mode: RadioLinkMode,
        remote: String?, password: String, mycall: String, settings: AppSettingsStore,
        store: MailStore, selection: Set<String>?, maxInboundBytes: Int
    ) async throws {
        phase = .session
        let peer = remote ?? "?"
        let path: ExchangePath = mode.isPeer ? .p2p(kind, peer: peer) : .radio(kind, gateway: peer)
        activePath = path
        append(
            mode.isListen
                ? String(localized: "\(peer) hat angerufen, starte B2F-Austausch als Master")
                : String(localized: "Verbindung steht, starte B2F-Austausch"))
        try await run(
            over: link, targetcall: peer, password: mode.usesPassword ? password : nil,
            mycall: mycall, locator: settings.locator, store: store,
            path: path, selection: selection, maxInboundBytes: maxInboundBytes,
            isMaster: mode.isListen)
    }

    /// Schreibt den Versuch in die Historie. Ohne Sitzung (Modem oder
    /// Ruf schon gescheitert) zählt der Versuch als fehlgeschlagen
    /// bzw. abgebrochen, mit dem Fehlertext der Meldung.
    func recordHistory(
        _ history: ConnectionHistoryStore?, started: Date, gateway: String,
        kind: RadioTransportKind?, centerHz: Int?
    ) {
        guard let history else { return }
        let stats = lastRunStats ?? TrafficStats()
        let outcome = lastRunOutcome ?? (didAbort ? .aborted : .failed)
        history.record(
            ConnectionRecord(
                date: started, gateway: gateway, kind: kind, centerHz: centerHz,
                durationSeconds: Date().timeIntervalSince(started),
                bytesSent: stats.bytesSent, bytesReceived: stats.bytesReceived,
                sent: stats.sent.count, received: stats.received.count,
                outcome: outcome,
                errorText: outcome == .success ? nil : errorMessage ?? summary))
    }

    private func summaryText(
        for stats: TrafficStats, held: Int = 0, deferred: [SessionMailbox.Deferred] = []
    ) -> String {
        let sent = stats.sent.count
        let received = stats.received.count
        var parts = [String]()
        if sent > 0 {
            parts.append(sent == 1 ? String(localized: "1 Nachricht gesendet") : String(localized: "\(sent) Nachrichten gesendet"))
        }
        if received > 0 {
            parts.append(
                received == 1 ? String(localized: "1 Nachricht empfangen") : String(localized: "\(received) Nachrichten empfangen"))
        }
        if parts.isEmpty {
            parts.append(String(localized: "Keine neuen Nachrichten"))
        }
        if held > 0 {
            parts.append(held == 1 ? String(localized: "1 zurückgehalten") : String(localized: "\(held) zurückgehalten"))
        }
        if !deferred.isEmpty {
            let bytes = deferred.reduce(0) { $0 + $1.sizeBytes }
            parts.append(
                (deferred.count == 1
                    ? String(localized: "1 zurückgestellt")
                    : String(localized: "\(deferred.count) zurückgestellt"))
                    + " (\(SessionMailbox.kilobytes(bytes)) kB)")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// Internal for the wording tests.
    func fail(with error: any Error, partial: TrafficStats? = nil) {
        // Messages that made it through before the error are already in
        // the mailbox — say so, or the user retries a session that
        // (partly) succeeded.
        let partialText: String? = {
            guard let partial, !partial.sent.isEmpty || !partial.received.isEmpty else {
                return nil
            }
            return summaryText(for: partial)
        }()

        // A dead PTT outranks the follow-on connection error: the radio
        // may still be transmitting.
        if let ptt = pttFailure {
            let text =
                ptt.keyOn
                ? String(localized: """
                    PTT-Fehler: rigctld konnte den Sender nicht tasten — ohne PTT \
                    wird nichts gesendet, die Sitzung wurde abgebrochen. Läuft rigctld noch?
                    """)
                : String(localized: """
                    PTT-Fehler: rigctld konnte den Sender nicht enttasten — bitte SOFORT \
                    prüfen, ob das Funkgerät noch sendet! Die Sitzung wurde abgebrochen.
                    """)
            append(String(localized: "Fehler: \(String(describing: error))"))
            errorMessage = text + (partialText.map { String(localized: "\n\nBereits übertragen: \($0)") } ?? "")
            return
        }

        // A user-initiated abort unwinds the session with an error;
        // that is expected and gets a summary, not an alert.
        if didAbort {
            let text = partialText.map { String(localized: "Abgebrochen — bereits übertragen: \($0)") } ?? String(localized: "Abgebrochen.")
            summary = text
            append(text)
            return
        }
        append(String(localized: "Fehler: \(String(describing: error))"))
        errorMessage = describe(error) + (partialText.map { String(localized: "\n\nBereits übertragen: \($0)") } ?? "")
    }

    /// Maps transport and protocol errors to something a user can act on.
    private func describe(_ error: any Error) -> String {
        // Radio phases first: before the B2F session runs, the generic
        // protocol wording below would mislead.
        switch phase {
        case .qsy(let qrg, let viaRig):
            if viaRig {
                let detail: String = {
                    if let winlink = error as? WinlinkError,
                        case .remoteError(let message) = winlink
                    {
                        return message
                    }
                    return String(localized: "Bitte im Tab «Funkgerät» der Einstellungen prüfen, ob die Verbindung steht.")
                }()
                return String(localized: "Die Frequenz \(qrg) kHz liess sich nicht über rigctld einstellen. \(detail)")
            }
            return String(localized: """
                Die Frequenz \(qrg) kHz liess sich nicht per CI-V einstellen — \
                bitte USB-Kabel, seriellen Port, Baudrate und CI-V-Adresse in \
                den Einstellungen (Funkgerät) prüfen.
                """)
        case .modemStart:
            if let winlink = error as? WinlinkError,
                case .remoteError(let message) = winlink
            {
                return message
            }
            if let processError = error as? ArdopProcessError {
                switch processError {
                case .launchFailed(let reason):
                    return String(localized: "Das integrierte ardopcf liess sich nicht starten: \(reason)")
                case .terminatedEarly(_, let log):
                    let tail = log.suffix(3).joined(separator: "\n")
                    return String(localized: """
                        Das integrierte ardopcf wurde unerwartet beendet — meist stimmt \
                        die Audio-Geräteauswahl nicht (Einstellungen → Funk). Letzte Meldungen:
                        \(tail)
                        """)
                case .readyTimeout:
                    return String(localized: """
                        Das integrierte ardopcf meldet sich nicht — bitte die \
                        Einstellungen (Funk) prüfen und erneut versuchen.
                        """)
                }
            }
            return String(localized: "Das integrierte ardopcf liess sich nicht starten: \(error.localizedDescription)")
        case .modemConnect(let kind, let host, let port):
            return String(localized: """
                Keine Verbindung zum \(kind.displayName)-Modem (\(host):\(String(port))). \
                Läuft das \(kind.modemName)-Programm? Host und Port lassen sich \
                in den Einstellungen (Funk) anpassen.
                """)
        case .rigConnect:
            // The rigctld error is thrown with a complete user-facing
            // message already.
            if let winlink = error as? WinlinkError,
                case .remoteError(let message) = winlink
            {
                return message
            }
        case .dial(let gateway):
            if let winlink = error as? WinlinkError,
                case .remoteError(let message) = winlink
            {
                return String(localized: "Verbindung zu \(gateway) fehlgeschlagen: \(message)")
            }
            return String(localized: """
                Keine Verbindung zu \(gateway) — die Gegenstelle antwortet nicht \
                oder der Kanal ist belegt. Frequenz, Bandbreite und Rufzeichen prüfen.
                """)
        case .listen(let kind):
            return String(localized: """
                Empfangsbereitschaft über \(kind.displayName) beendet: \(error.localizedDescription)
                """)
        case .session:
            break
        }
        if let winlink = error as? WinlinkError {
            if winlink.isLoginFailure {
                return String(localized: "Anmeldung fehlgeschlagen — bitte das Winlink-Passwort in den Einstellungen prüfen.")
            }
            switch winlink {
            case .remoteError(let message):
                if message.lowercased().contains("unknown client") {
                    return String(localized: """
                        Der CMS-Server lehnt Skywave als unbekannten Client ab — \
                        das sollte seit der Registrierung nicht mehr vorkommen. \
                        Bitte den CMS-Host in den Einstellungen prüfen; als Ausweichlösung \
                        \(SettingsKeys.testCMSHost) (Testserver, keine Zustellung) verwenden.
                        """)
                }
                return String(localized: "Der Server meldet einen Fehler: \(message)")
            case .connectionClosed:
                return String(localized: "Die Verbindung wurde unerwartet beendet. Bitte erneut versuchen.")
            case .timeout(let what):
                return String(localized: "Zeitüberschreitung: \(what)")
            case .unsupportedRemoteSID:
                return String(localized: "Die Gegenstelle unterstützt das B2F-Protokoll nicht.")
            default:
                return String(localized: "Protokollfehler: \(String(describing: winlink))")
            }
        }
        // NWError et al. — most likely no route/refused/DNS.
        return String(localized: "Keine Verbindung zum CMS (\(activeHost)): \(error.localizedDescription)")
    }

    private func append(_ line: String) {
        log.append(line)
        sessionLog.append(line)
    }
}

/// Wie eine Funkverbindung zustande kommt.
enum RadioLinkMode: Equatable, Sendable {
    /// RMS-Gateway rufen — Winlink-Passwort nötig.
    case gateway(String)
    /// P2P: eine andere Station rufen.
    case peerCall(String)
    /// P2P: auf einen Anruf warten, dann als Master austauschen.
    case peerListen

    var target: String? {
        switch self {
        case .gateway(let call), .peerCall(let call): call
        case .peerListen: nil
        }
    }

    var isPeer: Bool { if case .gateway = self { false } else { true } }
    var isListen: Bool { self == .peerListen }
    var usesPassword: Bool { if case .gateway = self { true } else { false } }

    func path(_ kind: RadioTransportKind) -> ExchangePath {
        switch self {
        case .gateway(let call): .radio(kind, gateway: call)
        case .peerCall(let call): .p2p(kind, peer: call)
        case .peerListen: .p2p(kind, peer: nil)
        }
    }
}
