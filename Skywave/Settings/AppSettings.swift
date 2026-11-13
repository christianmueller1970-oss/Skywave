import Foundation
import Observation
import WinlinkKit

/// Connection defaults, single-sourced.
enum SettingsKeys {
    /// Default CMS host. Production — the "Skywave" client SID is
    /// registered with the Winlink Development Team (live since
    /// 2026-07-13).
    static let defaultCMSHost = "server.winlink.org"
    /// The Winlink test server: accepts unregistered client SIDs, but
    /// its message store is isolated — nothing is actually delivered.
    static let testCMSHost = "cms-z.winlink.org"
    static let defaultCMSPort = 8772

    /// Search radius for the gateway directory. 800 km covers HB9 and
    /// the neighbouring countries; the window can change it.
    static let defaultGatewayMaxDistanceKm = 800

    // Radio modem programs, reachable over local TCP.
    static let defaultVaraHost = "localhost"
    static let defaultVaraCommandPort = 8300
    static let defaultVaraDataPort = 8301
    static let defaultArdopHost = "localhost"
    static let defaultArdopControlPort = 8515
    static let defaultArdopDataPort = 8516
    static let defaultRigctldPort = 4532

    // Bandwidth defaults for the connect dialog.
    static let defaultVaraHFBandwidth = "2300"
    static let defaultArdopBandwidth = "2000MAX"

    // Bundled ardopcf defaults.
    static let defaultArdopCIVAddress = "98"  // Icom IC-7610
    static let defaultArdopCATBaud = 115200
    /// Sendepegel des ARDOP-Modems. Die Vorgabe des TNC ist 100 —
    /// volle Amplitude, die auf einem Dateneingang meist übersteuert.
    /// Wir übernehmen sie trotzdem, um niemandem still das Sende-
    /// verhalten zu ändern.
    static let defaultArdopDriveLevel = 100

    // Legacy UserDefaults keys from before settings moved into the
    // data folder — read once to seed settings.json, never written.
    static let callsign = "callsign"
    static let locator = "locator"
    static let cmsHost = "cmsHost"
    static let cmsPort = "cmsPort"
}

/// How the bundled ardopcf keys the transmitter.
enum ArdopPTTMode: String, CaseIterable, Identifiable {
    /// CAT PTT via Icom CI-V hex commands on a serial port.
    case catCIV
    /// RTS line on a serial port.
    case rts
    /// Skywave keys PTT through rigctld (ardopcf reports PTT state).
    case rigctld
    /// No PTT — VOX or manual keying.
    case none

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .catCIV: String(localized: "CAT (Icom CI-V)")
        case .rts: String(localized: "RTS (serieller Port)")
        case .rigctld: "rigctld"
        case .none: String(localized: "Keine (VOX)")
        }
    }
}

/// Der Weg, auf dem Skywave das Funkgerät erreicht.
///
/// Eine Sicht auf die gespeicherten Einstellungen, kein eigener
/// Speicherwert: «mitgelieferter rigctld» ist ein eigenes Flag, die
/// drei übrigen Wege ergeben sich wie bisher aus dem PTT-Modus des
/// integrierten ardopcf. So bleibt das Verhalten bestehender
/// Installationen ohne Migration dasselbe.
enum RigAccess: String, CaseIterable, Identifiable {
    /// Skywave startet den mitgelieferten rigctld und hält die
    /// Verbindung selbst (Frequenz, Modus, PTT, QSY).
    case bundled
    /// Kein CAT: getastet wird über RTS oder VOX, die Frequenz von Hand.
    case none
    /// Ein rigctld, den jemand anderes gestartet hat.
    case external
    /// ardopcf tastet selbst über Icom CI-V; Skywave nutzt denselben
    /// Port vor und nach der Sitzung für das QSY.
    case civDirect

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bundled: String(localized: "Über Skywave (mitgelieferter rigctld)")
        case .none: String(localized: "Kein CAT")
        case .external: String(localized: "Erweitert: fremder rigctld")
        case .civDirect: String(localized: "Erweitert: Icom CI-V direkt")
        }
    }
}

