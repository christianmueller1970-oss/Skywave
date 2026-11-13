// Der Assistent tastet im Ernstfall einen
// Sender. Hier tut er das gegen ein Attrappen-Modem und eine erfundene
// ALC — nie gegen Hardware.
import Foundation
import Testing

@testable import Skywave

/// Merkt sich, was am Modem gestellt wurde.
private actor FakeModem: LevelTunableModem {
    private(set) var levels = [Int]()
    private(set) var toneBursts = 0
    /// Zuletzt gestellter Pegel — die erfundene ALC richtet sich danach.
    private(set) var currentLevel = 0

    func setDriveLevel(_ level: Int) async throws {
        levels.append(level)
        currentLevel = level
    }
    func sendTwoToneTest() async throws { toneBursts += 1 }
}

@MainActor
struct LevelTuningControllerTests {

    /// Baut einen Controller, dessen «Gerät» ab `respondsFrom` eine ALC
    /// meldet, die mit dem Pegel steigt.
    private func makeController(
        respondsFrom: Int?, connected: Bool = true
    ) -> (LevelTuningController, FakeModem) {
        let modem = FakeModem()
        let controller = LevelTuningController(
            measurable: { connected },
            readALC: {
                guard let respondsFrom else { return nil }
                return await modem.currentLevel >= respondsFrom ? 0.10 : 0.0
            },
            readWatts: { 5.0 },
            dwell: .milliseconds(30), samplePause: .milliseconds(5),
            burstDuration: .milliseconds(40)
        ) {
            (modem, {})
        }
        return (controller, modem)
    }

    private func run(_ controller: LevelTuningController) async {
        controller.start()
        while controller.isRunning {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Spricht die ALC bei 50 % an, ist 40 % der gesuchte Wert — eine
    /// Stufe darunter bleibt die Regelung sicher aussen vor.
    @Test func picksTheStepBelowTheFirstALCResponse() async {
        let (controller, _) = makeController(respondsFrom: 50)
        await run(controller)
        #expect(controller.phase == .finished(level: 40))
    }

    /// Spricht sie schon auf der untersten Stufe an, bleibt nur diese.
    @Test func staysOnTheLowestStepWhenALCRespondsImmediately() async {
        let (controller, _) = makeController(respondsFrom: 0)
        await run(controller)
        #expect(controller.phase == .finished(level: LevelTuningController.ladder[0]))
    }

    /// Spricht die ALC bis zum vollen Pegel nicht an, ist nicht der
    /// Software-Pegel das Problem, sondern der Eingangspegel im Gerät —
    /// «100 % übernehmen» waere hier ein falscher Rat.
    @Test func reportsRigInputTooLowWhenALCNeverResponds() async {
        let (controller, _) = makeController(respondsFrom: 1000)
        await run(controller)
        #expect(controller.phase == .rigInputTooLow(peakWatts: 5.0))
    }

    /// Ohne ALC-Meldung wird nicht geraten, sondern gesagt, dass es
    /// nicht geht.
    @Test func reportsFailureWhenTheRigHasNoALC() async {
        let (controller, _) = makeController(respondsFrom: nil)
        await run(controller)
        if case .failed(let message) = controller.phase {
            #expect(message.contains("ALC"))
        } else {
            Issue.record("Erwartet .failed, war \(controller.phase)")
        }
    }

    /// Je geprüfter Stufe genau ein Burst — nicht mehr, sonst weist
    /// das TNC ihn ab, und nicht weniger, sonst wird ohne Signal gemessen.
    @Test func oneBurstPerStep() async throws {
        let (controller, modem) = makeController(respondsFrom: 50)
        await run(controller)
        let bursts = await modem.toneBursts
        #expect(bursts == controller.samples.count)
        #expect(bursts > 0)
    }

    /// Ohne rigctld gibt es nichts zu messen.
    @Test func cannotMeasureWithoutAConnectedRig() {
        let (controller, _) = makeController(respondsFrom: 50, connected: false)
        #expect(!controller.canMeasure)
    }
}
