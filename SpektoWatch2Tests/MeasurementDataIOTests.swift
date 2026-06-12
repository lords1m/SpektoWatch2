import XCTest
@testable import SpektoWatch2

final class MeasurementDataIOTests: XCTestCase {
    func testDefaultWriterUsesV3Format() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_default_v3.spekto")
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAF"],
            sampleRate: 44_100,
            fps: 86.0,
            fftBlockSize: 4096,
            fftBinCount: 0
        )
        let bands = Array(repeating: Float(42), count: MeasurementDataFormat.thirdOctaveBandCount)
        try writer.writeFrame(
            timestamp: 0,
            metricValues: [50],
            broadbandLevel: 50,
            thirdOctaveZ: bands,
            thirdOctaveA: bands,
            thirdOctaveC: bands,
            fullFFT: []
        )
        try writer.close()

        let reader = try MeasurementDataReader(fileURL: tempURL)
        XCTAssertEqual(reader.header.version, MeasurementDataFormat.version3)
    }

    func testWriterAndReaderRoundtrip() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_test.spekto")
        try? FileManager.default.removeItem(at: tempURL)

        let metrics = ["LAF", "LAeq", "LCpeak"]
        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: metrics,
            sampleRate: 48_000,
            fps: 93.75,
            fftBlockSize: 4096,
            fftBinCount: 2048
        )

        let z = Array(repeating: Float(10), count: MeasurementDataFormat.thirdOctaveBandCount)
        let a = Array(repeating: Float(20), count: MeasurementDataFormat.thirdOctaveBandCount)
        let c = Array(repeating: Float(30), count: MeasurementDataFormat.thirdOctaveBandCount)
        let fullFFT = Array(repeating: Float(-80), count: 2048)

        try writer.writeFrame(
            timestamp: 0.0,
            metricValues: [51.2, 48.1, 72.6],
            broadbandLevel: 50.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: fullFFT
        )
        try writer.writeFrame(
            timestamp: 0.5,
            metricValues: [52.0, 48.4, 73.2],
            broadbandLevel: 50.8,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: fullFFT
        )
        try writer.close()

        let reader = try MeasurementDataReader(fileURL: tempURL)
        XCTAssertEqual(reader.frameCount, 2)
        XCTAssertEqual(reader.header.metricKeys, metrics)
        XCTAssertEqual(reader.header.fftBlockSize, 4096)

        let first = try reader.readFrame(at: 0)
        XCTAssertEqual(first.timestamp, 0.0, accuracy: 0.0001)
        XCTAssertEqual(first.metrics[0], 51.2, accuracy: 0.001)
        XCTAssertEqual(first.broadbandLevel, 50.0, accuracy: 0.001)
        XCTAssertEqual(first.thirdOctaveZ.count, MeasurementDataFormat.thirdOctaveBandCount)
        XCTAssertEqual(first.fullFFT.count, 2048)
    }

    func testWriterDropsExplicitlyWhenBackpressureCapacityIsZero() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_backpressure_test.spekto")
        try? FileManager.default.removeItem(at: tempURL)

        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAF"],
            sampleRate: 44_100,
            fps: 86.0,
            fftBlockSize: 4096,
            fftBinCount: 0,
            maxPendingFrames: 0
        )

        let bands = Array(repeating: Float(42), count: MeasurementDataFormat.thirdOctaveBandCount)
        try writer.writeFrame(
            timestamp: 0.0,
            metricValues: [50.0],
            broadbandLevel: 50.0,
            thirdOctaveZ: bands,
            thirdOctaveA: bands,
            thirdOctaveC: bands,
            fullFFT: []
        )
        try writer.close()

        XCTAssertEqual(writer.droppedFrameCount, 1)

        let reader = try MeasurementDataReader(fileURL: tempURL)
        XCTAssertEqual(reader.frameCount, 0)
        XCTAssertFalse(reader.header.hasFullFFT)
    }

    func testReaderPreservesLegacyVersionOneSpektoFiles() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_legacy_v1_test.spekto")
        try? FileManager.default.removeItem(at: tempURL)

        var data = Data()
        let metricKeys = ["LAF", "LAeq"]
        let z = Array(repeating: Float(11), count: MeasurementDataFormat.thirdOctaveBandCount)
        let a = Array(repeating: Float(22), count: MeasurementDataFormat.thirdOctaveBandCount)
        let c = Array(repeating: Float(33), count: MeasurementDataFormat.thirdOctaveBandCount)

        data.appendUInt32LE(MeasurementDataFormat.magic)
        data.appendUInt16LE(1)
        data.appendUInt16LE(0)
        data.appendUInt64LE(1)
        data.appendDoubleLE(44_100)
        data.appendFloatLE(86.0)
        data.appendUInt32LE(4096)
        data.appendUInt16LE(UInt16(metricKeys.count))
        data.appendUInt16LE(0)
        for key in metricKeys {
            let keyData = try XCTUnwrap(key.data(using: .utf8))
            data.appendUInt16LE(UInt16(keyData.count))
            data.append(keyData)
        }

        data.appendFloatLE(0.25)
        data.appendFloatLE(54.0)
        data.appendFloatLE(51.0)
        data.appendFloatLE(53.0)
        for value in z { data.appendFloatLE(value) }
        for value in a { data.appendFloatLE(value) }
        for value in c { data.appendFloatLE(value) }

        try data.write(to: tempURL)

        let reader = try MeasurementDataReader(fileURL: tempURL)
        XCTAssertEqual(reader.header.version, 1)
        XCTAssertEqual(reader.frameCount, 1)
        XCTAssertEqual(reader.header.metricKeys, metricKeys)
        XCTAssertFalse(reader.header.hasFullFFT)
        XCTAssertEqual(reader.header.fftBinCount, 0)

        let frame = try reader.readFrame(at: 0)
        XCTAssertEqual(frame.timestamp, 0.25, accuracy: 0.0001)
        XCTAssertEqual(frame.metrics, [54.0, 51.0])
        XCTAssertEqual(frame.broadbandLevel, 53.0, accuracy: 0.001)
        XCTAssertEqual(frame.thirdOctaveZ, z)
        XCTAssertEqual(frame.thirdOctaveA, a)
        XCTAssertEqual(frame.thirdOctaveC, c)
        XCTAssertTrue(frame.fullFFT.isEmpty)
    }

    // MARK: - v3 format (Phase 7)

    private func sampleBands() -> ([Float], [Float], [Float]) {
        let z = Array(repeating: Float(10), count: MeasurementDataFormat.thirdOctaveBandCount)
        let a = Array(repeating: Float(20), count: MeasurementDataFormat.thirdOctaveBandCount)
        let c = Array(repeating: Float(30), count: MeasurementDataFormat.thirdOctaveBandCount)
        return (z, a, c)
    }

    func testV3WriterReaderRoundTrip() throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_v3_test.spekto")
        try? FileManager.default.removeItem(at: tempURL)

        let metrics = ["LAF", "LAeq"]
        let calibration = MeasurementCalibrationMetadata(
            microphoneSource: "appleWatch",
            gain: 1.5,
            calibrationOffset: -2.0,
            deviceModel: "iPhone Test",
            frequencyWeighting: "A"
        )
        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: metrics,
            sampleRate: 48_000,
            fps: 93.75,
            fftBlockSize: 4096,
            fftBinCount: 0,
            fileFormatVersion: MeasurementDataFormat.version3,
            calibration: calibration
        )

        let (z, a, c) = sampleBands()
        try writer.writeFrame(
            timestamp: 0.0,
            metricValues: [51.2, 48.1],
            broadbandLevel: 50.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.writeFrame(
            timestamp: 0.5,
            metricValues: [52.0, 48.4],
            broadbandLevel: 50.8,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.close()

        let reader = try MeasurementDataReader(fileURL: tempURL)
        XCTAssertEqual(reader.header.version, MeasurementDataFormat.version3)
        XCTAssertNotEqual(reader.header.headerCRC32, 0)
        XCTAssertTrue(reader.header.hasSeekIndex)
        XCTAssertGreaterThan(reader.header.seekIndexOffset, 0)
        XCTAssertEqual(reader.header.calibration, calibration)
        XCTAssertEqual(reader.frameCount, 2)

        let second = try reader.readFrame(at: 1)
        XCTAssertEqual(second.timestamp, 0.5, accuracy: 0.0001)
        XCTAssertEqual(second.metrics[1], 48.4, accuracy: 0.001)
    }

    func testV2AndV3FrameParity() throws {
        let metrics = ["LAF", "LAeq", "LCpeak"]
        let (z, a, c) = sampleBands()
        let fullFFT = Array(repeating: Float(-80), count: 128)

        let v2URL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_v2_parity.spekto")
        let v3URL = FileManager.default.temporaryDirectory.appendingPathComponent("measurement_io_v3_parity.spekto")
        try? FileManager.default.removeItem(at: v2URL)
        try? FileManager.default.removeItem(at: v3URL)

        func writeFrames(to url: URL, version: UInt16) throws {
            let writer = try MeasurementDataWriter(
                fileURL: url,
                metricKeys: metrics,
                sampleRate: 48_000,
                fps: 93.75,
                fftBlockSize: 4096,
                fftBinCount: 128,
                fileFormatVersion: version
            )
            try writer.writeFrame(
                timestamp: 0.0,
                metricValues: [51.2, 48.1, 72.6],
                broadbandLevel: 50.0,
                thirdOctaveZ: z,
                thirdOctaveA: a,
                thirdOctaveC: c,
                fullFFT: fullFFT
            )
            try writer.writeFrame(
                timestamp: 0.5,
                metricValues: [52.0, 48.4, 73.2],
                broadbandLevel: 50.8,
                thirdOctaveZ: z,
                thirdOctaveA: a,
                thirdOctaveC: c,
                fullFFT: fullFFT
            )
            try writer.close()
        }

        try writeFrames(to: v2URL, version: MeasurementDataFormat.version2)
        try writeFrames(to: v3URL, version: MeasurementDataFormat.version3)

        let v2Reader = try MeasurementDataReader(fileURL: v2URL)
        let v3Reader = try MeasurementDataReader(fileURL: v3URL)

        for index in 0..<2 {
            let v2Frame = try v2Reader.readFrame(at: index)
            let v3Frame = try v3Reader.readFrame(at: index)
            XCTAssertEqual(v3Frame.timestamp, v2Frame.timestamp, accuracy: 0.0001)
            XCTAssertEqual(v3Frame.metrics, v2Frame.metrics)
            XCTAssertEqual(v3Frame.broadbandLevel, v2Frame.broadbandLevel, accuracy: 0.001)
            XCTAssertEqual(v3Frame.thirdOctaveZ, v2Frame.thirdOctaveZ)
            XCTAssertEqual(v3Frame.thirdOctaveA, v2Frame.thirdOctaveA)
            XCTAssertEqual(v3Frame.thirdOctaveC, v2Frame.thirdOctaveC)
            XCTAssertEqual(v3Frame.fullFFT, v2Frame.fullFFT)
        }
    }

    func testV2GoldenFixtureRemainsReadable() throws {
        let fixtureURL = try writeV2GoldenFixture()
        let reader = try MeasurementDataReader(fileURL: fixtureURL)
        XCTAssertEqual(reader.header.version, MeasurementDataFormat.version2)
        XCTAssertEqual(reader.frameCount, 2)
        XCTAssertEqual(reader.header.metricKeys, ["LAF", "LAeq"])
        XCTAssertEqual(reader.header.headerCRC32, 0)
        XCTAssertEqual(reader.header.seekIndexOffset, 0)
        XCTAssertNil(reader.header.calibration)

        let frame = try reader.readFrame(at: 0)
        XCTAssertEqual(frame.timestamp, 0.25, accuracy: 0.0001)
        XCTAssertEqual(frame.metrics, [54.0, 51.0])
    }

    func testV3GoldenFixtureRemainsReadable() throws {
        let fixtureURL = try writeV3GoldenFixture()
        let reader = try MeasurementDataReader(fileURL: fixtureURL)
        XCTAssertEqual(reader.header.version, MeasurementDataFormat.version3)
        XCTAssertNotEqual(reader.header.headerCRC32, 0)
        XCTAssertTrue(reader.header.hasSeekIndex)
        XCTAssertEqual(reader.frameCount, 2)

        let frame = try reader.readFrame(at: 1)
        XCTAssertEqual(frame.timestamp, 0.75, accuracy: 0.0001)
        XCTAssertEqual(frame.metrics, [55.0, 52.0])
    }

    private func writeV3GoldenFixture() throws -> URL {
        let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
        let fixtureURL = fixturesDirectory.appendingPathComponent("measurement_v3_golden.spekto")

        if FileManager.default.fileExists(atPath: fixtureURL.path) {
            return fixtureURL
        }

        let metrics = ["LAF", "LAeq"]
        let writer = try MeasurementDataWriter(
            fileURL: fixtureURL,
            metricKeys: metrics,
            sampleRate: 44_100,
            fps: 86.0,
            fftBlockSize: 4096,
            fftBinCount: 0,
            fileFormatVersion: MeasurementDataFormat.version3,
            calibration: MeasurementCalibrationMetadata(
                microphoneSource: "builtInMic",
                gain: 0,
                calibrationOffset: -1.5,
                deviceModel: "GoldenFixture",
                frequencyWeighting: "A"
            )
        )
        let (z, a, c) = sampleBands()
        try writer.writeFrame(
            timestamp: 0.25,
            metricValues: [54.0, 51.0],
            broadbandLevel: 53.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.writeFrame(
            timestamp: 0.75,
            metricValues: [55.0, 52.0],
            broadbandLevel: 54.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.close()
        return fixtureURL
    }

    private func writeV2GoldenFixture() throws -> URL {
        let fixturesDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.createDirectory(at: fixturesDirectory, withIntermediateDirectories: true)
        let fixtureURL = fixturesDirectory.appendingPathComponent("measurement_v2_golden.spekto")

        if FileManager.default.fileExists(atPath: fixtureURL.path) {
            return fixtureURL
        }

        let metrics = ["LAF", "LAeq"]
        let writer = try MeasurementDataWriter(
            fileURL: fixtureURL,
            metricKeys: metrics,
            sampleRate: 44_100,
            fps: 86.0,
            fftBlockSize: 4096,
            fftBinCount: 0,
            fileFormatVersion: MeasurementDataFormat.version2
        )
        let (z, a, c) = sampleBands()
        try writer.writeFrame(
            timestamp: 0.25,
            metricValues: [54.0, 51.0],
            broadbandLevel: 53.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.writeFrame(
            timestamp: 0.75,
            metricValues: [55.0, 52.0],
            broadbandLevel: 54.0,
            thirdOctaveZ: z,
            thirdOctaveA: a,
            thirdOctaveC: c,
            fullFFT: []
        )
        try writer.close()
        return fixtureURL
    }
}
