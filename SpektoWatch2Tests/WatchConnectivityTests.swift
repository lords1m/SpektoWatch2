import XCTest
@testable import SpektoWatch2

/// Tests für WatchConnectivity - Testet Datenübertragung, Message Queue und Serialisierung
final class WatchConnectivityTests: XCTestCase {

    // MARK: - SpectrogramData Serialisierung Tests

    /// Testet SpectrogramData Serialisierung und Deserialisierung
    func testSpectrogramDataSerialization() {
        // Erstelle Test-Daten
        let frequencies: [Float] = [100, 200, 500, 1000, 2000, 5000]
        let magnitudes: [Float] = [40, 45, 50, 55, 60, 50]
        let magnitudesA: [Float] = [35, 42, 48, 55, 61, 48]
        let magnitudesC: [Float] = [38, 44, 49, 55, 59, 49]
        let broadbandLevel: Float = 65.5
        let levels: [String: Float] = ["LAF": 65.5, "LCF": 67.2, "LZF": 68.0]
        let sampleRate: Double = 44100.0

        let original = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            magnitudesA: magnitudesA,
            magnitudesC: magnitudesC,
            broadbandLevel: broadbandLevel,
            levels: levels,
            sampleRate: sampleRate
        )

        // Serialisiere zu Binary
        let binaryData = original.toBinaryData()
        XCTAssertGreaterThan(binaryData.count, 0, "Binary data should not be empty")

        // Deserialisiere
        guard let restored = SpectrogramData.fromBinaryData(binaryData) else {
            XCTFail("Failed to deserialize SpectrogramData")
            return
        }

        // Vergleiche
        XCTAssertEqual(restored.frequencies.count, original.frequencies.count, "Frequency count should match")
        XCTAssertEqual(restored.magnitudes.count, original.magnitudes.count, "Magnitude count should match")
        XCTAssertEqual(restored.broadbandLevel, original.broadbandLevel, accuracy: 0.1, "Broadband level should match")
        XCTAssertEqual(restored.sampleRate, original.sampleRate, accuracy: 0.1, "Sample rate should match")

