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

    /// AS-1: called on the main queue when the capture graph's I/O
    /// configuration changed (route change, sample-rate change, interruption
    /// side effects). The engine has already stopped when this fires.
    var onConfigurationChange: (() -> Void)?

    /// Created on first capture start so `AudioEngine` init stays off the hot
    /// AVAudioEngine graph-build path during deferred `AppServices.startAudio()`.
    private lazy var engine: AVAudioEngine = makeEngine()
    private var configurationObserver: NSObjectProtocol?

    /// AS-1/AS-3: the session category is owned by the coordinator; capture
    /// holds a `.capture` lease between configure and stop.
    private let coordinator: AudioSessionCoordinator
    private let leaseLock = NSLock()
    private var captureLease: AudioSessionCoordinator.Lease?

    init(
        tapBlockSize: AVAudioFrameCount,
        nominalSampleRate: Double,
        coordinator: AudioSessionCoordinator = .shared
    ) {
        self.tapBlockSize = tapBlockSize
        self.nominalSampleRate = nominalSampleRate
        self.coordinator = coordinator
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    private func makeEngine() -> AVAudioEngine {
        let newEngine = AVAudioEngine()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: .main
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
        return newEngine
    }

    /// `true` while the capture graph is running.
    var isRunning: Bool { engine.isRunning }

    /// AS-1: media services were reset — every AVFoundation object is invalid.
    /// Drops the old graph; the next `installTapAndStart` builds a new one.
    func resetEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = makeEngine()
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // AS-3: prewarm must not change category/activation behind the
            // coordinator's back (it used to kill a playing tone).
            do {
                let rate = max(1.0, self.nominalSampleRate)
                try audioSession.setPreferredIOBufferDuration(Double(self.tapBlockSize) / rate)
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

        // Category/mode/activation via the coordinator lease (merged with any
        // tone / playback lease instead of overwriting it).
        leaseLock.lock()
        let hasLease = captureLease != nil
        leaseLock.unlock()
        if !hasLease {
            let lease = try coordinator.acquire(.capture)
            leaseLock.lock()
            captureLease = lease
            leaseLock.unlock()
        }
        let rate = max(1.0, nominalSampleRate)
        try audioSession.setPreferredIOBufferDuration(Double(tapBlockSize) / rate)

        if audioSession.isInputGainSettable {
            try audioSession.setInputGain(1.0)
        }

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

    /// Stops the engine, removes the input tap and ends the capture lease.
    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        releaseLease()
    }

    /// AS-1: reinstalls the tap and restarts after an interruption or a
    /// configuration change, keeping the capture lease. Returns the format
    /// now delivered by the input node.
    @discardableResult
    func restart() throws -> AVAudioFormat {
        try coordinator.reapply()
        engine.stop()
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "AudioCaptureSession", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Kein gültiges Eingangsformat nach Neustart"])
        }
        try installTapAndStart(format: format)
        return format
    }

    private func releaseLease() {
        leaseLock.lock()
        let lease = captureLease
        captureLease = nil
        leaseLock.unlock()
        if let lease { coordinator.release(lease) }
    }
}