/// Zielgrösse, auf die Bild-Anhänge im Compose verkleinert werden.
enum ImageAttachmentTarget: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case original

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: String(localized: "Klein (~50 KB)")
        case .medium: String(localized: "Mittel (~150 KB)")
        case .large: String(localized: "Gross (~400 KB)")
        case .original: String(localized: "Original")
        }
    }

    /// Byte-Budget für den Optimizer; nil = nicht optimieren.
    var targetBytes: Int? {
        switch self {
        case .small: 50_000
        case .medium: 150_000
        case .large: 400_000
        case .original: nil
        }
    }
}

/// The editable settings model, persisted as JSON in the data folder
/// (`settings.json`) next to mailbox and contacts — every change saves
/// immediately. The Winlink password stays in the Keychain.
@MainActor @Observable final class AppSettingsStore {
    private struct Persisted: Codable {
        var callsign = ""
        var locator = ""
        var cmsHost = ""
        var cmsPort = 0

        // Radio transport fields. All Optional on purpose: synthesized
        // Codable uses decode (not decodeIfPresent) for non-optionals,
        // so a required new key would make old settings.json files fail
        // to decode — and `(try? …) ?? Persisted()` in init would then
        // silently reset every setting.
        var varaHost: String?
        var varaCommandPort: Int?
        var varaDataPort: Int?
        var ardopHost: String?
        var ardopControlPort: Int?
        var ardopDataPort: Int?
        var rigctldHost: String?
        var rigctldPort: Int?

        // Last-used connect-dialog values, per transport.
        var varaHFGateway: String?
        var varaHFBandwidth: String?
        var varaFMGateway: String?
        var ardopGateway: String?
        var ardopBandwidth: String?
        var ardopChannelID: String?

        // Bundled ardopcf (integrated TNC) configuration.
        var ardopUseBundled: Bool?
        var ardopCaptureDevice: String?
        var ardopPlaybackDevice: String?
        var ardopPTTMode: String?
        var ardopSerialPort: String?
        var ardopCIVAddress: String?
        var ardopCATBaud: Int?
        /// ARDOP transmit drive level (0…100).
        var ardopDriveLevel: Int?
        /// QRG nach der Sitzung zurueckstellen (Vorgabe: nein).
        var restoreQRGAfterSession: Bool?

        // Funkgerät über den mitgelieferten rigctld. Fehlt `rigUseBundled`,
        // gilt der bisherige Weg aus `ardopPTTMode`.
        var rigUseBundled: Bool?
        var rigProfileID: String?
        var rigNetworkHost: String?
        var rigAutoConnect: Bool?
        var rigPTTViaCAT: Bool?

        // Compose.
        var imageAttachmentTarget: String?

        // Automatischer Telnet-Abruf.
        var autoFetchEnabled: Bool?
        var autoFetchIntervalMinutes: Int?

        // Gateway-Verzeichnis (Winlink Web Services).
        var gatewayRefreshEnabled: Bool?
        var gatewayMaxDistanceKm: Int?

        // Versandkontrolle: Eingangsgrenze je Nachricht über Funk.
        var radioInboundMaxKB: Int?

        // Positionsmeldung: letzte Quelle und manuelle Koordinaten.
        var positionSource: String?
        var manualLatitude: Double?
        var manualLongitude: Double?

        // P2P: zuletzt gerufene Station und Verfahren.
        var p2pPeer: String?
        var p2pKind: String?
    }

    @ObservationIgnored private let fileURL: URL

    var callsign: String {
        didSet {
            // Normalize to upper case. Assigning inside didSet does not
            // re-trigger the observer, so there is no loop.
            let normalized = callsign.uppercased()
            if normalized != callsign { callsign = normalized }
            save()
        }
    }

    var locator: String {
        didSet { save() }
    }

    var cmsHost: String {
        didSet { save() }
    }

    var cmsPort: Int {
        didSet { save() }
    }

    var varaHost: String {
        didSet { save() }
    }

    var varaCommandPort: Int {
        didSet { save() }
    }

    var varaDataPort: Int {
        didSet { save() }
    }

    var ardopHost: String {
        didSet { save() }
    }

    var ardopControlPort: Int {
        didSet { save() }
    }

    var ardopDataPort: Int {
        didSet { save() }
    }

