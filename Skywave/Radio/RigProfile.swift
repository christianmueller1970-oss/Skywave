import Foundation
import WinlinkKit

/// Werkseinstellungen eines Funkgeräts für den mitgelieferten rigctld:
/// Hamlib-Modellnummer und die Vorgaben der seriellen Schnittstelle.
///
/// Die Daten stammen aus `rig-profiles.json`. Die Datei teilt Skywave
/// mit HAM-Tools — Felder, die Skywave nicht braucht (Frequenzbereich,
/// Tune-Kommando …), werden beim Lesen übergangen. So lässt sich die
/// Datei ohne Nacharbeit abgleichen.
struct RigProfile: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let brand: String
    let model: String
    let hamlibRigNumber: Int
    let defaultBaud: Int
    let defaultDataBits: Int
    let defaultStopBits: Int
    let defaultParity: String
    let defaultHandshake: String
    let needsSerialPort: Bool
    /// CI-V-Adresse als Hex-String («0xA4»); nil bei Geräten ohne CI-V.
    let defaultCIVAddress: String?
    /// Hamlib erreicht das Gerät selbst übers Netz (FlexRadio).
    let networkRig: Bool?

    var displayName: String { "\(brand) \(model)" }
    var isNetworkRig: Bool { networkRig == true }
    var usesCIVAddress: Bool { defaultCIVAddress != nil }

    /// Startkonfiguration für rigctld. `baud` und `civAddress` übersteuern
    /// die Vorgaben des Profils; leer bzw. nil lässt sie stehen.
    func launchConfig(
        serialPort: String, baud: Int? = nil, civAddress: String? = nil,
        networkHost: String = "", listenPort: UInt16
    ) -> RigctldLaunchConfig {
        var config = RigctldLaunchConfig(model: hamlibRigNumber, listenPort: listenPort)
        if needsSerialPort {
            config.connection = .serial(
                .init(
                    port: serialPort,
                    baud: baud ?? defaultBaud,
                    dataBits: defaultDataBits,
                    stopBits: defaultStopBits,
                    parity: RigctldLaunchConfig.Parity(rawValue: defaultParity) ?? .none,
                    // Icom und Xiegu (CI-V) nutzen nie Hardware-Flusssteuerung;
                    // mit RTS/CTS öffnet rigctld den Port nicht und beendet sich.
                    handshake: usesCIVAddress
                        ? .none
                        : RigctldLaunchConfig.Handshake(rawValue: defaultHandshake) ?? .none))
            if usesCIVAddress {
                let custom = civAddress?.trimmingCharacters(in: .whitespaces) ?? ""
                config.civAddress = custom.isEmpty ? defaultCIVAddress : custom
            }
        } else if isNetworkRig {
            config.connection = .network(host: networkHost)
        }
        return config
    }
}

/// Die mitgelieferten Geräteprofile, nach Hersteller gruppierbar.
struct RigProfileCatalog: Sendable {
    let profiles: [RigProfile]

    /// Liest `rig-profiles.json` aus dem App-Bundle.
    static let bundled: RigProfileCatalog = {
        guard let url = Bundle.main.url(forResource: "rig-profiles", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let profiles = try? JSONDecoder().decode([RigProfile].self, from: data)
        else { return RigProfileCatalog(profiles: []) }
        return RigProfileCatalog(profiles: profiles)
    }()

    func profile(id: String) -> RigProfile? {
        profiles.first { $0.id == id }
    }

    /// Hersteller in der Reihenfolge ihres ersten Auftretens.
    var brands: [String] {
        var seen = Set<String>()
        return profiles.map(\.brand).filter { seen.insert($0).inserted }
    }

    func profiles(brand: String) -> [RigProfile] {
        profiles.filter { $0.brand == brand }
    }
}
