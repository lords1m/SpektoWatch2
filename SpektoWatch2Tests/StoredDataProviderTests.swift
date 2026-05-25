import XCTest
@testable import SpektoWatch2

final class StoredDataProviderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoredDataProviderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
    }

    func testBootstrapEagerlyLoadsLevelHistoryAndMetricRows() throws {
        let fileURL = try createMeasurementFile(frameCount: 100, fftBinCount: 512)

        let provider = try StoredDataProvider(fileURL: fileURL)

        XCTAssertEqual(provider.levelHistory.count, 100)
        XCTAssertEqual(provider.metricRows.count, 100)
        XCTAssertEqual(provider.frameCount, 100)
        XCTAssertEqual(provider.fftBinCount, 512)
        XCTAssertTrue(provider.hasFullFFT)
    }

    func testBootstrapLazyFFTForZeroBinCount() throws {
        let fileURL = try createMeasurementFile(frameCount: 10, fftBinCount: 0)

        let provider = try StoredDataProvider(fileURL: fileURL)

        XCTAssertEqual(provider.fftBinCount, 0)
        XCTAssertFalse(provider.hasFullFFT,
                       "Provider must not advertise FFT data when fftBinCount is 0")
    }

    func testSpectrogramFramesReadsRequestedWindowFromDisk() async throws {
        let fileURL = try createMeasurementFile(frameCount: 10, fftBinCount: 16)
        let provider = try StoredDataProvider(fileURL: fileURL)

        let window = try await provider.spectrogramFrames(in: 2..<5)

        XCTAssertEqual(window.startFrame, 2)
        XCTAssertEqual(window.frameCount, 3)
        XCTAssertEqual(window.bins.count, 3)
        XCTAssertEqual(window.bins[0].first, 2)
        XCTAssertEqual(window.bins[1].first, 3)
        XCTAssertEqual(window.bins[2].first, 4)
    }

    func testSpectrogramOverviewSamplesLongRecordingInsteadOfLoadingEveryFrame() async throws {
        let fileURL = try createMeasurementFile(frameCount: 50, fftBinCount: 32)
        let provider = try StoredDataProvider(fileURL: fileURL)

        let overview = try await provider.spectrogramOverview(maxFrameCount: 5)

        XCTAssertEqual(overview.frameCount, 5)
        XCTAssertEqual(overview.bins.count, 5)
        XCTAssertEqual(overview.bins.first?.first, 0)
        XCTAssertEqual(overview.bins.last?.first, 49)
    }

    func testSpectrogramWindowCancellationThrowsQuickly() async throws {
        let fileURL = try createMeasurementFile(frameCount: 10_000, fftBinCount: 128)
        let provider = try StoredDataProvider(fileURL: fileURL)

        let task = Task.detached {
            try await provider.spectrogramFrames(in: 0..<10_000)
        }

        let start = Date()
        task.cancel()
        await Task.yield()

        do {
            _ = try await task.value
            XCTFail("Spectrogram window read should throw CancellationError after cancellation.")
        } catch is CancellationError {
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func createMeasurementFile(frameCount: Int, fftBinCount: Int) throws -> URL {
        let tempURL = tempDirectory.appendingPathComponent("measurement_\(UUID().uuidString).spekto")
        let writer = try MeasurementDataWriter(
            fileURL: tempURL,
            metricKeys: ["LAF", "LAeq", "LCpeak"],
            sampleRate: 48_000,
            fps: 25,
            fftBlockSize: max(2, fftBinCount * 2),
            fftBinCount: fftBinCount,
            maxPendingFrames: max(32, frameCount + 1)
        )

        let thirdOctaves = Array(repeating: Float(42), count: MeasurementDataFormat.thirdOctaveBandCount)
        for index in 0..<frameCount {
            let fullFFT = Array(repeating: Float(index), count: fftBinCount)
            try writer.writeFrame(
                timestamp: Float(index) / 25.0,
                metricValues: [50.0 + Float(index), 48.0, 72.0],
                broadbandLevel: 60.0 + Float(index),
                thirdOctaveZ: thirdOctaves,
                thirdOctaveA: thirdOctaves,
                thirdOctaveC: thirdOctaves,
                fullFFT: fullFFT
            )
        }

        try writer.close()
        return tempURL
    }
}
