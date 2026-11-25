import AVFoundation
import XCTest
@testable import SpektoWatch2

final class AudioEditorTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioEditorTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Helpers

    private func makeSineWAV(
        name: String = "input.wav",
        duration: TimeInterval,
        sampleRate: Double = 44100,
        channels: Int = 1,
        frequencies: [(hz: Double, amp: Double)] = [(440, 0.5)]
    ) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        if let data = buffer.floatChannelData {
            for i in 0..<Int(frameCount) {
                let t = Double(i) / sampleRate
                var sample = 0.0
                for f in frequencies {
                    sample += f.amp * sin(2.0 * .pi * f.hz * t)
                }
                let val = Float(max(-0.98, min(0.98, sample)))
                for ch in 0..<channels {
                    data[ch][i] = val
                }
            }
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        return url
    }

    private func goertzelMagnitude(url: URL, targetHz: Double) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let count = AVAudioFrameCount(min(file.length, 44100))
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        try file.read(into: buf, frameCount: count)
        let n = Int(buf.frameLength)
        guard n > 0, let ptr = buf.floatChannelData?[0] else { return 0 }

        let k = (Double(n) * targetHz) / format.sampleRate
        let omega = (2.0 * .pi * k) / Double(n)
        let coeff = 2.0 * cos(omega)
        var q1 = 0.0
        var q2 = 0.0
        for i in 0..<n {
            let q0 = coeff * q1 - q2 + Double(ptr[i])
            q2 = q1
            q1 = q0
        }
        return sqrt(max(0, q1 * q1 + q2 * q2 - q1 * q2 * coeff)) / Double(n)
    }

    // MARK: - Edit Recipe & History Tests

    func testTrimAndChainedCutUpdateDurationAndTimeMapping() {
        var history = AudioEditHistory(sourceDuration: 10.0)
        XCTAssertEqual(history.current.effectiveDuration, 10.0, accuracy: 0.001)
        XCTAssertFalse(history.canUndo)

        // Trim to [2.0, 8.0] -> 6.0s
        let trimmed = history.current.applyingTrim(editedStart: 2.0, editedEnd: 8.0)
        history.apply(trimmed)
        XCTAssertEqual(history.current.effectiveDuration, 6.0, accuracy: 0.001)
        XCTAssertEqual(history.current.sourceTime(forEditedTime: 1.0), 3.0, accuracy: 0.001)
        XCTAssertTrue(history.canUndo)

        // Cut interior [2.0, 4.0] (which is source [4.0, 6.0]) -> 4.0s remaining
        let cut = history.current.applyingCut(editedStart: 2.0, editedEnd: 4.0)
        history.apply(cut)
        XCTAssertEqual(history.current.effectiveDuration, 4.0, accuracy: 0.001)
        XCTAssertEqual(history.current.keptRanges.count, 2)
        XCTAssertEqual(history.current.sourceTime(forEditedTime: 2.5), 6.5, accuracy: 0.001)

        // Undo & Redo
        XCTAssertTrue(history.undo())
        XCTAssertEqual(history.current.effectiveDuration, 6.0, accuracy: 0.001)
        XCTAssertTrue(history.redo())
        XCTAssertEqual(history.current.effectiveDuration, 4.0, accuracy: 0.001)
    }

    // MARK: - Waveform Analyzer Tests

    func testWaveformAnalyzerExtractsExpectedPeakBins() async throws {
        let wavURL = try makeSineWAV(duration: 1.0, frequencies: [(440, 0.5)])
        let data = try await WaveformAnalyzer.shared.extractWaveform(url: wavURL, targetBins: 100)

        XCTAssertEqual(data.bins.count, 100)
        XCTAssertEqual(data.duration, 1.0, accuracy: 0.02)
        let avgPeak = data.bins.map { max(abs($0.min), abs($0.max)) }.reduce(0, +) / Float(data.bins.count)
        XCTAssertGreaterThan(avgPeak, 0.40)
        XCTAssertLessThan(avgPeak, 0.55)
    }

    // MARK: - Offline Renderer Tests

    func testOfflineRendererTrimCutAndHighPassAttenuation() async throws {
        let wavURL = try makeSineWAV(duration: 2.0, frequencies: [(100, 0.4), (4000, 0.4)])

        // Trim [0.25, 1.75] then cut [0.5, 1.0] -> 1.0s + HPF @ 500 Hz
        var recipe = AudioEditRecipe(sourceDuration: 2.0)
        recipe = recipe.applyingTrim(editedStart: 0.25, editedEnd: 1.75)
        recipe = recipe.applyingCut(editedStart: 0.5, editedEnd: 1.0)
        recipe.filters.highPassEnabled = true
        recipe.filters.highPassCutoffHz = 500

        let renderedURL = try await AudioEditRenderer.renderToTemporaryWAV(sourceURL: wavURL, recipe: recipe)
        defer { try? FileManager.default.removeItem(at: renderedURL) }

        let outFile = try AVAudioFile(forReading: renderedURL)
        let outDuration = Double(outFile.length) / outFile.processingFormat.sampleRate
        XCTAssertEqual(outDuration, 1.0, accuracy: 0.05)

        let mag100 = try goertzelMagnitude(url: renderedURL, targetHz: 100)
        let mag4000 = try goertzelMagnitude(url: renderedURL, targetHz: 4000)
        XCTAssertGreaterThan(mag4000, mag100 * 5.0, "500 Hz HPF should strongly attenuate 100 Hz relative to 4000 Hz")
    }

    // MARK: - Format Conversion & MP3 Encoder Tests

    func testConvertWAVToAllSupportedFormatsIncludingMP3() async throws {
        let srcURL = try makeSineWAV(name: "stereo_src.wav", duration: 1.0, sampleRate: 44100, channels: 2, frequencies: [(440, 0.4)])

        let formats: [AudioExportFormat] = [.wav, .aiff, .caf, .m4aAAC, .alac, .mp3]
        for format in formats {
            var opts = AudioExportOptions(format: format, pcmBitDepth: 16, bitrateKbps: 192, title: "Test Export")
            if format == .wav { opts.pcmBitDepth = 24 }

            let dstURL = tempDir.appendingPathComponent("out_\(format.fileExtension)_\(UUID().uuidString).\(format.fileExtension)")
            let resultURL = try await AudioFormatConverter.convert(sourceURL: srcURL, destinationURL: dstURL, options: opts)

            XCTAssertTrue(FileManager.default.fileExists(atPath: resultURL.path), "Missing output for \(format.rawValue)")
            let attrs = try FileManager.default.attributesOfItem(atPath: resultURL.path)
            let size = (attrs[.size] as? Int64) ?? 0
            XCTAssertGreaterThan(size, 1024, "Output too small for \(format.rawValue)")

            let readBack = try AVAudioFile(forReading: resultURL)
            let readDur = Double(readBack.length) / max(1, readBack.processingFormat.sampleRate)
            XCTAssertEqual(readDur, 1.0, accuracy: 0.15, "Unexpected duration for \(format.rawValue)")
        }
    }
}
