// The gateway cache over a temporary folder, same pattern as
// AppSettingsStoreTests. No networking in this file.
import Foundation
import Testing

@testable import Skywave

@MainActor
@Suite struct GatewayStoreTests {
    private func makeFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkywaveTests-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("gateways.json")
    }

    private func remove(_ fileURL: URL) {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }

    private func webChannel(
        gateway: String, centerHz: Int, distanceKm: Int?
    ) -> GatewayChannel {
        GatewayChannel(
            gateway: gateway, grid: "JN36PV", kind: .ardop, centerHz: centerHz,
            bandwidthHz: 2000, distanceKm: distanceKm, headingDegrees: 246,
            source: .webService)
    }

    // MARK: - Fallback

    @Test func emptyStoreServesTheBuiltInList() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)

        #expect(store.usesBuiltinFallback)
        #expect(store.channels.count == GatewayDirectory.channels.count)
        #expect(!store.channels(for: .ardop).isEmpty)
    }

    /// A corrupt file must not take the app down — it starts over from
    /// the built-in list.
    @Test func corruptFileFallsBackWithoutThrowing() throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json at all".utf8).write(to: fileURL)

        let store = GatewayStore(fileURL: fileURL)

        #expect(store.usesBuiltinFallback)
        #expect(store.favorites.isEmpty)
    }

    /// A file written by a future version is discarded, not
    /// half-interpreted.
    @Test func newerSchemaVersionIsDiscarded() throws {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let future = """
            { "version": 99, "favorites": ["HB9AK/ardop/7051500"] }
            """
        try Data(future.utf8).write(to: fileURL)

        let store = GatewayStore(fileURL: fileURL)

        #expect(store.usesBuiltinFallback)
        #expect(store.favorites.isEmpty)
    }

    // MARK: - Favourites

    @Test func favoritesSurviveARelaunch() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)
        store.toggleFavorite("HB9AK/ardop/7051500")
        #expect(store.isFavorite("HB9AK/ardop/7051500"))

        let reopened = GatewayStore(fileURL: fileURL)
        #expect(reopened.isFavorite("HB9AK/ardop/7051500"))

        reopened.toggleFavorite("HB9AK/ardop/7051500")
        #expect(!GatewayStore(fileURL: fileURL).isFavorite("HB9AK/ardop/7051500"))
    }

    /// A starred channel that is no longer listed stays a favourite. A
    /// gateway in maintenance must not silently eat the selection.
    @Test func favoriteOfAnUnlistedChannelIsKeptAndReported() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)
        store.toggleFavorite("XX0XX/ardop/7000000")

        #expect(store.isFavorite("XX0XX/ardop/7000000"))
        #expect(store.orphanedFavorites == ["XX0XX/ardop/7000000"])
        // A listed one is not orphaned.
        store.toggleFavorite("HB9AK/ardop/7051500")
        #expect(store.orphanedFavorites == ["XX0XX/ardop/7000000"])
    }

    // MARK: - Lookup and ordering

    /// The ID scheme is shared, so a stored ardopChannelID keeps
    /// resolving whether it comes from the cache or the built-in list.
    @Test func lookupFallsThroughToTheBuiltInList() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)

        #expect(store.channel(id: "HB9AK/ardop/7051500")?.gateway == "HB9AK")
        #expect(store.channel(id: "XX0XX/ardop/7000000") == nil)
    }

    @Test func sortingPutsFavoritesFirstThenNearest() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)
        let near = webChannel(gateway: "HB9AK", centerHz: 7_051_500, distanceKm: 168)
        let far = webChannel(gateway: "DK0WCY", centerHz: 3_612_000, distanceKm: 645)
        let unknown = webChannel(gateway: "HB9ZZ", centerHz: 14_110_400, distanceKm: nil)

        #expect(store.sorted([far, unknown, near]).map(\.gateway) == ["HB9AK", "DK0WCY", "HB9ZZ"])

        store.toggleFavorite(far.id)
        #expect(store.sorted([near, unknown, far]).map(\.gateway) == ["DK0WCY", "HB9AK", "HB9ZZ"])
    }

    @Test func suggestionsAreCappedForThePicker() {
        let fileURL = makeFileURL()
        defer { remove(fileURL) }

        let store = GatewayStore(fileURL: fileURL)

        #expect(store.suggestions(for: .ardop, limit: 3).count == 3)
        #expect(store.suggestions(for: .varaHF, limit: 3).isEmpty)
    }
}
