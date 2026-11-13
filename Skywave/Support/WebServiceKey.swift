import Foundation

/// The Winlink Web Services access key that ships with the app.
///
/// The key is not in the repository. `scripts/generate-webservice-key.sh`
/// runs before every build, reads it from `SKYWAVE_WEBSERVICE_KEY` or
/// `~/.config/skywave/webservice-key`, XOR-masks it and writes it into
/// the bundle's Resources. Without a configured key the blob is absent,
/// `value` is empty, and the gateway directory falls back to the
/// built-in starter list — so a fresh clone builds and runs.
///
/// The mask keeps the key out of a plain `strings` sweep over the DMG.
/// It is obfuscation, not protection: anyone determined can recover it
/// from the shipped binary. That is a known and accepted trade-off for
/// a key that must work without the user configuring anything. The
/// client-side rate limit in `GatewayWebService` is what actually
/// protects the token.
enum WebServiceKey {
    /// Must stay byte-identical to PAD in the generator script.
    private static let pad = Array("ch.hb9hji.skywave.webservice.v1".utf8)
    private static let blobName = "wsk"

    /// The access key, or an empty string when none was injected.
    static let value: String = load()

    private static func load() -> String {
        guard let url = Bundle.main.url(forResource: blobName, withExtension: "dat"),
            let masked = try? Data(contentsOf: url)
        else { return "" }
        return unmask(masked)
    }

    /// XOR against the repeating pad. Symmetric, so the same routine
    /// would mask — the generator script does that side in Python.
    static func unmask(_ masked: Data) -> String {
        guard !masked.isEmpty else { return "" }
        let clear = masked.enumerated().map { index, byte in
            byte ^ pad[index % pad.count]
        }
        return String(decoding: clear, as: UTF8.self)
    }

    /// Test helper — the generator's Python must produce exactly this.
    static func mask(_ key: String) -> Data {
        Data(
            Array(key.utf8).enumerated().map { index, byte in
                byte ^ pad[index % pad.count]
            })
    }
}
