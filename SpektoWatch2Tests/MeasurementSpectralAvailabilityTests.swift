import XCTest
@testable import SpektoWatch2

final class MeasurementSpectralAvailabilityTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeasurementSpectralAvailabilityTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testDetectsPopulatedThirdOctaveBands() throws {
        let fileURL = try writeMeasurement(thirdOctaveLevel: 55)
        XCTAssertTrue(MeasurementSpectralAvailability.hasUsableSpectralData(fileURL: fileURL))
    }

    func testRejectsZeroFilledThirdOctaveBands() throws {
        let fileURL = try writeMeasurement(thirdOctaveLevel: 0)
        XCTAssertFalse(MeasurementSpectralAvailability.hasUsableSpectralData(fileURL: fileURL))
    }

    private func writeMeasurement(thirdOctaveLevel: Float) throws -> URL {
        let fileURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).spekto")
        let writer = try MeasurementDataWriter(
            fileURL: fileURL,
            metricKeys: ["LAF"],
            sampleRate: 48_000,
            fps: 25,
            fftBlockSize: 2048,
            fftBinCount: 0
        )
        let bands = Array(repeating: thirdOctaveLevel, count: MeasurementDataFormat.thirdOctaveBandCount)
        try writer.writeFrame(
            timestamp: 0,
            metricValues: [60],
            broadbandLevel: 60,
            thirdOctaveZ: bands,
            thirdOctaveA: bands,
            thirdOctaveC: bands,
            fullFFT: []
        )
        try writer.close()
        return fileURL
    }
}
