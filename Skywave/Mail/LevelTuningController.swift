// Der Pegel-Assistent stammt aus HAM-Tools. Hier kommen die Messwerte als
// Closures herein und werden vom Aufrufer aus einem RigctldClient gespeist.
import Foundation
import Observation
import WinlinkKit

/// Der Pegel-Assistent: sendet einen Zweiton und stellt den Sendepegel
/// so ein, dass die ALC des Geräts gerade eben anspricht.
///
/// Warum das nötig ist: ardopcf startet mit voller Amplitude. Auf einem
/// Dateneingang (USB-D und Verwandte) geht die NF ohne Mikrofonkette
/// direkt auf den Modulator — volle Amplitude übersteuert ihn dort
/// regelmässig. Übersteuerung verbreitert das Signal und kostet
/// Dekodierungen; nach unten ist der Verlust an Reichweite dagegen
/// gering. Deshalb der Richtwert «ALC kratzt gerade eben».
///
/// **Der Vorgang tastet den Sender.** Er gehört auf eine freie Frequenz
/// oder in die Kunstlast, und der Aufrufer muss darauf hinweisen.
/// Was der Assistent vom Modem braucht — mehr nicht.
///
/// Ein eigenes Protokoll statt `ArdopModem` direkt: Der Ablauf tastet
/// einen Sender, und der gehört abgesichert. Mit dieser Naht lässt sich
/// die Leiter-Logik gegen ein Attrappen-Modem prüfen, ohne dass je ein
/// echtes TNC oder ein Funkgerät im Spiel ist.
protocol LevelTunableModem: Sendable {
    func setDriveLevel(_ level: Int) async throws
    /// Einmal-Befehl: fünf Sekunden Zweiton, endet von selbst.
    func sendTwoToneTest() async throws
}

extension ArdopModem: LevelTunableModem {}

@MainActor @Observable final class LevelTuningController {

    enum Phase: Equatable, Sendable {
        case idle
        case starting
        /// Sendet und misst bei diesem Pegel.
        case measuring(level: Int)
        /// Fertig, mit gefundenem Pegel.
        case finished(level: Int)
        /// Die ALC hat bis zum vollen Pegel nicht angesprochen. Nicht die
        /// Software begrenzt dann, sondern der Eingangspegel im Gerät.
        case rigInputTooLow(peakWatts: Double?)
        case failed(String)
    }

    /// Eine Messung bei einem Pegel.
    struct Sample: Identifiable, Sendable {
        let id = UUID()
        let level: Int
        let alc: Float?
        let watts: Double?
    }

    public private(set) var phase: Phase = .idle
    public private(set) var samples = [Sample]()
    /// Laufende Anzeige während einer Messung.
    public private(set) var currentALC: Float?
    public private(set) var currentWatts: Double?
    public private(set) var log = [String]()

    /// Ab hier gilt die ALC als «spricht an». Hamlib normiert auf 0…1;
    /// unterhalb dieser Schwelle rauscht die Anzeige nur.
    static let alcThreshold: Float = 0.02
    /// Darüber begrenzt die Regelung deutlich — hier ist zu viel Pegel.
    static let alcTooHigh: Float = 0.25

    /// Pegel, die geprüft werden. Grob von unten nach oben: der erste,
    /// der die ALC anspricht, ist der gesuchte — eine Stufe darunter
    /// bleibt die Regelung sicher aussen vor.
    static let ladder = [20, 30, 40, 50, 60, 70, 80, 90, 100]

    /// Wie lange bei einem Pegel gesendet und gemessen wird, und in
    /// welchem Abstand dabei abgelesen wird. Als Parameter, damit die
    /// Tests den Ablauf in Millisekunden statt in Minuten durchspielen.
    static let defaultDwell: Duration = .milliseconds(1800)
    static let defaultSamplePause: Duration = .milliseconds(250)

    private var task: Task<Void, Never>?
    private let launch: () async throws -> (any LevelTunableModem, () async -> Void)
    /// Messwerte: nil bedeutet «das Gerät meldet das nicht».
    private let readALC: () async -> Float?
    private let readWatts: () async -> Double?
    /// Ob überhaupt gemessen werden kann — ohne rigctld gibt es nichts.
    private let measurable: () -> Bool

    /// `launch` liefert ein verbundenes Modem und den Weg, es wieder
    /// abzubauen — injiziert, damit der Ablauf ohne echtes ardopcf
    /// testbar bleibt.
    private let dwell: Duration
    private let samplePause: Duration

    private let burstDuration: Duration

