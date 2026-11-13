// The key ships inside the app, masked. These tests pin the masking so
// the Swift side and the Python side of the generator script cannot
// drift apart.
import Foundation
import Testing

@testable import Skywave

@Suite struct WebServiceKeyTests {
    @Test func maskingRoundTrips() {
        let key = "1880278F-EXAMPLE-KEY-0123456789"

        #expect(WebServiceKey.unmask(WebServiceKey.mask(key)) == key)
    }

    /// The whole point: the key must not sit in the blob as plain text.
    @Test func maskedBlobDoesNotContainTheKey() {
        let key = "PROBE-KEY-abcdef123456"
        let masked = WebServiceKey.mask(key)

        #expect(masked.count == key.utf8.count)
        #expect(!String(decoding: masked, as: UTF8.self).contains(key))
        #expect(masked != Data(key.utf8))
    }

    /// The exact bytes the generator script must produce for this input.
    /// If the pad in either place changes, this test fails instead of
    /// the app silently shipping a key it cannot read back.
    @Test func maskingMatchesTheGeneratorScript() {
        let masked = WebServiceKey.mask("PROBE-KEY-abcdef123456")

        #expect(
            Array(masked) == [
                0x33, 0x3a, 0x61, 0x2a, 0x27, 0x14, 0x23, 0x2f, 0x30, 0x03,
                0x12, 0x09, 0x1a, 0x13, 0x04, 0x10, 0x54, 0x1c, 0x44, 0x51,
                0x57, 0x45,
            ])
    }

    /// No key configured is a normal state: the app then falls back to
    /// the built-in gateway list instead of failing to launch.
    @Test func missingBlobYieldsAnEmptyKey() {
        #expect(WebServiceKey.unmask(Data()) == "")
    }
}
