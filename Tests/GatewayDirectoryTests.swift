import Foundation
import Testing
import WinlinkKit

@testable import Skywave

@Suite struct GatewayDirectoryTests {

    /// Winlink lists center frequencies; the rig dial in USB-D sits
    /// 1.5 kHz below (the Spickzettel values).
    @Test func dialIsCenterMinus1500ForSSBData() throws {
        let hb9mm40m = try #require(GatewayDirectory.channel(id: "HB9MM/ardop/7053000"))
        #expect(hb9mm40m.dialHz == 7_051_500)
        #expect(hb9mm40m.band == "40 m")

        let hb9ak80m = try #require(GatewayDirectory.channel(id: "HB9AK/ardop/3614500"))
        #expect(hb9ak80m.dialHz == 3_613_000)
        #expect(hb9ak80m.band == "80 m")
    }

    @Test func swissKilohertzFormatting() {
        #expect(GatewayChannel.kilohertz(7_051_500) == "7'051,5")
        #expect(GatewayChannel.kilohertz(14_107_700) == "14'107,7")
        #expect(GatewayChannel.kilohertz(3_604_000) == "3'604,0")
        #expect(GatewayChannel.kilohertz(145_300_000) == "145'300,0")
    }

    @Test func menuLabelReadsLikeTheSpickzettel() throws {
        let channel = try #require(GatewayDirectory.channel(id: "HB9MM/ardop/7053000"))
        #expect(channel.menuLabel == "HB9MM · 40 m · Dial 7'051,5 kHz")
    }

    /// Starter data is ARDOP-only and each bandwidth must be one the
    /// connect dialog's segmented picker can represent.
    @Test func starterChannelsAreValidForTheDialog() throws {
        let ardop = GatewayDirectory.channels(for: .ardop)
        #expect(!ardop.isEmpty)
        #expect(ardop.count == GatewayDirectory.channels.count)
        #expect(GatewayDirectory.channels(for: .varaHF).isEmpty)
        for channel in ardop {
            // Unlike web-service channels, the built-in ones always
            // state a bandwidth — they were curated by hand.
            let width = try #require(channel.bandwidthHz)
            #expect(ArdopBandwidth.supportedMax.contains(width))
        }
        // IDs are unique — the picker and persistence rely on that.
        #expect(Set(GatewayDirectory.channels.map(\.id)).count == GatewayDirectory.channels.count)
    }

    /// The 30 m channels stay within ARDOP 500 (band-plan limit).
    @Test func thirtyMeterChannelsAreNarrow() {
        for channel in GatewayDirectory.channels where channel.band == "30 m" {
            #expect(channel.bandwidthHz == 500)
        }
    }

    @Test func unknownChannelIDReturnsNil() {
        #expect(GatewayDirectory.channel(id: "XX0XX/ardop/7000000") == nil)
        #expect(GatewayDirectory.channel(id: "") == nil)
    }
}
