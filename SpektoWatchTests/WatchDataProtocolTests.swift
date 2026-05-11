import XCTest
@testable import SpektoWatch_Watch_App

// MARK: - Watch Data Protocol Tests
//
// These tests cover the binary serialisation protocol as used on the Watch side,
// including a regression test for the TestFlight crash caused by
// `Data.dropFirst()` returning a non-zero-indexed slice.
//
// CRASH HISTORY (Build 33, April 2026):
//   EXC_BREAKPOINT in Data.copyBytes → triggered by `fromBinaryData` when called
//   with a Data slice whose startIndex != 0.  The fix wraps every dropFirst()
//   result in Data(...) to produce a freshly allocated, zero-indexed buffer.

final class WatchDataProtocolTests: XCTestCase {

    // MARK: - Slice index regression

    func testDropFirstReturnsNonZeroStartIndex() {
        // This documents the root cause: a slice starts at index 1, not 0.
        let original = Data([0x01, 0x02, 0x03, 0x04])
        let slice = original.dropFirst()

        XCTAssertEqual(slice.startIndex, 1,
            "dropFirst() returns a slice with startIndex == 1 – this is the root cause of the crash")
    }

    func testDataInitFromDropFirstResetsStartIndexToZero() {
        // The fix: wrapping the slice in Data(...) copies it into a zero-indexed buffer.
        let original = Data([0x01, 0x02, 0x03, 0x04])
        let fixed = Data(original.dropFirst())

        XCTAssertEqual(fixed.startIndex, 0,
            "Data(slice) must reset startIndex to 0 – required for copyBytes to work correctly")
    }

    func testDropFirstSliceCausesOutOfBoundsAccessForAbsoluteIndex() {
        // Demonstrates why copying is necessary: accessing index 0 of the slice
        // is an out-of-bounds access (the slice's valid range starts at 1).
        let original = Data([0x01, 0xAA, 0xBB])
        let slice = original.dropFirst()

        // slice[0] is out-of-bounds; slice[1] is the first valid byte.
        XCTAssertEqual(slice[1], 0xAA,
            "First payload byte is at absolute index 1 in the original slice")

        // After copying, index 0 is valid and contains the same byte.
        let copied = Data(slice)
        XCTAssertEqual(copied[0], 0xAA,
            "After Data(slice), the same byte is at index 0")
    }

    // MARK: - SpectrogramData binary round-trip

    func testSpectrogramDataRoundTrip() throws {
        let original = SpectrogramData(
            frequencies: [100, 500, 1000, 4000],
            magnitudes: [40.0, 50.0, 60.0, 55.0],
            magnitudesA: [38.0, 49.0, 62.0, 53.0],
            magnitudesC: [39.0, 49.5, 61.0, 54.0],
            broadbandLevel: 65.5,
            levels: ["LAeq": 65.5, "LCeq": 67.2],
            sampleRate: 44100.0
        )

        let binary = original.toBinaryData()
        let restored = try XCTUnwrap(SpectrogramData.fromBinaryData(binary),
            "fromBinaryData must succeed for valid binary data")

        XCTAssertEqual(restored.frequencies.count, original.frequencies.count)
        XCTAssertEqual(restored.magnitudes.count,  original.magnitudes.count)
        XCTAssertEqual(restored.broadbandLevel,    original.broadbandLevel, accuracy: 0.01)
        XCTAssertEqual(restored.sampleRate,        original.sampleRate,     accuracy: 0.01)

        for i in 0..<original.frequencies.count {
            XCTAssertEqual(restored.frequencies[i], original.frequencies[i], accuracy: 0.1,
                "frequencies[\(i)] mismatch")
            XCTAssertEqual(restored.magnitudes[i], original.magnitudes[i], accuracy: 0.1,
                "magnitudes[\(i)] mismatch")
        }
    }

    func testSpectrogramDataRoundTripViaPacketWithHeader() throws {
        // Simulates exactly what WatchConnectivityManager.session(_:didReceiveMessageData:) does:
        // prepend a 0x01 header byte, then deserialise the payload using the FIXED approach.
        let original = SpectrogramData(
            frequencies: [200, 1000],
            magnitudes: [55.0, 62.0],
            broadbandLevel: 58.0,
            sampleRate: 44100.0
        )

        // Sender side
        var packet = Data([0x01])
        packet.append(original.toBinaryData())

        // Receiver side (fixed version)
        let type    = packet[0]
        let payload = Data(packet.dropFirst()) // ← THE FIX: Data(...) wraps the slice

        XCTAssertEqual(type, 0x01)
        XCTAssertEqual(payload.startIndex, 0,
            "Payload must have startIndex 0 after wrapping")

        let restored = try XCTUnwrap(SpectrogramData.fromBinaryData(payload),
            "fromBinaryData must succeed when given a zero-indexed payload")
        XCTAssertEqual(restored.broadbandLevel, original.broadbandLevel, accuracy: 0.01)
    }

    // MARK: - Corrupted / short data

    func testEmptyPayloadReturnsNil() {
        XCTAssertNil(SpectrogramData.fromBinaryData(Data()),
            "Empty payload must return nil, not crash")
    }

    func testTruncatedPayloadReturnsNil() {
        // A 3-byte payload is too short for any valid spectrogram header.
        let truncated = Data([0x00, 0x01, 0x02])
        XCTAssertNil(SpectrogramData.fromBinaryData(truncated),
            "Truncated payload must return nil, not crash")
    }

    func testLargePayloadRoundTrip() throws {
        // 4096 bins – tests that large allocations don't corrupt indices.
        let count = 4096
        let freqs = (0..<count).map { Float($0) * 10.0 }
        let mags  = (0..<count).map { Float($0 % 100) }
        let data  = SpectrogramData(
            frequencies: freqs,
            magnitudes: mags,
            broadbandLevel: 75.0,
            sampleRate: 44100.0
        )

        let binary  = data.toBinaryData()
        var packet  = Data([0x01])
        packet.append(binary)

        let payload  = Data(packet.dropFirst())
        let restored = try XCTUnwrap(SpectrogramData.fromBinaryData(payload))
        XCTAssertEqual(restored.frequencies.count, count)
        XCTAssertEqual(restored.magnitudes.count,  count)
    }

    // MARK: - MicrophoneSource serialisation

    func testMicrophoneSourceRoundTrip() {
        for source in MicrophoneSource.allCases {
            let raw      = source.rawValue
            let restored = MicrophoneSource(rawValue: raw)
            XCTAssertEqual(restored, source,
                "MicrophoneSource.\(source) must round-trip through rawValue")
        }
    }

    func testMicrophoneSourceiPhoneRawValue() {
        XCTAssertEqual(MicrophoneSource.iPhone.rawValue, "iPhone")
    }

    func testMicrophoneSourceAppleWatchRawValue() {
        XCTAssertEqual(MicrophoneSource.appleWatch.rawValue, "Apple Watch")
    }
}
