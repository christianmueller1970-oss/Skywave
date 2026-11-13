import Foundation

/// The built-in offline fallback for the gateway directory.
///
/// Hand-picked ARDOP starter channels reachable from HB9 (source:
/// cms.winlink.org GatewayChannels, service code PUBLIC, 2026-07-14).
/// `GatewayStore` replaces these with the live list from the Winlink
/// web service once one has been fetched; without a key, without a
/// locator or offline they remain what the connect dialog offers, so
/// the app never stands there with an empty picker.
enum GatewayDirectory {
    static let channels: [GatewayChannel] = [
        // HB9MM (Nyon VD) — ARDOP around the clock, primary target.
        // 30 m carries only ARDOP 500; the wider bands take 2000.
        .init(gateway: "HB9MM", grid: "JN36HN", kind: .ardop, centerHz: 3_605_500, bandwidthHz: 2000),
        .init(gateway: "HB9MM", grid: "JN36HN", kind: .ardop, centerHz: 7_053_000, bandwidthHz: 2000),
        .init(gateway: "HB9MM", grid: "JN36HN", kind: .ardop, centerHz: 10_145_300, bandwidthHz: 500),
        .init(gateway: "HB9MM", grid: "JN36HN", kind: .ardop, centerHz: 14_109_200, bandwidthHz: 2000),
        // HB9AK (JN36PV) — ARDOP around the clock.
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 3_614_500, bandwidthHz: 2000),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 7_051_500, bandwidthHz: 2000),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 10_145_900, bandwidthHz: 500),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 14_110_400, bandwidthHz: 2000),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 14_116_500, bandwidthHz: 2000),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 18_115_900, bandwidthHz: 2000),
        .init(gateway: "HB9AK", grid: "JN36PV", kind: .ardop, centerHz: 21_115_000, bandwidthHz: 2000),
        // HB9PC (Flanthey VS).
        .init(gateway: "HB9PC", grid: "JN36DJ", kind: .ardop, centerHz: 3_596_000, bandwidthHz: 2000),
        .init(gateway: "HB9PC", grid: "JN36DJ", kind: .ardop, centerHz: 3_604_000, bandwidthHz: 2000),
        .init(gateway: "HB9PC", grid: "JN36DJ", kind: .ardop, centerHz: 7_059_500, bandwidthHz: 2000),
    ]

    /// Channels for the open connect dialog, band order per gateway.
    static func channels(for kind: RadioTransportKind) -> [GatewayChannel] {
        channels.filter { $0.kind == kind }
    }

    static func channel(id: String) -> GatewayChannel? {
        channels.first { $0.id == id }
    }
}
