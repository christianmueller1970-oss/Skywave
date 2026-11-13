import Foundation
import Testing

@testable import Skywave

/// A unique temp file URL for a settings.json.
private func makeFileURL() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("settings.json")
}

@MainActor
@Suite struct AppSettingsStoreTests {

    /// An edited callsign/locator must survive being reloaded
    /// (i.e. app relaunch).
    @Test func editsPersistAcrossReload() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        store.callsign = "hb9hji"
        store.locator = "JN47PN"

        // A fresh store over the same file = a relaunch.
        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.callsign == "HB9HJI")
        #expect(reloaded.locator == "JN47PN")
    }

    /// Die QRG-Rueckstellung ist per Vorgabe aus — das Geraet bleibt
    /// nach der Sitzung auf dem Kanal des Gateways stehen — und die
    /// Wahl ueberlebt einen Neustart.
    @Test func qrgRestoreDefaultsOffAndPersists() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.restoreQRGAfterSession == false)

        store.restoreQRGAfterSession = true
        #expect(AppSettingsStore(fileURL: url).restoreQRGAfterSession)
    }

    /// Callsign is normalized to upper case without looping.
    @Test func callsignUppercases() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        store.callsign = "hb9hji"
        #expect(store.callsign == "HB9HJI")
        #expect(store.effectiveCallsign == "HB9HJI")
    }

    /// CMS host/port fall back to the production defaults when unset.
    @Test func cmsDefaults() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.cmsHost == SettingsKeys.defaultCMSHost)
        #expect(store.cmsPort == SettingsKeys.defaultCMSPort)
        #expect(store.effectiveCMSPort == UInt16(SettingsKeys.defaultCMSPort))
    }

    /// Radio fields fall back to their defaults when unset.
    @Test func radioDefaults() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.varaHost == SettingsKeys.defaultVaraHost)
        #expect(store.varaCommandPort == SettingsKeys.defaultVaraCommandPort)
        #expect(store.varaDataPort == SettingsKeys.defaultVaraDataPort)
        #expect(store.ardopHost == SettingsKeys.defaultArdopHost)
        #expect(store.ardopControlPort == SettingsKeys.defaultArdopControlPort)
        #expect(store.ardopDataPort == SettingsKeys.defaultArdopDataPort)
        // Vorgabe des TNC, bewusst uebernommen: kein stiller Eingriff
        // ins Sendeverhalten bestehender Installationen.
        #expect(store.ardopDriveLevel == SettingsKeys.defaultArdopDriveLevel)
        #expect(store.rigctldHost == "")
        #expect(store.rigctldPort == SettingsKeys.defaultRigctldPort)
        #expect(!store.rigctldEnabled)
        #expect(store.varaHFGateway == "")
        #expect(store.varaHFBandwidth == SettingsKeys.defaultVaraHFBandwidth)
        #expect(store.ardopBandwidth == SettingsKeys.defaultArdopBandwidth)
        #expect(store.varaConfig.host == "localhost")
        #expect(store.varaConfig.commandPort == 8300)
        #expect(store.ardopConfig.controlPort == 8515)
    }

    /// Edited radio fields must survive a reload; gateways uppercase.
    @Test func radioEditsPersistAcrossReload() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        store.ardopUseBundled = false  // Legacy-Regel gilt nur mit externem TNC
        store.varaHost = "10.0.0.5"
        store.varaCommandPort = 8400
        store.ardopDriveLevel = 55
        store.rigctldHost = "localhost"
        store.varaHFGateway = "hb9ak"
        store.varaHFBandwidth = "500"
        store.ardopGateway = "hb9pd"
        store.ardopBandwidth = "500FORCED"

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.varaHost == "10.0.0.5")
        #expect(reloaded.varaCommandPort == 8400)
        #expect(reloaded.ardopDriveLevel == 55)
        #expect(reloaded.rigctldHost == "localhost")
        #expect(reloaded.rigctldEnabled)
        #expect(reloaded.varaHFGateway == "HB9AK")
        #expect(reloaded.varaHFBandwidth == "500")
        #expect(reloaded.ardopGateway == "HB9PD")
        #expect(reloaded.ardopBandwidth == "500FORCED")
    }

    /// Auto-Abruf ist ab Werk aus, Intervall 30 min; beides übersteht
    /// einen Reload.
    @Test func autoFetchSettingsPersistAcrossReload() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(!store.autoFetchEnabled)
        #expect(store.autoFetchIntervalMinutes == 30)
        store.autoFetchEnabled = true
        store.autoFetchIntervalMinutes = 60

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.autoFetchEnabled)
        #expect(reloaded.autoFetchIntervalMinutes == 60)
    }

    /// Die Ziel-Bildgrösse startet auf «Mittel» und übersteht einen
    /// Reload.
    @Test func imageAttachmentTargetPersistsAcrossReload() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.imageAttachmentTarget == .medium)
        #expect(store.imageAttachmentTarget.targetBytes == 150_000)
        store.imageAttachmentTarget = .small

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.imageAttachmentTarget == .small)
    }

    /// Bundled-ardopcf settings persist and produce the matching
    /// launch configuration (CI-V hex derived from the address).
    @Test func bundledArdopSettingsPersistAndMapToLaunchConfig() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.ardopUseBundled)  // Integriert ist seit dem bestandenen RF-Test Standard
        #expect(store.ardopPTTMode == .catCIV)
        store.ardopUseBundled = true
        store.ardopCaptureDevice = "USB Audio CODEC"
        store.ardopPlaybackDevice = "USB Audio CODEC"
        store.ardopSerialPort = "/dev/cu.usbmodem14201"
        store.ardopCIVAddress = "98"

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.ardopUseBundled)
        #expect(reloaded.ardopCaptureDevice == "USB Audio CODEC")
        #expect(reloaded.ardopPTTMode == .catCIV)

        let launch = reloaded.ardopLaunchConfig
        #expect(launch.captureDevice == "USB Audio CODEC")
        #expect(launch.ptt == .catCIV(
            port: "/dev/cu.usbmodem14201", baud: 115200, civAddress: 0x98))
        #expect(launch.arguments().contains("FEFE98E01C0001FD"))
        #expect(launch.modemConfig.controlPort == 8515)

        // rigctld PTT only counts when the mode says so (bundled TNC).
        reloaded.rigctldHost = "localhost"
        #expect(!reloaded.rigctldEnabled)
        reloaded.ardopPTTMode = .rigctld
        #expect(reloaded.rigctldEnabled)
        #expect(reloaded.ardopLaunchConfig.ptt == .none)
    }

    /// The picker choice from the ARDOP connect dialog persists, and
    /// the CI-V QSY is only available for the integrated TNC with CAT
    /// PTT and a configured serial port.
    @Test func gatewayChannelPersistsAndQSYGating() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.ardopChannelID == "")
        #expect(!store.civQSYAvailable)  // bundled TNC off by default

        store.ardopChannelID = "HB9MM/ardop/7053000"
        store.ardopUseBundled = true
        #expect(!store.civQSYAvailable)  // still no serial port
        store.ardopSerialPort = "/dev/cu.usbserial-11420"
        #expect(store.civQSYAvailable)
        store.ardopPTTMode = .rigctld
        #expect(!store.civQSYAvailable)  // QSY needs the CAT (CI-V) port
        store.ardopPTTMode = .catCIV

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.ardopChannelID == "HB9MM/ardop/7053000")
        #expect(reloaded.civQSYAvailable)
        #expect(reloaded.civAddress == 0x98)
        reloaded.ardopCIVAddress = "A4"  // IC-705
        #expect(reloaded.civAddress == 0xA4)
    }

    /// A settings.json written before the radio fields existed must
    /// still decode — otherwise every setting silently resets. (The
    /// radio fields are Optionals in Persisted for exactly this.)
    @Test func oldSettingsFileStillDecodes() throws {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let legacy = """
            {
              "callsign" : "HB9HJI",
              "cmsHost" : "server.winlink.org",
              "cmsPort" : 8772,
              "locator" : "JN47PN"
            }
            """
        try Data(legacy.utf8).write(to: url)

        let store = AppSettingsStore(fileURL: url)
        #expect(store.callsign == "HB9HJI")
        #expect(store.locator == "JN47PN")
        #expect(store.varaHost == SettingsKeys.defaultVaraHost)
        #expect(store.ardopHost == SettingsKeys.defaultArdopHost)
    }

    /// A missing settings.json plus legacy UserDefaults values seeds
    /// the file once — the move out of the app container.
    @Test func seedsFromLegacyDefaults() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // The tests run inside the real app process, so .standard IS
        // the user's preferences — save and restore what is there.
        let original = UserDefaults.standard.string(forKey: SettingsKeys.callsign)
        UserDefaults.standard.set("HB3XXX", forKey: SettingsKeys.callsign)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: SettingsKeys.callsign)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKeys.callsign)
            }
        }

        AppSettingsStore.seedFromLegacyDefaults(fileURL: url)
        #expect(AppSettingsStore(fileURL: url).callsign == "HB3XXX")

        // Never overwrites an existing file.
        UserDefaults.standard.set("HB9YYY", forKey: SettingsKeys.callsign)
        AppSettingsStore.seedFromLegacyDefaults(fileURL: url)
        #expect(AppSettingsStore(fileURL: url).callsign == "HB3XXX")
    }
}

