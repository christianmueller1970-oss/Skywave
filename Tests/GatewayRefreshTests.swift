// Refreshing the gateway list against a fake fetch. Nothing here talks
// to the network — the access key comes with a sparing-use condition,
// and the test suite must never be the thing that violates it.
import Foundation
import Testing
import WinlinkKit

@testable import Skywave

/// Counts requests so a test can assert that none went out.
private actor RequestCounter {
    private(set) var count = 0

    func bump() {
        count += 1
    }
}

@MainActor
@Suite struct GatewayRefreshTests {
    private static let key = "TESTKEY-0123456789"

    /// Shaped like the live answer from api.winlink.org (2026-08-07):
    /// Mode 43 = ARDOP 2000, 41 = ARDOP 500, and Baud says "600"
    /// regardless — it is not the bandwidth.
    private static let ardopAnswer = """
        {"GatewayList":[
          {"Callsign":"HB9AK","Gridsquare":"JN36PV","Frequency":7051500,"Mode":43,
           "Baud":"600","ServiceCode":"PUBLIC","Distance":105,"Heading":92},
          {"Callsign":"HB9AK","Gridsquare":"JN36PV","Frequency":10145900,"Mode":43,
           "Baud":"600","ServiceCode":"PUBLIC","Distance":105,"Heading":92},
          {"Callsign":"HB9MM","Gridsquare":"JN36HN","Frequency":10145300,"Mode":41,
           "Baud":"600","ServiceCode":"PUBLIC","Distance":143,"Heading":113}
        ]}
        """

