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

    // MARK: - Binary packet header (Phase 6, task 6.3)

    func testBinaryPacketHeaderRoundTrip() {
        let header = WatchConnectivityProtocol.BinaryPacketHeader(kind: .spectrogram)
        let decoded = WatchConnectivityProtocol.BinaryPacketHeader.decode(from: header.encode())
        XCTAssertEqual(decoded, header)
    }

    func testMakeSpectrogramPacketUsesFourByteHeader() {
        let original = SpectrogramData(
            frequencies: [100],
            magnitudes: [50],
            broadbandLevel: 55,
            sampleRate: 44_100
        )
        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(original)
        XCTAssertGreaterThanOrEqual(packet.count, WatchConnectivityProtocol.BinaryPacketHeader.byteLength + 1)
        XCTAssertEqual(packet[0], WatchConnectivityProtocol.BinaryPacketKind.spectrogram.rawValue)
        XCTAssertEqual(packet[1], WatchConnectivityProtocol.binaryPacketFormatVersion)
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

    // MARK: - WatchConnectivityProtocol wire version (Phase 6, task 6.1)

    func testMissingProtocolVersionIsLegacy() {
        let legacy: [String: Any] = [
            WatchConnectivityProtocol.Key.type: WatchConnectivityProtocol.MessageType.gain.rawValue,
            WatchConnectivityProtocol.Key.value: Float(1.0)
        ]
        XCTAssertEqual(
            WatchConnectivityProtocol.protocolVersion(from: legacy),
            WatchConnectivityProtocol.legacyProtocolVersion
        )
    }

    func testOutgoingMessagesEmbedProtocolVersion() {
        let gain = WatchConnectivityProtocol.makeGainMessage(1.5)
        XCTAssertEqual(
            WatchConnectivityProtocol.protocolVersion(from: gain),
            WatchConnectivityProtocol.protocolVersion
        )
        XCTAssertEqual(
            WatchConnectivityProtocol.protocolVersion(from: WatchConnectivityProtocol.makeRecordingStartMessage()),
            WatchConnectivityProtocol.protocolVersion
        )
    }

    func testFutureProtocolVersionStillParsesPayload() throws {
        var message = WatchConnectivityProtocol.makeGainMessage(2.5)
        message[WatchConnectivityProtocol.Key.protocolVersion] = NSNumber(value: 99)
        message["futureField"] = "ignored"

        XCTAssertEqual(WatchConnectivityProtocol.protocolVersion(from: message), 99)
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: message), .gain)
        let parsedGain = try XCTUnwrap(WatchConnectivityProtocol.gain(from: message))
        XCTAssertEqual(parsedGain, 2.5, accuracy: 0.001)
    }

    func testMergingProtocolVersionIntoApplicationContext() {
        let context = WatchConnectivityProtocol.mergingProtocolVersion(into: ["frequencyWeighting": "A"])
        XCTAssertEqual(
            WatchConnectivityProtocol.peerProtocolVersion(from: context),
            WatchConnectivityProtocol.protocolVersion
        )
        XCTAssertEqual(context["frequencyWeighting"] as? String, "A")
    }

    // MARK: - WatchConnectivityMessageCodec round-trips (Phase 6, task 6.2)

    func testCodecRecordingControlRoundTrip() {
        let cases: [(WatchConnectivityProtocol.MessageType, MicrophoneSource?)] = [
            (.startRecording, nil),
            (.startRecording, .appleWatch),
            (.stopRecording, .iPhone)
        ]
        for (type, source) in cases {
            let wire: [String: Any]
            switch type {
            case .startRecording:
                wire = WatchConnectivityProtocol.makeRecordingStartMessage(source: source)
            case .stopRecording:
                wire = WatchConnectivityProtocol.makeRecordingStopMessage(source: source)
            default:
                continue
            }
            let payload = WatchConnectivityMessageCodec.decodeRecordingControl(from: wire, type: type)
            XCTAssertEqual(payload, WatchConnectivityMessageCodec.RecordingControlPayload(source: source))
            let reencoded = WatchConnectivityMessageCodec.encode(payload!, type: type)
            XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
        }
    }

    func testCodecGainRoundTrip() {
        let wire = WatchConnectivityProtocol.makeGainMessage(2.5)
        let payload = WatchConnectivityMessageCodec.decodeGain(from: wire)
        XCTAssertEqual(payload, WatchConnectivityMessageCodec.GainPayload(gain: 2.5))
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }

    func testCodecMicrophoneSourceRoundTrip() {
        let wire = WatchConnectivityProtocol.makeMicrophoneSourceMessage(.appleWatch)
        let payload = WatchConnectivityMessageCodec.decodeMicrophoneSource(from: wire)
        XCTAssertEqual(payload, WatchConnectivityMessageCodec.MicrophoneSourcePayload(source: .appleWatch))
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }

    func testCodecFrequencyWeightingRoundTrip() {
        let wire = WatchConnectivityProtocol.makeFrequencyWeightingMessage("C")
        let payload = WatchConnectivityMessageCodec.decodeFrequencyWeighting(from: wire)
        XCTAssertEqual(payload, WatchConnectivityMessageCodec.FrequencyWeightingPayload(weighting: "C"))
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }

    func testCodecConfigStringRoundTrip() {
        let dashboard = WatchConnectivityProtocol.makeWatchDashboardConfigMessage("{\"v\":1}")
        let dashboardPayload = WatchConnectivityMessageCodec.decodeConfigString(from: dashboard, type: .watchDashboardConfig)
        XCTAssertEqual(dashboardPayload, WatchConnectivityMessageCodec.ConfigStringPayload(config: "{\"v\":1}"))
        XCTAssertTrue(
            WatchConnectivityMessageCodec.wireMessagesEqual(
                dashboard,
                WatchConnectivityMessageCodec.encode(dashboardPayload!, type: .watchDashboardConfig)
            )
        )

        let meter = WatchConnectivityProtocol.makeWatchMeterLayoutConfigMessage("[]")
        let meterPayload = WatchConnectivityMessageCodec.decodeConfigString(from: meter, type: .watchMeterLayoutConfig)
        XCTAssertEqual(meterPayload, WatchConnectivityMessageCodec.ConfigStringPayload(config: "[]"))
        XCTAssertTrue(
            WatchConnectivityMessageCodec.wireMessagesEqual(
                meter,
                WatchConnectivityMessageCodec.encode(meterPayload!, type: .watchMeterLayoutConfig)
            )
        )
    }

    func testCodecMeasurementSourcePreferenceRoundTrip() {
        let wire = WatchConnectivityProtocol.makeWatchMeasurementSourcePreferenceMessage(.appleWatch)
        let payload = WatchConnectivityMessageCodec.decodeMeasurementSourcePreference(from: wire)
        XCTAssertEqual(
            payload,
            WatchConnectivityMessageCodec.MeasurementSourcePreferencePayload(preference: .appleWatch)
        )
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }

    func testCodecAppStateUpdateRoundTrip() throws {
        let state = WatchAppState(
            activePresetID: "overview",
            isRecording: false,
            designAccent: "cyan",
            theme: "dark"
        )
        guard let wire = WatchConnectivityProtocol.makeAppStateUpdateMessage(state) else {
            XCTFail("Failed to encode app state")
            return
        }
        let payload = WatchConnectivityMessageCodec.decodeAppStateUpdate(from: wire)
        XCTAssertEqual(payload, WatchConnectivityMessageCodec.AppStateUpdatePayload(state: state))
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded!))
    }

    func testCodecRecordingFileTransferRoundTrip() throws {
        let id = UUID()
        let metadata = try JSONEncoder().encode(
            WatchRecordingMetadata(
                id: id,
                title: "Test",
                createdAt: Date(timeIntervalSince1970: 1_000),
                duration: 12,
                sampleRate: 44_100,
                weighting: "A",
                audioFileName: "\(id.uuidString).caf",
                measurementFileName: "\(id.uuidString).swr",
                laeq: 60,
                lcPeak: 80,
                minLevel: 40
            )
        )
        let wire = WatchConnectivityProtocol.makeRecordingFileTransferMetadata(
            id: id,
            kind: .audio,
            metadata: metadata
        )
        let payload = WatchConnectivityMessageCodec.decodeRecordingFileTransfer(from: wire)
        XCTAssertEqual(
            payload,
            WatchConnectivityMessageCodec.RecordingFileTransferPayload(id: id, kind: .audio, metadata: metadata)
        )
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }

    func testCodecRecordingSyncedRoundTrip() {
        let id = UUID()
        let wire = WatchConnectivityProtocol.makeRecordingSyncedUserInfo(id: id)
        let payload = WatchConnectivityMessageCodec.decodeRecordingSynced(from: wire)
        XCTAssertEqual(payload, WatchConnectivityMessageCodec.RecordingSyncedPayload(id: id))
        let reencoded = WatchConnectivityMessageCodec.encode(payload!)
        XCTAssertTrue(WatchConnectivityMessageCodec.wireMessagesEqual(wire, reencoded))
    }
}
