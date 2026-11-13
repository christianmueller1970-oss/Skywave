import Foundation
import Testing
import WinlinkKit

@testable import Skywave

@Suite struct PositionResolverTests {

    /// Der Locator liefert den Zellen-Mittelpunkt und sagt, wie gross
    /// die Zelle ist — keine GPS-Koordinate.
    @Test func locatorGivesCellCentreWithSize() throws {
        let position = try #require(PositionResolver.fromLocator("jn47pn"))
        #expect(abs(position.latitude - 47.5625) < 0.0001)
        #expect(abs(position.longitude - 9.2917) < 0.0001)
        #expect(position.accuracyText == "Mittelpunkt von JN47pn, Zelle ca. 6,3 × 4,6 km")
        #expect(position.coordinateText == "47.5625° N, 9.2917° E")

        #expect(PositionResolver.fromLocator("") == nil)
        #expect(PositionResolver.fromLocator("XX") == nil)
        #expect(PositionResolver.fromLocator("JN47")?.accuracyText.contains("150,3 × 111,2 km") == true)
    }

    @Test func manualAcceptsCommaAndChecksRange() {
        let position = PositionResolver.fromManual(latitude: "47,5", longitude: " 9.3° ")
        #expect(position?.latitude == 47.5)
        #expect(position?.longitude == 9.3)
        #expect(position?.accuracyText == "Wie eingegeben")
        #expect(PositionResolver.fromManual(latitude: "91", longitude: "9") == nil)
        #expect(PositionResolver.fromManual(latitude: "47", longitude: "181") == nil)
        #expect(PositionResolver.fromManual(latitude: "", longitude: "9") == nil)
        #expect(PositionResolver.fromManual(latitude: "abc", longitude: "9") == nil)
    }

    @Test func serviceReportsAccuracyAndAge() {
        let fresh = PositionResolver.fromService(
            latitude: 47.5, longitude: 9.3, accuracyMeters: 65.4, timestamp: Date())
        #expect(fresh.accuracyText == "Standortdienst (WLAN/IP-Ortung), ± 65 m")
        let coarse = PositionResolver.fromService(
            latitude: 47.5, longitude: 9.3, accuracyMeters: 2500,
            timestamp: Date().addingTimeInterval(-600))
        #expect(coarse.accuracyText == "Standortdienst (WLAN/IP-Ortung), ± 2,5 km, 10 min alt")
    }

    /// Ein Fix des Standortdienstes behält seinen Messzeitpunkt in
    /// der Meldung; Locator und Handeingabe bekommen «jetzt».
    @Test func reportDateIsTheFixTimestamp() throws {
        let measured = Date(timeIntervalSince1970: 1_469_030_400)
        let now = measured.addingTimeInterval(1800)
        let service = PositionResolver.fromService(
            latitude: 47.5, longitude: 9.3, accuracyMeters: 50, timestamp: measured)
        #expect(PositionResolver.report(position: service, comment: "", now: now).date == measured)

        let manual = try #require(PositionResolver.fromManual(latitude: "47.5", longitude: "9.3"))
        #expect(PositionResolver.report(position: manual, comment: "", now: now).date == now)
        let locator = try #require(PositionResolver.fromLocator("JN47PN"))
        #expect(PositionResolver.report(position: locator, comment: "", now: now).date == now)
    }

    /// Die Meldung trägt Koordinaten, gekürzten Kommentar und Zeitpunkt.
    @Test func reportCarriesPositionAndTrimmedComment() throws {
        let position = try #require(PositionResolver.fromManual(latitude: "47.5", longitude: "9.3"))
        let now = Date(timeIntervalSince1970: 1_469_030_400)
        let report = PositionResolver.report(
            position: position, comment: "  " + String(repeating: "x", count: 90) + "  ", now: now)
        #expect(report.latitude == 47.5)
        #expect(report.longitude == 9.3)
        #expect(report.comment.count == 80)
        #expect(report.date == now)
        let message = report.message(mycall: "HB9HJI")
        #expect(message.to.map(\.description) == ["QTH"])
        #expect(message.bodyText.hasPrefix("DATE: 2016/07/20 16:00\r\nLATITUDE: 47-30.0000N\r\n"))
    }
}