    /// Was vom Burst nach dem Messen noch übrig ist — so lange muss
    /// gewartet werden, bevor der nächste angefordert werden darf.
    private var restOfBurst: Duration {
        burstDuration > dwell ? burstDuration - dwell : .milliseconds(50)
    }

    init(
        measurable: @escaping () -> Bool,
        readALC: @escaping () async -> Float?,
        readWatts: @escaping () async -> Double?,
        dwell: Duration = LevelTuningController.defaultDwell,
        samplePause: Duration = LevelTuningController.defaultSamplePause,
        burstDuration: Duration = ArdopModem.twoToneDuration,
        launch: @escaping () async throws -> (any LevelTunableModem, () async -> Void)
    ) {
        self.measurable = measurable
        self.readALC = readALC
        self.readWatts = readWatts
        self.dwell = dwell
        self.samplePause = samplePause
        self.burstDuration = burstDuration
        self.launch = launch
    }

    var isRunning: Bool {
        switch phase {
        case .starting, .measuring: true
        default: false
        }
    }

    /// Kann überhaupt automatisch geregelt werden, oder bleibt nur
    /// Handbetrieb? Ohne ALC-Meldung fehlt die Messgrösse.
    var canMeasure: Bool { measurable() }

    func start() {
        guard !isRunning else { return }
        samples = []
        log = []
        currentALC = nil
        currentWatts = nil
        phase = .starting
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        if isRunning { phase = .idle }
    }

    private func note(_ text: String) {
        log.append(text)
    }

    private func run() async {
        var modem: (any LevelTunableModem)?
        var teardown: (() async -> Void)?
        do {
            note(String(localized: "Starte Modem …"))
            let (m, down) = try await launch()
            modem = m
            teardown = down

            var found: Int?
            for level in Self.ladder {
                if Task.isCancelled { break }
                phase = .measuring(level: level)
                try await m.setDriveLevel(level)
                try await m.sendTwoToneTest()
                let reading = await measure()
                // Der Burst laeuft weiter; erst abwarten, sonst weist das
                // TNC den naechsten Zweiton ab («not from state»).
                try? await Task.sleep(for: restOfBurst)

                samples.append(Sample(level: level, alc: reading.alc, watts: reading.watts))
                note(levelSummary(level: level, reading: reading))

                if let alc = reading.alc, alc >= Self.alcThreshold {
                    // Eine Stufe zurück: bei diesem Pegel greift die
                    // Regelung schon, darunter nicht.
                    found = Self.ladder.first.map { first in
                        level == first ? first : Self.ladder[Self.ladder.firstIndex(of: level)! - 1]
                    }
                    break
                }
            }

            await teardown?()
            modem = nil
            teardown = nil

            if Task.isCancelled {
                phase = .idle
            } else if let found {
                note(String(localized: "Gefunden: \(String(found)) %"))
                phase = .finished(level: found)
            } else if samples.allSatisfy({ $0.alc == nil }) {
                phase = .failed(String(localized:
                    "Das Funkgerät meldet keine ALC — bitte von Hand einstellen."))
            } else {
                // Nie angesprochen, obwohl bis zum vollen Pegel gesendet
                // wurde: Dann ist die NF, die beim Gerät ankommt, zu
                // schwach — daran ändert der Software-Pegel nichts mehr.
                // Der Regler bliebe auf 100 %, und das Ergebnis waere
                // trotzdem ein untersteuerter Sender.
                let peak = samples.compactMap(\.watts).max()
                note(String(localized: "ALC sprach bis 100 % nicht an."))
                phase = .rigInputTooLow(peakWatts: peak)
            }
        } catch {
            await teardown?()
            phase = .failed(String(describing: error))
        }
    }

    private func measure() async -> (alc: Float?, watts: Double?) {
        var peakALC: Float?
        var peakWatts: Double?
        let deadline = ContinuousClock.now.advanced(by: dwell)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            if let alc = await readALC() {
                peakALC = max(peakALC ?? 0, alc)
                currentALC = alc
            }
            if let watts = await readWatts() {
                peakWatts = max(peakWatts ?? 0, watts)
                currentWatts = watts
            }
            try? await Task.sleep(for: samplePause)
        }
        return (peakALC, peakWatts)
    }

    private func levelSummary(level: Int, reading: (alc: Float?, watts: Double?)) -> String {
        let alcText = reading.alc.map { String(format: "%.2f", $0) } ?? "—"
        let wattText = reading.watts.map { String(format: "%.1f W", $0) } ?? "—"
        return String(localized: "Pegel \(String(level)) %: ALC \(alcText), \(wattText)")
    }
}