@MainActor
@Suite struct VersandkontrolleSettingsTests {
    /// Die Eingangsgrenze über Funk ist per Vorgabe aus (0) und
    /// überlebt einen Neustart.
    @Test func radioInboundLimitDefaultsOffAndPersists() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        #expect(store.radioInboundMaxKB == 0)
        store.radioInboundMaxKB = 50

        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.radioInboundMaxKB == 50)
    }

    // MARK: - Funkgerät (Weg zum Gerät)

    /// Bestehende Installationen: der Weg ergibt sich aus dem bisherigen
    /// PTT-Modus, nichts wird ungefragt auf rigctld umgestellt.
    @Test func rigAccessDerivesFromLegacyPTTMode() throws {
        let cases: [(String, RigAccess)] = [
            ("catCIV", .civDirect), ("rigctld", .external), ("rts", .none), ("none", .none),
        ]
        for (legacy, expected) in cases {
            let url = makeFileURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            // So sieht eine settings.json aus 0.6.0 aus: ohne rig*-Schlüssel.
            let json = """
                {"callsign":"HB9HJI","locator":"JN47PN","cmsHost":"","cmsPort":0,
                 "ardopUseBundled":true,"ardopPTTMode":"\(legacy)",
                 "ardopSerialPort":"/dev/cu.usbserial-1","ardopCIVAddress":"A4",
                 "ardopCATBaud":19200,"rigctldHost":"localhost","rigctldPort":4532}
                """
            try Data(json.utf8).write(to: url)

            let store = AppSettingsStore(fileURL: url)
            #expect(store.rigAccess == expected, "\(legacy)")
            #expect(!store.rigUseBundled)
            #expect(store.ardopPTTMode.rawValue == legacy)
            #expect(store.civQSYAvailable == (legacy == "catCIV"))
            #expect(store.rigctldEnabled == (legacy == "rigctld"))
            #expect(store.ardopCATBaud == 19200)
            #expect(store.rigAutoConnect)
        }
    }

    /// Der mitgelieferte rigctld hält den Port: ardopcf tastet nicht
    /// selbst, und die bisherigen Wege (CI-V-QSY, Sitzungs-rigctld) ruhen.
    @Test func bundledRigAccessTakesThePortFromArdopcf() throws {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        store.ardopUseBundled = true
        store.ardopSerialPort = "/dev/cu.usbserial-1"
        store.rigctldHost = "localhost"
        #expect(store.rigLink == nil)  // CI-V direkt: kein RigController

        store.rigAccess = .bundled
        #expect(store.rigLink == nil)  // noch kein Modell gewählt
        let ic705 = try #require(RigProfileCatalog.bundled.profile(id: "icom-ic705"))
        store.selectRigProfile(ic705)
        #expect(store.ardopCATBaud == 115200)
        #expect(store.ardopCIVAddress == "A4")
        #expect(store.ardopLaunchConfig.ptt == .none)
        #expect(!store.civQSYAvailable)
        #expect(!store.rigctldEnabled)
        #expect(store.usesBundledRigPTT)

        let link = try #require(store.rigLink)
        #expect(link.name == "Icom IC-705")
        guard case .bundled(let config) = link.link else {
            Issue.record("erwartet .bundled")
            return
        }
        #expect(config.model == 3085)
        #expect(config.civAddress == "0xA4")
        #expect(config.connection == .serial(.init(port: "/dev/cu.usbserial-1", baud: 115200)))

        // Zurück auf den direkten Weg: alles wie vorher, Wahl überlebt den Neustart.
        store.rigAccess = .civDirect
        #expect(store.civQSYAvailable)
        store.rigAccess = .bundled
        let reloaded = AppSettingsStore(fileURL: url)
        #expect(reloaded.rigAccess == .bundled)
        #expect(reloaded.rigProfileID == "icom-ic705")
    }

    /// Die Modellwahl überschreibt keine Baudrate, die schon zu einem
    /// eingerichteten Port gehört — nur ohne Port gilt die Profilvorgabe.
    @Test func selectingAProfileKeepsAnEstablishedBaudRate() throws {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ic7300 = try #require(RigProfileCatalog.bundled.profile(id: "icom-ic7300"))

        let store = AppSettingsStore(fileURL: url)
        store.selectRigProfile(ic7300)
        #expect(store.ardopCATBaud == 19200)  // kein Port: Vorgabe des Profils
        #expect(store.ardopCIVAddress == "94")

        store.ardopSerialPort = "/dev/cu.usbserial-1"
        store.ardopCATBaud = 115200
        store.ardopCIVAddress = "A4"
        store.selectRigProfile(ic7300)
        #expect(store.ardopCATBaud == 115200)  // eingerichtet: bleibt stehen
        #expect(store.ardopCIVAddress == "94")  // die Adresse gehört zum Modell

        // QSY: bisher über CI-V direkt, nach dem Umstellen über rigctld.
        #expect(store.civQSYAvailable && !store.rigQSYAvailable && store.qsyAvailable)
        store.rigAccess = .bundled
        #expect(!store.civQSYAvailable && store.rigQSYAvailable && store.qsyAvailable)
        store.rigAccess = .none
        #expect(!store.qsyAvailable)
    }

    /// RTS mit dem integrierten ardopcf tastet nicht (Sandbox) — nur
    /// dann zeigt der Tab «Funkgerät» den Hinweis.
    @Test func rtsHintOnlyForBundledArdopcfWithRTS() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppSettingsStore(fileURL: url)
        store.rigAccess = .none
        store.ardopPTTMode = .rts
        store.ardopUseBundled = true
        #expect(store.rtsPTTBlockedBySandbox)

        store.ardopPTTMode = .none
        #expect(!store.rtsPTTBlockedBySandbox)

        store.ardopPTTMode = .rts
        store.ardopUseBundled = false
        #expect(!store.rtsPTTBlockedBySandbox)

        store.ardopUseBundled = true
        store.rigAccess = .civDirect
        #expect(!store.rtsPTTBlockedBySandbox)
    }

    /// Externes Modem mit eingetragenem rigctld-Host (Regel aus 0.6.0):
    /// der Tab zeigt den fremden rigctld, und wer wegschaltet, schaltet
    /// die PTT über rigctld wirklich ab (Codex-Review 2026-11-12).
    @Test func externalModemWithRigctldHostShowsAndLeavesExternal() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = AppSettingsStore(fileURL: url)
        store.ardopUseBundled = false
        store.ardopPTTMode = .none
        store.rigctldHost = "localhost"
        #expect(store.rigctldEnabled)
        #expect(store.rigAccess == .external)

        store.rigAccess = .none
        #expect(store.rigAccess == .none)
        #expect(!store.rigctldEnabled)

        // Zurück auf den fremden rigctld: Host neu eintragen, dann tastet er wieder.
        store.rigAccess = .external
        #expect(store.rigAccess == .external)
        store.rigctldHost = "localhost"
        #expect(store.rigctldEnabled)

        // Mit dem integrierten ardopcf bleibt der Host beim Wegschalten stehen.
        store.ardopUseBundled = true
        store.rigAccess = .none
        #expect(store.rigctldHost == "localhost")
        #expect(!store.rigctldEnabled)
    }

    @Test func rigAccessSetterMapsToLegacyPTTModes() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = AppSettingsStore(fileURL: url)
        store.rigAccess = .external
        #expect(store.ardopPTTMode == .rigctld)
        #expect(store.rigLink == nil)  // Host fehlt
        store.rigctldHost = "shack.local"
        store.rigctldPort = 4533
        #expect(store.rigLink?.link == .external(host: "shack.local", port: 4533))

        store.rigAccess = .none
        #expect(store.ardopPTTMode == .none)
        store.ardopPTTMode = .rts
        store.rigAccess = .bundled
        store.rigAccess = .none
        #expect(store.ardopPTTMode == .rts)  // RTS-Wahl bleibt erhalten
    }
}