    /// Empty host disables rig control (ARDOP then relies on the TNC
    /// or external means to key the transmitter).
    var rigctldHost: String {
        didSet { save() }
    }

    var rigctldPort: Int {
        didSet { save() }
    }

    var varaHFGateway: String {
        didSet {
            let normalized = varaHFGateway.uppercased()
            if normalized != varaHFGateway { varaHFGateway = normalized }
            save()
        }
    }

    var varaHFBandwidth: String {
        didSet { save() }
    }

    var varaFMGateway: String {
        didSet {
            let normalized = varaFMGateway.uppercased()
            if normalized != varaFMGateway { varaFMGateway = normalized }
            save()
        }
    }

    var ardopGateway: String {
        didSet {
            let normalized = ardopGateway.uppercased()
            if normalized != ardopGateway { ardopGateway = normalized }
            save()
        }
    }

    var ardopBandwidth: String {
        didSet { save() }
    }

    /// `GatewayChannel.id` of the last picker choice in the ARDOP
    /// connect dialog; empty after a manual gateway entry.
    var ardopChannelID: String {
        didSet { save() }
    }

    /// True: Skywave starts the bundled ardopcf itself; false: connect
    /// to an externally running TNC at `ardopHost`.
    var ardopUseBundled: Bool {
        didSet { save() }
    }

    /// Audio device names for the bundled ardopcf; empty means the
    /// system default device.
    var ardopCaptureDevice: String {
        didSet { save() }
    }

    var ardopPlaybackDevice: String {
        didSet { save() }
    }

    var ardopPTTMode: ArdopPTTMode {
        didSet { save() }
    }

    /// Serial device path (/dev/cu.*) for CAT or RTS PTT.
    var ardopSerialPort: String {
        didSet { save() }
    }

    /// Icom CI-V address as hex string (IC-7610: "98").
    var ardopCIVAddress: String {
        didSet { save() }
    }

    /// Sendepegel des ARDOP-Modems, 0…100. Skaliert die Amplitude der
    /// NF, die ardopcf ans Funkgerät gibt. Zu viel davon übersteuert
    /// den Modulator — im Datenbetrieb fehlt die Mikrofonkette, die
    /// das sonst abfängt.
    var ardopDriveLevel: Int {
        didSet { save() }
    }

    /// Nach dem automatischen QSY die vorherige Frequenz und den
    /// vorherigen Modus wieder einstellen.
    ///
    /// Vorgabe «aus»: nach der Sitzung bleibt das Gerät auf dem Kanal
    /// des Gateways stehen. So lässt sich sofort wieder rufen, ohne
    /// erneut umzustimmen — und man sieht am Gerät, worauf gearbeitet
    /// wurde. Wer sein Gerät lieber so vorfindet, wie er es verlassen
    /// hat, schaltet die Rückstellung ein.
    var restoreQRGAfterSession: Bool {
        didSet { save() }
    }

    var ardopCATBaud: Int {
        didSet { save() }
    }

    /// Skywave steuert das Funkgerät über den mitgelieferten rigctld.
    var rigUseBundled: Bool {
        didSet { save() }
    }

    /// Gewähltes Geräteprofil (`RigProfile.id`); leer = noch keines.
    var rigProfileID: String {
        didSet { save() }
    }

    /// Adresse eines Geräts, das Hamlib übers Netz erreicht (FlexRadio).
    var rigNetworkHost: String {
        didSet { save() }
    }

    /// Verbindung zum Funkgerät beim Start von Skywave aufbauen.
    var rigAutoConnect: Bool {
        didSet { save() }
    }

    /// Mit dem mitgelieferten rigctld über CAT tasten; aus = VOX.
    var rigPTTViaCAT: Bool {
        didSet { save() }
    }

    /// Zielgrösse für Bild-Anhänge beim Anhängen im Compose.
    var imageAttachmentTarget: ImageAttachmentTarget {
        didSet { save() }
    }

    /// Automatischer Abruf über Telnet (CMS) im Hintergrund.
    var autoFetchEnabled: Bool {
        didSet { save() }
    }

    var autoFetchIntervalMinutes: Int {
        didSet { save() }
    }

