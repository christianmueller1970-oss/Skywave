// The channel type itself, against channels built in the test rather
// than against the built-in list — GatewayDirectoryTests covers that.
import Foundation
import Testing

@testable import Skywave

@Suite struct GatewayChannelTests {
    private func channel(
        gateway: String = "HB9AK", kind: RadioTransportKind = .ardop,
        centerHz: Int = 7_051_500, bandwidthHz: Int? = 2000,
        distanceKm: Int? = nil, headingDegrees: Int? = nil,
        source: GatewayChannel.Source = .builtin
    ) -> GatewayChannel {
        GatewayChannel(
            gateway: gateway, grid: "JN36PV", kind: kind, centerHz: centerHz,
            bandwidthHz: bandwidthHz, distanceKm: distanceKm,
            headingDegrees: headingDegrees, source: source)
    }

    /// The ID scheme must not change: `settings.ardopChannelID` and
    /// every favourite reference it, across both sources.
    @Test func idIsGatewayKindAndCenterFrequency() {
        #expect(channel().id == "HB9AK/ardop/7051500")
        #expect(channel(kind: .varaHF).id == "HB9AK/varaHF/7051500")
    }

    /// A web-service channel and a built-in one for the same frequency
    /// are the same entry as far as favourites are concerned.
    @Test func sourceDoesNotAffectIdentity() {
        #expect(channel(source: .builtin).id == channel(source: .webService).id)
    }

    @Test func dialSitsBelowCenterExceptOnFM() {
        #expect(channel().dialHz == 7_050_000)
        #expect(channel(kind: .varaFM, centerHz: 144_950_000).dialHz == 144_950_000)
    }

    @Test func menuLabelIsUnchangedByTheNewFields() {
        let plain = channel(centerHz: 7_053_000, distanceKm: nil)
        let enriched = channel(centerHz: 7_053_000, distanceKm: 168, headingDegrees: 246)

        #expect(plain.menuLabel == "HB9AK · 40 m · Dial 7'051,5 kHz")
        #expect(enriched.menuLabel == plain.menuLabel)
    }

    @Test func detailLabelAddsDistanceAndHeadingWhenKnown() {
        #expect(
            channel(centerHz: 7_053_000, distanceKm: 168, headingDegrees: 246)
                .detailLabel == "HB9AK · 40 m · Dial 7'051,5 kHz · 168 km · 246°")
        // Heading is zero-padded so the column lines up.
        #expect(
            channel(centerHz: 7_053_000, distanceKm: 12, headingDegrees: 8)
                .detailLabel == "HB9AK · 40 m · Dial 7'051,5 kHz · 12 km · 008°")
        #expect(channel(centerHz: 7_053_000).detailLabel == channel(centerHz: 7_053_000).menuLabel)
    }

    @Test func channelSurvivesAJSONRoundTrip() throws {
        let original = channel(distanceKm: 168, headingDegrees: 246, source: .webService)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(GatewayChannel.self, from: data)

        #expect(restored == original)
        #expect(restored.id == original.id)
    }

    /// The web service does not always report a usable bandwidth; nil
    /// must survive the cache so the UI knows to leave the setting be.
    @Test func missingBandwidthSurvivesTheCache() throws {
        let original = channel(bandwidthHz: nil, source: .webService)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(GatewayChannel.self, from: data)

        #expect(restored.bandwidthHz == nil)
    }

    @Test(arguments: [
        (1_838_000, "160 m"), (3_604_000, "80 m"), (7_053_000, "40 m"),
        (10_145_900, "30 m"), (14_110_400, "20 m"), (18_115_900, "17 m"),
        (21_115_000, "15 m"), (24_925_000, "12 m"), (28_120_000, "10 m"),
        (144_950_000, "UKW"),
    ])
    func bandIsDerivedFromTheCenterFrequency(_ centerHz: Int, _ band: String) {
        #expect(channel(centerHz: centerHz).band == band)
    }
}
