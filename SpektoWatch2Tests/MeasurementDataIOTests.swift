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
}