    /// Täglicher Abgleich der Gateway-Liste über die Winlink Web
    /// Services. Ohne gültigen Locator passiert ohnehin nichts.
    var gatewayRefreshEnabled: Bool {
        didSet { save() }
    }

    /// Suchradius für die Gateway-Liste in Kilometern.
    var gatewayMaxDistanceKm: Int {
        didSet { save() }
    }

    /// Grösste Nachricht (unkomprimiert, kB), die über Funk noch
    /// angenommen wird; grössere werden zurückgestellt und beim
    /// nächsten Austausch — etwa über Internet — erneut angeboten.
    /// 0 = keine Grenze (Vorgabe).
    var radioInboundMaxKB: Int {
        didSet { save() }
    }

    /// Auswahl für die Einstellungen; 0 steht für «unbegrenzt».
    static let radioInboundLimitsKB = [0, 10, 25, 50, 100, 250]

    /// Zuletzt gewählte Standortquelle der Positionsmeldung.
    var positionSource: PositionSource {
        didSet { save() }
    }

    /// Zuletzt von Hand eingegebene Koordinaten (Dezimalgrad).
    var manualLatitude: Double? {
        didSet { save() }
    }

    var manualLongitude: Double? {
        didSet { save() }
    }

    /// Zuletzt direkt gerufene Station (P2P).
    var p2pPeer: String {
        didSet {
            let normalized = p2pPeer.uppercased()
            if normalized != p2pPeer { p2pPeer = normalized }
            save()
        }
    }

    /// Zuletzt für P2P gewähltes Verfahren.
    var p2pKind: RadioTransportKind {
        didSet { save() }
    }

    init(fileURL: URL) {
        // Property observers do not fire for assignments in an
        // initializer, so this only loads — it does not write back.
        self.fileURL = fileURL
        let persisted =
            (try? JSONDecoder().decode(
                Persisted.self, from: Data(contentsOf: fileURL))) ?? Persisted()
        callsign = persisted.callsign
        locator = persisted.locator
        cmsHost = persisted.cmsHost.isEmpty ? SettingsKeys.defaultCMSHost : persisted.cmsHost
        cmsPort = persisted.cmsPort > 0 ? persisted.cmsPort : SettingsKeys.defaultCMSPort
        varaHost = persisted.varaHost ?? SettingsKeys.defaultVaraHost
        varaCommandPort = persisted.varaCommandPort ?? SettingsKeys.defaultVaraCommandPort
        varaDataPort = persisted.varaDataPort ?? SettingsKeys.defaultVaraDataPort
        ardopHost = persisted.ardopHost ?? SettingsKeys.defaultArdopHost
        ardopControlPort = persisted.ardopControlPort ?? SettingsKeys.defaultArdopControlPort
        ardopDataPort = persisted.ardopDataPort ?? SettingsKeys.defaultArdopDataPort
        rigctldHost = persisted.rigctldHost ?? ""
        rigctldPort = persisted.rigctldPort ?? SettingsKeys.defaultRigctldPort
        varaHFGateway = persisted.varaHFGateway ?? ""
        varaHFBandwidth = persisted.varaHFBandwidth ?? SettingsKeys.defaultVaraHFBandwidth
        varaFMGateway = persisted.varaFMGateway ?? ""
        ardopGateway = persisted.ardopGateway ?? ""
        ardopBandwidth = persisted.ardopBandwidth ?? SettingsKeys.defaultArdopBandwidth
        ardopChannelID = persisted.ardopChannelID ?? ""
        ardopUseBundled = persisted.ardopUseBundled ?? true
        ardopCaptureDevice = persisted.ardopCaptureDevice ?? ""
        ardopPlaybackDevice = persisted.ardopPlaybackDevice ?? ""
        ardopPTTMode = persisted.ardopPTTMode.flatMap(ArdopPTTMode.init) ?? .catCIV
        ardopSerialPort = persisted.ardopSerialPort ?? ""
        ardopCIVAddress = persisted.ardopCIVAddress ?? SettingsKeys.defaultArdopCIVAddress
        ardopCATBaud = persisted.ardopCATBaud ?? SettingsKeys.defaultArdopCATBaud
        ardopDriveLevel = persisted.ardopDriveLevel ?? SettingsKeys.defaultArdopDriveLevel
        restoreQRGAfterSession = persisted.restoreQRGAfterSession ?? false
        rigUseBundled = persisted.rigUseBundled ?? false
        rigProfileID = persisted.rigProfileID ?? ""
        rigNetworkHost = persisted.rigNetworkHost ?? ""
        rigAutoConnect = persisted.rigAutoConnect ?? true
        rigPTTViaCAT = persisted.rigPTTViaCAT ?? true
        imageAttachmentTarget =
            persisted.imageAttachmentTarget.flatMap(ImageAttachmentTarget.init) ?? .medium
        autoFetchEnabled = persisted.autoFetchEnabled ?? false
        autoFetchIntervalMinutes = persisted.autoFetchIntervalMinutes ?? 30
        gatewayRefreshEnabled = persisted.gatewayRefreshEnabled ?? true
        gatewayMaxDistanceKm =
            persisted.gatewayMaxDistanceKm ?? SettingsKeys.defaultGatewayMaxDistanceKm
        radioInboundMaxKB = max(0, persisted.radioInboundMaxKB ?? 0)
        positionSource = persisted.positionSource.flatMap(PositionSource.init) ?? .locator
        manualLatitude = persisted.manualLatitude
        manualLongitude = persisted.manualLongitude
        p2pPeer = persisted.p2pPeer ?? ""
        p2pKind = persisted.p2pKind.flatMap(RadioTransportKind.init) ?? .ardop
    }

