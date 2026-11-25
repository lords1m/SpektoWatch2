import XCTest
import AVFoundation
@testable import SpektoWatch2

/// Regression tests for M22 task-7 (rendering, UI & feature polish).
/// UI-7/UI-8/UI-9 (render cadence, gestures) and UI-2 playback timing are
/// verified on device / in Instruments (task-8).
@MainActor
final class M22UIPolishRegressionTests: XCTestCase {

    private func writeTone(seconds: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { data[i] = 0.2 * Float(sin(2 * .pi * 1_000 * Double(i) / 44_100)) }
        try file.write(from: buffer)
    }

    // MARK: - UI-1 overview column cap

    func testStreamingHistoryIsCappedToMaxColumns() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ui1-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTone(seconds: 6, to: url)

        let uncapped = try RecordingSpectrogramModel.computeHistoryStreaming(
            url: url, calibrationOffset: 94, fftBlockSize: 2048, maxColumns: .max)
        let capped = try RecordingSpectrogramModel.computeHistoryStreaming(
            url: url, calibrationOffset: 94, fftBlockSize: 2048, maxColumns: 20)

        XCTAssertGreaterThan(uncapped.count, 20)
        XCTAssertLessThanOrEqual(capped.count, 21)
        XCTAssertEqual(capped.first?.count, uncapped.first?.count)
        // Max-pooling keeps the tone's peak level.
        let peakUncapped = uncapped.flatMap { $0 }.max() ?? -200
        let peakCapped = capped.flatMap { $0 }.max() ?? -200
        XCTAssertEqual(peakCapped, peakUncapped, accuracy: 0.01)
    }

    func testDefaultCapFitsTextureLimit() {
        XCTAssertLessThan(RecordingSpectrogramModel.maxOverviewFrames, 16_384)
    }

    // MARK: - UI-16 masking preview volume

    func testLinearVolumeClamps() {
        XCTAssertEqual(MaskingPreviewPlayer.linearVolume(0), 1, accuracy: 1e-6)
        XCTAssertEqual(MaskingPreviewPlayer.linearVolume(-20), 0.1, accuracy: 1e-6)
        XCTAssertEqual(MaskingPreviewPlayer.linearVolume(12), 1, "never above unity")
    }

    // MARK: - UI-15 tone ramps (DSP shipped with task-4)

    func testRampConstantsAreShort() {
        XCTAssertGreaterThanOrEqual(ToneGenerator.rampSeconds, 0.003)
        XCTAssertLessThanOrEqual(ToneGenerator.fadeOutSeconds, 0.05)
    }

    // MARK: - UI-12 widget undo keeps its source layout

    func testWidgetUndoToastRecordsSourceLayout() {
        let widget = WidgetConfiguration(type: .levelMeter, size: WidgetSize(columns: 2, rows: 2))
        let toast = WidgetUndoToast(widget: widget, index: 0, navigation: .preset(activePresetID: "overview"))
        XCTAssertEqual(toast.navigation, .preset(activePresetID: "overview"))
        XCTAssertNotEqual(toast.navigation, .preset(activePresetID: "phase"))
    }
}