    private func makeFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("gateways.json")
    }

    private func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func makeSettings() -> AppSettingsStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
        let settings = AppSettingsStore(fileURL: url)
        settings.locator = "JN47PN"
        return settings
    }

    private func makeStore(
        fileURL: URL, apiKey: String = key, status: Int = 200,
        body: String = ardopAnswer
    ) -> (GatewayStore, RequestCounter) {
        let counter = RequestCounter()
        let payload = Data(body.utf8)
        let store = GatewayStore(fileURL: fileURL, apiKey: apiKey) { _ in
            await counter.bump()
            return HTTPResponse(status: status, body: payload)
        }
        return (store, counter)
    }

    // MARK: - The happy path

    @Test func refreshReplacesTheBuiltInListAndComputesDistance() async throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL)

        await store.refresh(settings: makeSettings(), force: true)

        #expect(await counter.count == 1)
        #expect(!store.usesBuiltinFallback)
        #expect(store.cached.count == 3)
        #expect(store.lastRefresh != nil)
        #expect(store.lastError == nil)
        #expect(store.channels.allSatisfy { $0.source == .webService })

        let hb9ak = try #require(store.channel(id: "HB9AK/ardop/7051500"))
        // Computed locally from JN47PN → JN36PV, not taken from the
        // service's rounded miles.
        #expect(hb9ak.distanceKm == 168)
        #expect(hb9ak.headingDegrees == 245)
        #expect(hb9ak.bandwidthHz == 2000)
    }

    /// HB9AK really announces ARDOP 2000 on 30 m (mode 43 in the live
    /// data); IARU Region 1 makes the band narrow-band only.
    @Test func thirtyMetreChannelIsCappedRegardlessOfWhatTheServiceSays() async throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, _) = makeStore(fileURL: fileURL)

        await store.refresh(settings: makeSettings(), force: true)

        let thirty = try #require(store.channel(id: "HB9AK/ardop/10145900"))
        #expect(thirty.band == "30 m")
        #expect(thirty.bandwidthHz == 500)

        // HB9MM states ARDOP 500 there itself — same result, other route.
        let hb9mm = try #require(store.channel(id: "HB9MM/ardop/10145300"))
        #expect(hb9mm.bandwidthHz == 500)
    }

    @Test func refreshedListSurvivesARelaunch() async throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, _) = makeStore(fileURL: fileURL)

        await store.refresh(settings: makeSettings(), force: true)

        let reopened = GatewayStore(fileURL: fileURL, apiKey: Self.key) { _ in
            HTTPResponse(status: 200, body: Data())
        }
        #expect(reopened.cached.count == 3)
        // Stored as the user typed it, not in the canonical spelling.
        #expect(reopened.cachedGridSquare == "JN47PN")
        #expect(!reopened.usesBuiltinFallback)
    }

    /// Favourites are user data. A refresh may not touch them — not
    /// even one that no longer lists the starred channel.
    @Test func favoritesSurviveARefreshThatDropsTheChannel() async throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, _) = makeStore(fileURL: fileURL, body: #"{"GatewayList":[]}"#)
        store.toggleFavorite("HB9AK/ardop/7051500")

        await store.refresh(settings: makeSettings(), force: true)

        #expect(store.isFavorite("HB9AK/ardop/7051500"))
        #expect(store.orphanedFavorites.isEmpty)  // still in the built-in list
    }

    // MARK: - Nothing is spent when it cannot succeed

    @Test func noKeyMeansNoRequestAndNoKey() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL, apiKey: "")

        await store.refresh(settings: makeSettings(), force: true)

        #expect(await counter.count == 0)
        #expect(!store.hasAccessKey)
        #expect(store.usesBuiltinFallback)
        #expect(store.refreshBlockedReason(settings: makeSettings()) != nil)
    }

    @Test(arguments: ["", "JN47PNX", "nonsense"])
    func missingOrMalformedLocatorSpendsNothing(_ locator: String) async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL)
        let settings = makeSettings()
        settings.locator = locator

        await store.refresh(settings: settings, force: true)

        #expect(await counter.count == 0)
        #expect(store.refreshBlockedReason(settings: settings) != nil)
    }

    /// The hourly limit inside GatewayWebService binds even the button.
    @Test func secondForcedRefreshWithinTheHourSendsNothing() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL)
        let settings = makeSettings()

        await store.refresh(settings: settings, force: true)
        await store.refresh(settings: settings, force: true)

        #expect(await counter.count == 1)
    }

    /// A fresh cache is not refreshed on its own; only the button gets
    /// past the 24 h rule.
    @Test func automaticRefreshSkipsAFreshCache() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL)
        let settings = makeSettings()

        await store.refresh(settings: settings, force: true)
        #expect(store.nextAllowedRefresh != nil)

        await store.refresh(settings: settings, force: false)
        #expect(await counter.count == 1)
    }

    @Test func automaticRefreshRespectsTheSetting() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (store, counter) = makeStore(fileURL: fileURL)
        let settings = makeSettings()
        settings.gatewayRefreshEnabled = false

        await store.refresh(settings: settings, force: false)

        #expect(await counter.count == 0)
    }

    // MARK: - Failures

    /// A failed attempt must not make the cache look fresh, and it must
    /// not throw away what we already have.
    @Test func failureKeepsTheCacheAndArmsTheBackoff() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let (good, _) = makeStore(fileURL: fileURL)
        await good.refresh(settings: makeSettings(), force: true)
        let refreshedAt = good.lastRefresh

        let (store, _) = makeStore(fileURL: fileURL, status: 500)
        await store.refresh(settings: makeSettings(), force: true)

        #expect(store.cached.count == 3)  // still there
        #expect(store.lastRefresh == refreshedAt)  // unchanged
        #expect(store.lastError != nil)
        #expect(store.consecutiveFailures == 1)
        #expect(store.nextAllowedRefresh != nil)
    }

    /// A rejected key stops the automatic refresh instead of knocking
    /// on — that is what would get the token revoked.
    @Test func rejectedKeyLatchesAndStopsRefreshing() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let denied = """
            {"GatewayList":[],"ResponseStatus":{"ErrorCode":"InvalidAccessKey",
             "Message":"Invalid access key for this operation"}}
            """
        let (store, counter) = makeStore(fileURL: fileURL, status: 400, body: denied)
        let settings = makeSettings()

        await store.refresh(settings: settings, force: true)

        #expect(store.accessDenied)
        #expect(store.refreshBlockedReason(settings: settings)?.contains("abgelehnt") == true)

        // Neither an automatic nor a forced run tries again.
        await store.refresh(settings: settings, force: false)
        await store.refresh(settings: settings, force: true)
        #expect(await counter.count == 1)
    }

    @Test func accessDeniedLatchSurvivesARelaunch() async {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        let denied = """
            {"ResponseStatus":{"ErrorCode":"InvalidAccessKey","Message":"nope"}}
            """
        let (store, _) = makeStore(fileURL: fileURL, status: 400, body: denied)
        await store.refresh(settings: makeSettings(), force: true)

        let reopened = GatewayStore(fileURL: fileURL, apiKey: Self.key) { _ in
            HTTPResponse(status: 200, body: Data())
        }
        #expect(reopened.accessDenied)
    }

    // MARK: - Mapping

    /// Modes Skywave has no transport for are dropped rather than
    /// shown as something they are not.
    @Test func onlyModesWithATransportAreKept() {
        let positions = [
            GatewayPosition(
                callsign: "HB9AK", gridSquare: "JN36PV", frequencyHz: 7_051_500,
                baud: "2000", serviceCode: "PUBLIC", distanceMiles: 104,
                headingDegrees: 246, queriedMode: .ardop, rawMode: 6),
            GatewayPosition(
                callsign: "HB9XY", gridSquare: "JN36PV", frequencyHz: 144_950_000,
                baud: "1200", serviceCode: "PUBLIC", distanceMiles: 104,
                headingDegrees: 246, queriedMode: .packet, rawMode: 1),
        ]

        let channels = GatewayStore.channels(from: positions, home: "JN47PN")

        #expect(channels.count == 1)
        #expect(channels[0].kind == .ardop)
    }

    /// A record without a usable grid square keeps the service's own
    /// distance rather than showing none.
    @Test func unusableGridFallsBackToTheServiceDistance() throws {
        let positions = [
            GatewayPosition(
                callsign: "HB9AK", gridSquare: "", frequencyHz: 7_051_500,
                baud: "2000", serviceCode: "PUBLIC", distanceMiles: 100,
                headingDegrees: 246, queriedMode: .ardop, rawMode: 6)
        ]

        let channel = try #require(
            GatewayStore.channels(from: positions, home: "JN47PN").first)

        #expect(channel.distanceKm == 161)  // 100 miles
        #expect(channel.headingDegrees == 246)
    }

    @Test func emptyOrBrokenRecordsAreDropped() {
        let positions = [
            GatewayPosition(
                callsign: "", gridSquare: "JN36PV", frequencyHz: 7_051_500, baud: "",
                serviceCode: "", distanceMiles: 0, headingDegrees: 0,
                queriedMode: .ardop, rawMode: 6),
            GatewayPosition(
                callsign: "HB9AK", gridSquare: "JN36PV", frequencyHz: 0, baud: "",
                serviceCode: "", distanceMiles: 0, headingDegrees: 0,
                queriedMode: .ardop, rawMode: 6),
        ]

        #expect(GatewayStore.channels(from: positions, home: "JN47PN").isEmpty)
    }
}
