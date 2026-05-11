import XCTest
@testable import SpektoWatch2

final class MeasurementDataIOTests: XCTestCase {
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
}
