#if canImport(UIKit)
import XCTest
@testable import SpektoWatch2
import AVFoundation

final class SpectrogramImageExporterTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpectrogramExporterTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    // MARK: - SpectrogramImageRenderer

    func testRendererOutputDimensions() throws {
        // 8 s at 44100 Hz yields ~780 columns (hop=512), enough to fill 600 px without clamping.
        let audioURL = try makeSyntheticAudioFile(durationSeconds: 8.0, sampleRate: 44100)
        let renderer = SpectrogramImageRenderer()
        let targetWidth = 600
        let targetHeight = 200
        let image = try renderer.renderSpectrogramImage(
            audioURL: audioURL,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        XCTAssertEqual(Int(image.size.width), targetWidth)
        XCTAssertEqual(Int(image.size.height), targetHeight)
    }

    func testRendererProducesNonEmptyPixelData() throws {
        let audioURL = try makeSyntheticAudioFile(durationSeconds: 1.0, sampleRate: 44100, frequency: 1000)
        let renderer = SpectrogramImageRenderer()
        let image = try renderer.renderSpectrogramImage(
            audioURL: audioURL,
            targetWidth: 100,
            targetHeight: 100
        )
        let pngData = image.pngData()
        XCTAssertNotNil(pngData)
        XCTAssertGreaterThan(pngData!.count, 0)
    }

    func testRendererThrowsOnUnreadableFile() {
        let missing = tempDirectory.appendingPathComponent("nonexistent.caf")
        let renderer = SpectrogramImageRenderer()
        XCTAssertThrowsError(try renderer.renderSpectrogramImage(audioURL: missing))
    }

    // MARK: - SpectrogramImageExporter

    func testExportSuccessWritesPNGFile() throws {
        let audioURL = try makeSyntheticAudioFile(durationSeconds: 1.0, sampleRate: 44100)
        let exporter = SpectrogramImageExporter()
        let outputURL = try exporter.export(audioURL: audioURL, recordingID: UUID().uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertEqual(outputURL.pathExtension, "png")
        let data = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testExportSuccessFilenameContainsRecordingID() throws {
        let audioURL = try makeSyntheticAudioFile(durationSeconds: 0.5, sampleRate: 44100)
        let recordingID = UUID().uuidString
        let exporter = SpectrogramImageExporter()
        let outputURL = try exporter.export(audioURL: audioURL, recordingID: recordingID)
        XCTAssertTrue(outputURL.lastPathComponent.contains(recordingID))
    }

    func testExportFailsWhenAudioFileMissing() {
        let missing = tempDirectory.appendingPathComponent("missing.caf")
        let exporter = SpectrogramImageExporter()
        XCTAssertThrowsError(try exporter.export(audioURL: missing, recordingID: UUID().uuidString)) { error in
            guard let exportError = error as? SpectrogramImageExporter.ExportError,
                  case .audioNotFound = exportError else {
                XCTFail("Expected ExportError.audioNotFound, got \(error)")
                return
            }
        }
    }

    func testExportErrorDescriptionIsNonEmpty() {
        let missing = URL(fileURLWithPath: "/nonexistent/audio.caf")
        let error = SpectrogramImageExporter.ExportError.audioNotFound(missing)
        XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
    }

    // MARK: - Helpers

    private func makeSyntheticAudioFile(
        durationSeconds: Double,
        sampleRate: Double,
        frequency: Double = 440.0
    ) throws -> URL {
        let frameCount = AVAudioFrameCount(durationSeconds * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let amplitude: Float = 0.5
        let angularFrequency = Float(2.0 * .pi * frequency / sampleRate)
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            channel[i] = amplitude * sin(angularFrequency * Float(i))
        }

        let outputURL = tempDirectory.appendingPathComponent("\(UUID().uuidString).caf")
        let audioFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
        try audioFile.write(from: buffer)
        return outputURL
    }
}
#endif
