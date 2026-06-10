import Foundation
import AVFoundation
import OSLog

/// Owns the `AVAudioEngine` capture graph, the capture-time `AVAudioSession`
/// configuration (category/mode, IO buffer duration, preferred input, stereo
/// polar pattern), the input tap, and graph/session prewarming.
///
/// Delivers raw capture buffers to its owner through `onBuffer`, which is
/// invoked from the input tap **on the audio render thread** — there is
/// deliberately no Combine/`@Published` in this hot path.
///
/// Extracted from `AudioEngine` in VERBESSERUNGSPLAN Phase 3, Task 3.2. All
/// moved logic is verbatim; `AudioEngine` keeps the start/stop orchestration,
/// permission flow, lifecycle state, writers, and the processing pipeline.
final class AudioCaptureSession {
    /// Frames per tap callback. Drives the preferred IO buffer duration and the
    /// installed tap's buffer size.
    let tapBlockSize: AVAudioFrameCount
    /// Nominal hardware sample rate used to derive the preferred IO buffer
    /// duration during session/graph prewarm.
    let nominalSampleRate: Double

    /// Called from the input tap on the audio render thread with each captured
    /// buffer. Set by the owner before the first `installTapAndStart`.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Created on first capture start so `AudioEngine` init stays off the hot
    /// AVAudioEngine graph-build path during deferred `AppServices.startAudio()`.
    private lazy var engine = AVAudioEngine()

    init(tapBlockSize: AVAudioFrameCount, nominalSampleRate: Double) {
        self.tapBlockSize = tapBlockSize
        self.nominalSampleRate = nominalSampleRate
    }

    /// Warms the lazy `AVAudioEngine` so the first capture start does less
    /// main-thread work.
    func prewarmGraph() {
        #if DEBUG
        if UITestRuntime.useTestAudio { return }
        #endif
        #if targetEnvironment(simulator)
        return
        #endif
        let signpostID = PerformanceSignpost.begin("AudioCapturePrewarm")
        _ = engine.inputNode
        engine.prepare()
        PerformanceSignpost.end("AudioCapturePrewarm", signpostID: signpostID)
    }

    /// Pre-warms the `AVAudioSession` to reduce capture start latency.
    func prewarmSession() {
        #if DEBUG
        if UITestRuntime.useTestAudio { return }
        #endif
        let audioSession = AVAudioSession.sharedInstance()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try audioSession.setCategory(.record, mode: .measurement, options: [])
                try audioSession.setPreferredIOBufferDuration(Double(self.tapBlockSize) / self.nominalSampleRate)
                try audioSession.setActive(true)
            } catch {
                Logger.audioEngine.warning("Prewarm failed: \(error.localizedDescription)")
            }
        }
    }

    /// The current input node output format. Used by the owner to create the
    /// recording file writer and to validate the hardware format.
    func inputFormat() -> AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    /// Configures the shared `AVAudioSession` for measurement capture and
    /// applies the requested stereo polar pattern. Returns the built-in mic's
    /// data sources. Throws on any session-configuration failure. Intended to
    /// run on a background queue (it performs blocking session operations).
    func configureCaptureSession(
        stereoMode: StereoInputMode,
        selectedDataSource: AVAudioSessionDataSourceDescription?
    ) throws -> [AVAudioSessionDataSourceDescription] {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(.record, mode: .measurement, options: [])
        try audioSession.setPreferredIOBufferDuration(Double(tapBlockSize) / nominalSampleRate)

        if audioSession.isInputGainSettable {
            try audioSession.setInputGain(1.0)
        }

        try audioSession.setActive(true)

        var dataSources: [AVAudioSessionDataSourceDescription] = []
        if let inputs = audioSession.availableInputs,
           let builtInMic = inputs.first(where: { $0.portType == .builtInMic }) {
            try audioSession.setPreferredInput(builtInMic)
            dataSources = builtInMic.dataSources ?? []

            // Apply stereo polar pattern BEFORE reading inputNode.outputFormat.
            // The format is only 2-channel if the pattern is set beforehand.
            let targetOrientation: AVAudioSession.Orientation
            switch stereoMode {
            case .frontBottom: targetOrientation = .front
            case .bottomBack:  targetOrientation = .back
            case .frontBack:   targetOrientation = .bottom
            }
            if let stereoSource = dataSources.first(where: { $0.orientation == targetOrientation }),
               stereoSource.supportedPolarPatterns?.contains(.stereo) == true {
                try stereoSource.setPreferredPolarPattern(.stereo)
                try audioSession.setInputDataSource(stereoSource)
                Logger.audioEngine.info("Stereo mic configured: orientation=\(String(describing: targetOrientation))")
            } else if let source = selectedDataSource {
                // Fallback: use the previously selected source
                try audioSession.setInputDataSource(source)
            }
        }
        return dataSources
    }

    /// Installs the input tap (forwarding buffers to `onBuffer`) and starts the
    /// engine. Must run on the main thread (AVAudioEngine requirement). Throws
    /// if the engine fails to start.
    func installTapAndStart(format: AVAudioFormat) throws {
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: tapBlockSize, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }
        try engine.start()
    }

    /// Stops the engine and removes the input tap.
    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}
