import Foundation
import Testing

@testable import Skywave

@MainActor
@Suite struct ConnectionHistoryStoreTests {

    private func makeFileURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connection-history.json")
    }

    private func record(
        gateway: String = "HB9AK", kind: RadioTransportKind? = .ardop,
        outcome: ConnectionRecord.Outcome = .success, bytes: Int = 9000,
        seconds: TimeInterval = 240, date: Date = Date()
    ) -> ConnectionRecord {
        ConnectionRecord(
            date: date, gateway: gateway, kind: kind, centerHz: 3_614_500,
            durationSeconds: seconds, bytesSent: bytes / 3, bytesReceived: bytes - bytes / 3,
            sent: 1, received: 2, outcome: outcome, errorText: nil)
    }

    @Test func newestFirstPersistsAndLooksUpPerGatewayAndKind() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ConnectionHistoryStore(fileURL: url)
        let older = Date().addingTimeInterval(-3600)
        store.record(record(outcome: .success, date: older))
        store.record(record(outcome: .failed))
        store.record(record(gateway: "HB9AK", kind: .varaHF))
        store.record(record(gateway: "server.winlink.org", kind: nil))

        #expect(store.records.first?.kind == nil)
        #expect(store.records(gateway: "hb9ak", kind: .ardop).count == 2)
        #expect(store.last(gateway: "HB9AK", kind: .ardop)?.outcome == .failed)
        #expect(store.lastSuccess(gateway: "HB9AK", kind: .ardop)?.date == older)
        #expect(store.lastSuccess(gateway: "HB9AK", kind: .varaFM) == nil)

        let reopened = ConnectionHistoryStore(fileURL: url)
        #expect(reopened.records.count == 4)
        #expect(reopened.lastSuccess(gateway: "HB9AK", kind: .ardop)?.outcome == .success)
    }

    @Test func historyIsCapped() {
        let url = makeFileURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = ConnectionHistoryStore(fileURL: url)
        for _ in 0..<(ConnectionHistoryStore.limit + 5) {
            store.record(record())
        }
        #expect(store.records.count == ConnectionHistoryStore.limit)
    }

    @Test func derivedValues() {
        let fast = record(bytes: 9000, seconds: 240)
        #expect(fast.band == "80 m")
        #expect(fast.bytesPerSecond == 37.5)
        #expect(fast.rateText == "38 B/s")
        #expect(fast.durationText == "4 min")

        let empty = record(bytes: 0, seconds: 45)
        #expect(empty.bytesPerSecond == nil)
        #expect(empty.rateText == nil)
        #expect(empty.durationText == "45 s")
    }
}
