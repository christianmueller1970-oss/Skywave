import Foundation
import Testing

@testable import Skywave

/// Filter im Bereich «Verbindungen» und die Liste der Sitzungsprotokolle.
@MainActor
@Suite struct ConnectionHistoryViewTests {
    private func record(
        _ gateway: String, _ kind: RadioTransportKind?, _ outcome: ConnectionRecord.Outcome,
        centerHz: Int? = nil
    ) -> ConnectionRecord {
        ConnectionRecord(
            date: Date(timeIntervalSince1970: 1_794_500_000), gateway: gateway, kind: kind,
            centerHz: centerHz, durationSeconds: 60, bytesSent: 0, bytesReceived: 0,
            sent: 0, received: 0, outcome: outcome, errorText: nil)
    }

    private var sample: [ConnectionRecord] {
        [
            record("HB9AK", .ardop, .success, centerHz: 3_614_500),
            record("HB9AK", .ardop, .aborted),
            record("HB9MM", .varaHF, .failed),
            record("cms.winlink.org", nil, .success),
        ]
    }

    @Test func filtersByWay() {
        var filter = ConnectionFilter()
        #expect(filter.apply(to: sample).count == 4)
        filter.way = .internet
        #expect(filter.apply(to: sample).map(\.gateway) == ["cms.winlink.org"])
        filter.way = .radio(.ardop)
        #expect(filter.apply(to: sample).count == 2)
        filter.way = .radio(.varaFM)
        #expect(filter.apply(to: sample).isEmpty)
    }

    @Test func filtersByOutcomeAndCallsign() {
        var filter = ConnectionFilter()
        filter.outcome = .success
        #expect(filter.apply(to: sample).count == 2)
        filter.way = .radio(.ardop)
        #expect(filter.apply(to: sample).count == 1)

        filter = ConnectionFilter()
        filter.search = " hb9m "
        #expect(filter.apply(to: sample).map(\.gateway) == ["HB9MM"])
    }

    /// Zeiten in der Liste stehen in UTC, der Weg ohne Modem heisst «Internet».
    @Test func rowTextsUseUTCAndNameTheWay() {
        let radio = sample[0]
        // 1'794'500'000 s = 12.11.2026 16:13:20 UTC
        #expect(radio.utcStamp == "12.11.2026 16:13")
        #expect(radio.wayText == "ARDOP")
        #expect(radio.channelText?.contains("kHz") == true)
        #expect(radio.channelText?.contains("80 m") == true)
        #expect(sample[3].wayText == "Internet")
        #expect(sample[3].channelText == nil)
        #expect(sample[1].outcomeText == "Abgebrochen")
    }

    /// Protokolle: neueste zuerst, fremde Dateien bleiben aussen vor, der
    /// Beginn kommt aus dem Dateinamen.
    @Test func sessionLogsAreListedNewestFirst() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveLogs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in [
            "session-2026-11-11_20-12-00.log", "session-2026-11-12_17-39-05.log",
            "session-2026-10-11_17-50-15.log", "notizen.txt", "andere.log",
        ] {
            try Data("x".utf8).write(to: dir.appendingPathComponent(name))
        }

        let sessions = SessionLogStore.sessions(in: dir)
        #expect(sessions.map(\.url.lastPathComponent) == [
            "session-2026-11-12_17-39-05.log", "session-2026-11-11_20-12-00.log",
            "session-2026-10-11_17-50-15.log",
        ])

        // Der Dateiname trägt Ortszeit; der Titel zeigt UTC.
        let zurich = try #require(TimeZone(identifier: "Europe/Zurich"))
        let started = try #require(
            SessionLogStore.startDate(fromFileName: "session-2026-11-12_17-39-05.log", timeZone: zurich))
        #expect(SessionLogFile(url: sessions[0].url, started: started).title == "12.11.2026 16:39:05 UTC")
        #expect(SessionLogStore.startDate(fromFileName: "andere.log") == nil)
    }
}
