//
//  WatchProtocolVersioningTests.swift
//  SpektoWatch2Tests
//
//  M13 task-7 acceptance: version-byte rejection on legacy /
//  unknown payloads, and round-trip integrity of the new
//  WatchAppState envelope.
//

import XCTest
@testable import SpektoWatch2

final class WatchProtocolVersioningTests: XCTestCase {

    // MARK: - SpectrogramData version byte

    func testSpectrogramRoundTripIncludesVersionByte() {
        let original = SpectrogramData(
            frequencies: [100, 200, 300],
            magnitudes: [-30, -25, -35],
            broadbandLevel: -28,
            levels: ["LAF": -28, "LAeq": -30],
            sampleRate: 44100
        )
        let encoded = original.toBinaryData()

        // First byte must be the current schema version.
        XCTAssertEqual(encoded.first, SpectrogramData.currentSchemaVersion)
        XCTAssertEqual(encoded.first, 0x01)

        let decoded = SpectrogramData.fromBinaryData(encoded)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.broadbandLevel, -28)
        XCTAssertEqual(decoded?.sampleRate, 44100)
        XCTAssertEqual(decoded?.magnitudes, [-30, -25, -35])
        XCTAssertEqual(decoded?.frequencies, [100, 200, 300])
        XCTAssertEqual(decoded?.levels["LAF"], -28)
    }

    func testUnknownVersionRejected() {
        let original = SpectrogramData(
            frequencies: [100, 200],
            magnitudes: [-40, -42],
            broadbandLevel: -38,
            sampleRate: 44100
        )
        var encoded = original.toBinaryData()
        // Flip the version byte to a future / unknown value.
        encoded[encoded.startIndex] = 0x99

        let decoded = SpectrogramData.fromBinaryData(encoded)
        XCTAssertNil(decoded, "Unknown protocol version must be rejected, not parsed.")
    }

    func testEmptyDataIsRejected() {
        XCTAssertNil(SpectrogramData.fromBinaryData(Data()))
    }

    // MARK: - WatchAppState envelope

    func testWatchAppStateRoundTrip() throws {
        let state = WatchAppState(
            activePresetID: "overview",
            isRecording: true,
            designAccent: "phosphor",
            theme: "dark",
            toneGenerator: WatchAppState.ToneState(
                frequencyHz: 1000,
                amplitude: 0.5,
                waveform: "sine",
                isPlaying: false
            )
        )

        let encoded = try state.encode()
        let decoded = WatchAppState.decode(encoded)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded, state)
    }

    func testWatchAppStateUnknownVersionRejected() throws {
        // Build an envelope, then poke the JSON to bump the schema
        // version to a future value — must be rejected by the
        // decoder.
        let state = WatchAppState(
            activePresetID: nil,
            isRecording: false,
            designAccent: "amber",
            theme: "light"
        )
        var encoded = try state.encode()
        // Replace "schemaVersion":1 with "schemaVersion":99 by raw
        // string match. JSON key order is stable enough for this
        // test fixture.
        guard let json = String(data: encoded, encoding: .utf8) else {
            XCTFail("Envelope was not UTF-8 decodable.")
            return
        }
        let bumped = json.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":99")
        encoded = Data(bumped.utf8)

        XCTAssertNil(WatchAppState.decode(encoded),
            "WatchAppState with unknown schemaVersion must be rejected.")
    }

    func testProtocolMessageBuilderAndDecoder() {
        let state = WatchAppState(
            activePresetID: "spectrogram",
            isRecording: false,
            designAccent: "cyan",
            theme: "dark"
        )
        guard let message = WatchConnectivityProtocol.makeAppStateUpdateMessage(state) else {
            XCTFail("Failed to build appStateUpdate message.")
            return
        }
        XCTAssertEqual(message["type"] as? String,
            WatchConnectivityProtocol.MessageType.appStateUpdate.rawValue)

        let decoded = WatchConnectivityProtocol.appStateUpdate(from: message)
        XCTAssertEqual(decoded, state)
    }

    func testMalformedAppStateMessageRejected() {
        // type set, but no value blob.
        let badMessage: [String: Any] = [
            "type": WatchConnectivityProtocol.MessageType.appStateUpdate.rawValue
        ]
        XCTAssertNil(WatchConnectivityProtocol.appStateUpdate(from: badMessage))
    }
}