    /// Trimmed, upper-cased callsign for protocol use.
    var effectiveCallsign: String {
        callsign.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// CMS port for the transport layer.
    var effectiveCMSPort: UInt16 {
        UInt16(clamping: cmsPort)
    }

    /// True once everything needed for an exchange is configured.
    var isConfigured: Bool {
        !effectiveCallsign.isEmpty && Keychain.password()?.isEmpty == false
    }

    /// VARA modem endpoint for the transport layer.
    var varaConfig: VaraModem.Config {
        var config = VaraModem.Config()
        config.host = varaHost
        config.commandPort = UInt16(clamping: varaCommandPort)
        config.dataPort = UInt16(clamping: varaDataPort)
        return config
    }

    /// ARDOP TNC endpoint for the transport layer.
    var ardopConfig: ArdopModem.Config {
        var config = ArdopModem.Config()
        config.host = ardopHost
        config.controlPort = UInt16(clamping: ardopControlPort)
        config.dataPort = UInt16(clamping: ardopDataPort)
        return config
    }

    /// True when PTT should be keyed via rigctld (ARDOP only). With
    /// the bundled TNC the PTT mode decides; with an external TNC the
    /// legacy rule applies: a non-empty rigctld host enables it.
    var rigctldEnabled: Bool {
        // Mit dem mitgelieferten rigctld läuft PTT über den RigController,
        // nicht über eine eigene Verbindung der Sitzung.
        if rigUseBundled { return false }
        if ardopUseBundled {
            return ardopPTTMode == .rigctld
                && !rigctldHost.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !rigctldHost.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// True when Skywave itself can talk CI-V to the rig for a QSY:
    /// the integrated TNC with CAT PTT — QSY reuses its serial-port
    /// configuration before/after the session (during it, ardopcf owns
    /// the port).
    var civQSYAvailable: Bool {
        // rigctld hält den Port — ein direkter CI-V-Zugriff käme nicht durch.
        !rigUseBundled && ardopUseBundled && ardopPTTMode == .catCIV
            && !ardopSerialPort.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// RTS ist gewählt, tastet aber nicht: das integrierte ardopcf läuft
    /// in der App-Sandbox, und die blockiert das Setzen der Steuerleitung
    /// (`TIOCMSET`). Der Tab «Funkgerät» weist darauf hin.
    var rtsPTTBlockedBySandbox: Bool {
        rigAccess == .none && ardopPTTMode == .rts && ardopUseBundled
    }

    /// CI-V transceiver address for `CIVClient` (hex in the settings).
    var civAddress: UInt8 {
        UInt8(ardopCIVAddress, radix: 16) ?? 0x98
    }

    /// Launch configuration for the bundled ardopcf.
    var ardopLaunchConfig: ArdopLaunchConfig {
        var launch = ArdopLaunchConfig()
        launch.controlPort = UInt16(clamping: ardopControlPort)
        launch.captureDevice = ardopCaptureDevice.isEmpty ? "DEFAULT" : ardopCaptureDevice
        launch.playbackDevice = ardopPlaybackDevice.isEmpty ? "DEFAULT" : ardopPlaybackDevice
        if rigUseBundled {
            // rigctld hält den seriellen Port; ardopcf meldet PTT nur an
            // Skywave, das über den RigController tastet (oder VOX).
            launch.ptt = .none
            return launch
        }
        switch ardopPTTMode {
        case .catCIV:
            launch.ptt = .catCIV(
                port: ardopSerialPort,
                baud: ardopCATBaud,
                civAddress: UInt8(ardopCIVAddress, radix: 16) ?? 0x98)
        case .rts:
            launch.ptt = .rts(port: ardopSerialPort)
        case .rigctld, .none:
            // rigctld PTT is keyed by Skywave via the modem's PTT
            // handler, so ardopcf itself does not key anything.
            launch.ptt = .none
        }
        return launch
    }

    // MARK: - Funkgerät

    /// Der Weg zum Funkgerät als eine Auswahl — siehe `RigAccess`.
    var rigAccess: RigAccess {
        get {
            if rigUseBundled { return .bundled }
            // Externes Modem: dort schaltet seit jeher der eingetragene
            // Host die PTT über rigctld ein (`rigctldEnabled`), egal was
            // im PTT-Modus steht — die Anzeige folgt dem.
            if !ardopUseBundled, rigctldEnabled { return .external }
            switch ardopPTTMode {
            case .catCIV: return .civDirect
            case .rigctld: return .external
            case .rts, .none: return .none
            }
        }
        set {
            switch newValue {
            case .bundled:
                rigUseBundled = true
            case .civDirect:
                rigUseBundled = false
                ardopPTTMode = .catCIV
                disableExternalModemRigctld()
            case .external:
                rigUseBundled = false
                ardopPTTMode = .rigctld
            case .none:
                rigUseBundled = false
                // Eine RTS-Wahl bleibt stehen, alles andere wird VOX.
                if ardopPTTMode != .rts { ardopPTTMode = .none }
                disableExternalModemRigctld()
            }
        }
    }

    /// Beim externen Modem hängt die PTT über rigctld allein am Host.
    /// Wer im Tab einen anderen Weg wählt, schaltet sie damit ab — sonst
    /// zeigte der Tab «Kein CAT», und die Sitzung tastete weiter über
    /// rigctld.
    private func disableExternalModemRigctld() {
        if !ardopUseBundled { rigctldHost = "" }
    }

    /// Das gewählte Geräteprofil für den mitgelieferten rigctld.
    var rigProfile: RigProfile? {
        RigProfileCatalog.bundled.profile(id: rigProfileID)
    }

    /// Übernimmt ein Profil samt seiner CI-V-Adresse. Die Baudrate des
    /// Profils gilt nur, solange noch kein Port eingerichtet ist: eine
    /// bereits eingetragene passt zur Einstellung am Gerät und bliebe
    /// sonst still überschrieben (IC-7300: Profil 19200, Gerät oft 115200).
    func selectRigProfile(_ profile: RigProfile) {
        rigProfileID = profile.id
        if ardopSerialPort.trimmingCharacters(in: .whitespaces).isEmpty {
            ardopCATBaud = profile.defaultBaud
        }
        if let address = profile.defaultCIVAddress {
            ardopCIVAddress = address.replacingOccurrences(of: "0x", with: "")
                .replacingOccurrences(of: "0X", with: "")
        }
    }

    /// Verbindung für den `RigController`, falls Skywave das Gerät über
    /// rigctld erreicht und alles Nötige eingetragen ist; sonst nil.
    var rigLink: (link: RigController.Link, name: String)? {
        switch rigAccess {
        case .bundled:
            guard let profile = rigProfile else { return nil }
            let port = ardopSerialPort.trimmingCharacters(in: .whitespaces)
            let host = rigNetworkHost.trimmingCharacters(in: .whitespaces)
            if profile.needsSerialPort, port.isEmpty { return nil }
            if profile.isNetworkRig, host.isEmpty { return nil }
            let civ = ardopCIVAddress.trimmingCharacters(in: .whitespaces)
            let config = profile.launchConfig(
                serialPort: port, baud: ardopCATBaud,
                civAddress: civ.isEmpty ? nil : "0x\(civ)",
                networkHost: host, listenPort: RigController.bundledBasePort)
            return (.bundled(config), profile.displayName)
        case .external:
            let host = rigctldHost.trimmingCharacters(in: .whitespaces)
            guard !host.isEmpty else { return nil }
            return (
                .external(host: host, port: UInt16(clamping: rigctldPort)),
                "rigctld \(host):\(rigctldPort)"
            )
        case .civDirect, .none:
            return nil
        }
    }

    /// Skywave kann die Frequenz über rigctld (mitgeliefert oder fremd)
    /// einstellen — der `RigController` hält dafür die Verbindung.
    var rigQSYAvailable: Bool { rigLink != nil }

    /// Automatisches QSY ist auf irgendeinem Weg möglich.
    var qsyAvailable: Bool { civQSYAvailable || rigQSYAvailable }

    /// Skywave tastet über den mitgelieferten rigctld.
    var usesBundledRigPTT: Bool {
        rigUseBundled && rigPTTViaCAT
    }

    private func save() {
        let persisted = Persisted(
            callsign: callsign, locator: locator, cmsHost: cmsHost, cmsPort: cmsPort,
            varaHost: varaHost, varaCommandPort: varaCommandPort,
            varaDataPort: varaDataPort,
            ardopHost: ardopHost, ardopControlPort: ardopControlPort,
            ardopDataPort: ardopDataPort,
            rigctldHost: rigctldHost, rigctldPort: rigctldPort,
            varaHFGateway: varaHFGateway, varaHFBandwidth: varaHFBandwidth,
            varaFMGateway: varaFMGateway,
            ardopGateway: ardopGateway, ardopBandwidth: ardopBandwidth,
            ardopChannelID: ardopChannelID,
            ardopUseBundled: ardopUseBundled,
            ardopCaptureDevice: ardopCaptureDevice,
            ardopPlaybackDevice: ardopPlaybackDevice,
            ardopPTTMode: ardopPTTMode.rawValue,
            ardopSerialPort: ardopSerialPort,
            ardopCIVAddress: ardopCIVAddress,
            ardopCATBaud: ardopCATBaud,
            ardopDriveLevel: ardopDriveLevel,
            restoreQRGAfterSession: restoreQRGAfterSession,
            rigUseBundled: rigUseBundled,
            rigProfileID: rigProfileID,
            rigNetworkHost: rigNetworkHost,
            rigAutoConnect: rigAutoConnect,
            rigPTTViaCAT: rigPTTViaCAT,
            imageAttachmentTarget: imageAttachmentTarget.rawValue,
            autoFetchEnabled: autoFetchEnabled,
            autoFetchIntervalMinutes: autoFetchIntervalMinutes,
            gatewayRefreshEnabled: gatewayRefreshEnabled,
            gatewayMaxDistanceKm: gatewayMaxDistanceKm,
            radioInboundMaxKB: radioInboundMaxKB,
            positionSource: positionSource.rawValue,
            manualLatitude: manualLatitude,
            manualLongitude: manualLongitude,
            p2pPeer: p2pPeer,
            p2pKind: p2pKind.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: fileURL)
    }

    /// One-time import of settings that lived in UserDefaults before
    /// the data folder existed. No-op once settings.json is present.
    static func seedFromLegacyDefaults(fileURL: URL) {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let defaults = UserDefaults.standard
        let persisted = Persisted(
            callsign: defaults.string(forKey: SettingsKeys.callsign) ?? "",
            locator: defaults.string(forKey: SettingsKeys.locator) ?? "",
            cmsHost: defaults.string(forKey: SettingsKeys.cmsHost) ?? "",
            cmsPort: defaults.integer(forKey: SettingsKeys.cmsPort))
        guard persisted.callsign != "" || persisted.locator != "" || persisted.cmsHost != ""
        else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(persisted) else { return }
        try? data.write(to: fileURL)
    }
}