        // Vergleiche einzelne Frequenzen
        for i in 0..<frequencies.count {
            XCTAssertEqual(restored.frequencies[i], original.frequencies[i], accuracy: 0.1,
                          "Frequency at index \(i) should match")
            XCTAssertEqual(restored.magnitudes[i], original.magnitudes[i], accuracy: 0.1,
                          "Magnitude at index \(i) should match")
        }
    }

    /// Testet SpectrogramData Serialisierung mit leeren Arrays
    func testSpectrogramDataSerializationEmpty() {
        let original = SpectrogramData(
            frequencies: [],
            magnitudes: [],
            broadbandLevel: 0,
            sampleRate: 44100.0
        )

        let binaryData = original.toBinaryData()
        guard let restored = SpectrogramData.fromBinaryData(binaryData) else {
            XCTFail("Failed to deserialize empty SpectrogramData")
            return
        }

        XCTAssertEqual(restored.frequencies.count, 0, "Empty frequencies should deserialize")
        XCTAssertEqual(restored.magnitudes.count, 0, "Empty magnitudes should deserialize")
    }

    /// Testet SpectrogramData Serialisierung mit großen Arrays
    func testSpectrogramDataSerializationLargeData() {
        // 4096 Bins (typisch für 8192 FFT)
        let count = 4096
        let frequencies = (0..<count).map { Float($0) * 10.0 }
        let magnitudes = (0..<count).map { Float($0 % 100) }

        let original = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 75.0,
            sampleRate: 44100.0
        )

        let binaryData = original.toBinaryData()
        guard let restored = SpectrogramData.fromBinaryData(binaryData) else {
            XCTFail("Failed to deserialize large SpectrogramData")
            return
        }

        XCTAssertEqual(restored.frequencies.count, count, "Large frequency array should deserialize")
        XCTAssertEqual(restored.magnitudes.count, count, "Large magnitude array should deserialize")
    }

    // MARK: - WatchDashboardConfig Serialisierung Tests

    /// Testet WatchDashboardConfig Encoding/Decoding
    func testWatchDashboardConfigSerialization() {
        let original = WatchDashboardConfig()

        // Encode
        guard let encoded = original.encode() else {
            XCTFail("Failed to encode WatchDashboardConfig")
            return
        }

        // Decode
        guard let restored = WatchDashboardConfig.decode(from: encoded) else {
            XCTFail("Failed to decode WatchDashboardConfig")
            return
        }

        XCTAssertEqual(restored.widgets.count, original.widgets.count)
        XCTAssertEqual(restored.version, original.version)

        // Vergleiche Widget-Positionen
        for (index, widget) in original.widgets.enumerated() {
            XCTAssertEqual(restored.widgets[index].position, widget.position)
            XCTAssertEqual(restored.widgets[index].type, widget.type)
        }
    }

    // MARK: - MicrophoneSource Tests

    /// Testet MicrophoneSource rawValue Konvertierung
    func testMicrophoneSourceRawValue() {
        XCTAssertEqual(MicrophoneSource.iPhone.rawValue, "iPhone")
        XCTAssertEqual(MicrophoneSource.appleWatch.rawValue, "Apple Watch")

        // Roundtrip
        for source in MicrophoneSource.allCases {
            let raw = source.rawValue
            let restored = MicrophoneSource(rawValue: raw)
            XCTAssertEqual(restored, source, "MicrophoneSource should round-trip through rawValue")
        }
    }

    // MARK: - Message Dictionary Tests

    /// Testet Gain-Nachricht Format
    func testGainMessageFormat() {
        let gain: Float = 2.5
        let message: [String: Any] = ["type": "gain", "value": gain]

        XCTAssertEqual(message["type"] as? String, "gain")
        XCTAssertEqual(message["value"] as? Float, gain)
    }

    /// Testet MicrophoneSource-Nachricht Format
    func testMicrophoneSourceMessageFormat() {
        let source = MicrophoneSource.appleWatch
        let message: [String: Any] = ["type": "microphoneSource", "source": source.rawValue]

        XCTAssertEqual(message["type"] as? String, "microphoneSource")
        XCTAssertEqual(message["source"] as? String, source.rawValue)
    }

    /// Testet Recording-Befehle Format
    func testRecordingCommandMessageFormat() {
        let startMessage: [String: Any] = ["type": "startRecording"]
        let stopMessage: [String: Any] = ["type": "stopRecording"]

        XCTAssertEqual(startMessage["type"] as? String, "startRecording")
        XCTAssertEqual(stopMessage["type"] as? String, "stopRecording")
    }

    // MARK: - Binary Protocol Tests

    /// Testet Spektrogramm-Paket Header
    func testSpectrogramPacketHeader() {
        let data = SpectrogramData(
            frequencies: [100, 200],
            magnitudes: [50, 60],
            broadbandLevel: 55.0,
            sampleRate: 44100.0
        )

        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(data)

        XCTAssertEqual(packet[0], WatchConnectivityProtocol.BinaryPacketKind.spectrogram.rawValue, "First byte should be spectrogram header")
    }

    func testTypedControlMessageFactories() throws {
        let startMessage = WatchConnectivityProtocol.makeRecordingStartMessage()
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: startMessage), .startRecording)
        XCTAssertNil(WatchConnectivityProtocol.recordingSource(from: startMessage))

        let wearableStartMessage = WatchConnectivityProtocol.makeRecordingStartMessage(source: .appleWatch)
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: wearableStartMessage), .startRecording)
        XCTAssertEqual(WatchConnectivityProtocol.recordingSource(from: wearableStartMessage), .appleWatch)

        let stopMessage = WatchConnectivityProtocol.makeRecordingStopMessage()
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: stopMessage), .stopRecording)

        let wearableStopMessage = WatchConnectivityProtocol.makeRecordingStopMessage(source: .appleWatch)
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: wearableStopMessage), .stopRecording)
        XCTAssertEqual(WatchConnectivityProtocol.recordingSource(from: wearableStopMessage), .appleWatch)

        let gainMessage = WatchConnectivityProtocol.makeGainMessage(2.5)
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: gainMessage), .gain)
        let parsedGain = try XCTUnwrap(WatchConnectivityProtocol.gain(from: gainMessage))
        XCTAssertEqual(parsedGain, 2.5, accuracy: 0.001)

        let sourceMessage = WatchConnectivityProtocol.makeMicrophoneSourceMessage(.appleWatch)
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: sourceMessage), .microphoneSource)
        XCTAssertEqual(WatchConnectivityProtocol.microphoneSource(from: sourceMessage), .appleWatch)

        let weightingMessage = WatchConnectivityProtocol.makeFrequencyWeightingMessage("A")
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: weightingMessage), .frequencyWeighting)
        XCTAssertEqual(WatchConnectivityProtocol.frequencyWeighting(from: weightingMessage), "A")

        let configMessage = WatchConnectivityProtocol.makeWatchDashboardConfigMessage("{}")
        XCTAssertEqual(WatchConnectivityProtocol.messageType(from: configMessage), .watchDashboardConfig)
        XCTAssertEqual(WatchConnectivityProtocol.dashboardConfigString(from: configMessage), "{}")
    }

    func testTypedSpectrogramPacketRoundTrip() {
        let original = SpectrogramData(
            frequencies: [100, 200, 500],
            magnitudes: [50, 60, 55],
            broadbandLevel: 57.0,
            levels: ["LAF": 57.0],
            sampleRate: 44_100
        )

        let packet = WatchConnectivityProtocol.makeSpectrogramPacket(original)
        guard case .spectrogram(let restored) = WatchConnectivityProtocol.decodeBinaryPayload(packet) else {
            XCTFail("Expected spectrogram packet")
            return
        }

        XCTAssertEqual(restored.frequencies, original.frequencies)
        XCTAssertEqual(restored.magnitudes, original.magnitudes)
        XCTAssertEqual(restored.broadbandLevel, original.broadbandLevel, accuracy: 0.001)
        XCTAssertEqual(restored.sampleRate, original.sampleRate, accuracy: 0.001)
    }

    func testUnknownBinaryPacketReturnsNil() {
        let packet = Data([0xFF, 0x00, 0x01])
        XCTAssertNil(WatchConnectivityProtocol.decodeBinaryPayload(packet))
    }

    func testLiveUpdatePolicyKeepsWatchDataFreshWithinOneSecond() {
        XCTAssertLessThanOrEqual(
            WatchConnectivityProtocol.normalSpectrogramSendInterval,
            WatchConnectivityProtocol.maximumLiveDataAgeSeconds
        )
        XCTAssertLessThanOrEqual(
            WatchConnectivityProtocol.lowPowerSpectrogramSendInterval,
            WatchConnectivityProtocol.maximumLiveDataAgeSeconds
        )
        XCTAssertLessThanOrEqual(
            WatchConnectivityProtocol.criticalThermalSpectrogramSendInterval,
            WatchConnectivityProtocol.maximumLiveDataAgeSeconds
        )
    }

    // MARK: - Edge Cases

    /// Testet Deserialisierung mit ungültigen Daten
    func testInvalidDataDeserialization() {
        let invalidData = Data([0x00, 0x01, 0x02]) // Zu kurz

        let spectrogramResult = SpectrogramData.fromBinaryData(invalidData)
        XCTAssertNil(spectrogramResult, "Invalid data should return nil for SpectrogramData")

    }

    /// Testet Deserialisierung mit leeren Daten
    func testEmptyDataDeserialization() {
        let emptyData = Data()

        let spectrogramResult = SpectrogramData.fromBinaryData(emptyData)
        XCTAssertNil(spectrogramResult, "Empty data should return nil for SpectrogramData")

    }

    /// Testet NaN und Inf Handling
    func testSpecialFloatValues() {
        // SpectrogramData mit NaN/Inf sollte trotzdem serialisierbar sein
        let frequencies: [Float] = [100, Float.nan, 300]
        let magnitudes: [Float] = [50, Float.infinity, 70]

        let original = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 60.0,
            sampleRate: 44100.0
        )

        let binaryData = original.toBinaryData()

        // Sollte nicht abstürzen, aber Werte können verändert sein
        XCTAssertGreaterThan(binaryData.count, 0, "Should serialize even with special float values")
    }

    // MARK: - Performance Tests

    /// Misst Serialisierung Performance
    func testSpectrogramSerializationPerformance() {
        let frequencies = (0..<4096).map { Float($0) * 10.0 }
        let magnitudes = (0..<4096).map { Float($0 % 100) }

        let data = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 75.0,
            sampleRate: 44100.0
        )

        measure {
            for _ in 0..<100 {
                _ = data.toBinaryData()
            }
        }
    }

    /// Misst Deserialisierung Performance
    func testSpectrogramDeserializationPerformance() {
        let frequencies = (0..<4096).map { Float($0) * 10.0 }
        let magnitudes = (0..<4096).map { Float($0 % 100) }

        let data = SpectrogramData(
            frequencies: frequencies,
            magnitudes: magnitudes,
            broadbandLevel: 75.0,
            sampleRate: 44100.0
        )

        let binaryData = data.toBinaryData()

        measure {
            for _ in 0..<100 {
                _ = SpectrogramData.fromBinaryData(binaryData)
            }
        }
    }

    // MARK: - Message Queue Simulation Tests

    /// Simuliert Message Queue Verhalten
    func testMessageQueueSimulation() {
        var queue: [[String: Any]] = []
        let maxRetries = 3

        // Füge Nachrichten hinzu
        queue.append(["type": "gain", "value": 1.5])
        queue.append(["type": "microphoneSource", "source": "Watch"])
        queue.append(["type": "startRecording"])

        XCTAssertEqual(queue.count, 3, "Queue should have 3 messages")

        // Simuliere erfolgreiche Zustellung
        queue.removeFirst()
        XCTAssertEqual(queue.count, 2, "Queue should have 2 messages after delivery")

        // Simuliere Retry
        var retries = 0
        while retries < maxRetries && !queue.isEmpty {
            retries += 1
        }
        XCTAssertEqual(retries, maxRetries, "Should retry max times")
    }
}
