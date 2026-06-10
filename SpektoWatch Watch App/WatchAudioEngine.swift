import Foundation
import AVFoundation
import WatchKit
import Combine
import Accelerate
import os

/// Audio-thread snapshot assembled on each FFT frame; DCT/visual work runs on
/// the main thread inside `flushPendingLiveData` (not on the render callback).
private struct PendingWatchAudioFrame {
    let magnitudesZ: [Float]
    let magnitudesA: [Float]
    let magnitudesC: [Float]
    let thirdOctaveZ: [Float]
    let thirdOctaveA: [Float]
    let thirdOctaveC: [Float]
    let bandLeqZ: [Float]
    let bandLeqA: [Float]
    let bandLeqC: [Float]
    let barkZ: [Float]
    let levels: [String: Float]
    let broadbandLevel: Float
    let sampleRate: Double
    let timestamp: Date
    let visualSamples: [Float]
}

class WatchAudioEngine: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    /// Single source of truth for what the watch is doing.
    /// Widgets observe `$liveData` instead of branching on `isRecording`.
    @Published private(set) var operatingMode: WatchOperatingMode = .companion

    /// User policy for the live measurement source (auto / iPhone / watch).
    @Published private(set) var measurementSourcePreference: WatchMeasurementSourcePreference
    /// Resolved source currently driving `liveData` (for UI indicator).
    @Published private(set) var activeMeasurementSource: WatchActiveMeasurementSource = .idle

    /// Legacy alias: `true` when live data comes from the watch mic policy.
    var standaloneEnabled: Bool { !usesPhoneAsLiveDataSource }
    /// When `true`, record start/stop is coordinated with the iPhone app.
    var coordinatesRecordingWithPhone: Bool {
        !Self.isWatchOnlyApp && measurementSourcePreference == .iPhone
    }

    private var phoneSpectrogramSubscription: AnyCancellable?
    private var connectivityCancellables = Set<AnyCancellable>()
    private static let phoneStreamFreshness: TimeInterval = 2.0
    /// True when the watch mic tap is running for live level/spectrogram preview
    /// (standalone / watch-only), without an active file recording.
    private var isLiveMonitoring = false
    private var isMicTapInstalled = false
    private var micTapFormat: AVAudioFormat?
    private var audioEngine: AVAudioEngine
    private let bufferSize: AVAudioFrameCount = 4096
    private let sampleRate: Double = 44100.0
    private var session: WKExtendedRuntimeSession?
    private let connectivityManager: WatchConnectivityManager
    private var gain: Float = 1.0

    // Lokale FFT Konfiguration (Abgespeckt für Watch)
    private let fftSize: Int = 2048
    // M15 task-3: real-optimized DFT (matches `Processing/FFTProcessor.swift`
    // on iOS). The previous `vDSP_DFT_zop_CreateSetup` setup produced a full
    // complex spectrum with `2/N` normalization — that scale is only valid
    // for `zrop` (half-spectrum), so bins were ~6 dB hot. zrop also halves
    // the buffer footprint.
    private let fftSetup: vDSP_DFT_Setup
    private var windowedSamples: [Float]      // N-length windowed real signal
    private var splitRealIn: [Float]          // N/2 — even-indexed samples
    private var splitImagIn: [Float]          // N/2 — odd-indexed samples
    private var realOut: [Float]              // N/2
    private var imagOut: [Float]              // N/2
    private var window: [Float]
    private var fftMagnitudes: [Float]
    // Linear-amplitude copy of the FFT magnitudes, captured before the dB
    // conversion in `performFFT`. Reused for weighted-energy + LCpeak math so
    // the watch produces real IEC 61672 metrics (LAeq, LCpeak) rather than a
    // broadband-as-LAeq placeholder. Preallocated — no audio-thread allocation.
    private var fftLinearMagnitudes: [Float]
    private let visualDCT: vDSP.DCT
    private var visualWindowedSamples: [Float]
    private var visualCoefficients: [Float]
    private var visualMagnitudes: [Float]
    private var displayVisualMagnitudes: [Float]
    #if DEBUG
    private var debugFrameCount = 0
    #endif
    private let watchMicCalibrationOffset: Float = 100.0

    // Real IEC 61672 metrics on the watch (M21/task-2). Shared with iOS via
    // `Shared/`. `weightingProcessor` supplies the precomputed A/C gain curves;
    // `metricsCalculator` integrates LAeq and holds LCpeak across the session.
    private let weightingProcessor: FrequencyWeightingProcessor
    private let metricsCalculator: AcousticMetricsCalculator
    private var fftEnergyScratch: [Float]
    private var lcPeakScratch: [Float]
    /// Set on the main thread at recording start; read on the audio thread to
    /// derive the running recording duration for the calculator's Taktmaximal.
    private var recordingStartDate: Date?

    /// Active durable recording (standalone only). Created before the engine
    /// starts so the first audio frames are captured; the audio thread feeds it
    /// per buffer and `stopRecording` finalizes + registers it in the catalog.
    /// `nil` in companion/wearableMic modes where the phone owns storage.
    private var activeRecordingSession: WatchRecordingSession?

    // Pre-computed once, reused per-frame: bin frequencies (constant for given fftSize/sampleRate).
    private let binFrequencies: [Float]
    private var displayVisualFrequencies: [Float]

    // Reusable scratch buffers — avoid per-callback `Array(repeating: 0, count: ...)`
    // and `Array(samples.prefix(fftSize))` allocations.
    private var monoSampleScratch: [Float] = []
    private var fftInputScratch: [Float]

    @Published var isRecording = false
    @Published var currentSpectrogramData: SpectrogramData?

    /// Unified data source for widgets. Mirrors either the local FFT result
    /// (when the watch mic is active) or the phone-pushed spectrogram (companion
    /// mode). Widgets bind to `$liveData` and don't have to care which is which.
    @Published var liveData: SpectrogramData?

    // MARK: - Live-Data Flush Coalescing
    //
    // `processAudioBuffer` previously called `DispatchQueue.main.async` once
    // per audio callback (~11 Hz at 4096 / 44100), each carrying a 1024-element
    // `[Float]` copy. On the watch's constrained main thread this was real
    // battery pressure for an indicator users glance at every few seconds.
    // Coalesce updates to ~5 Hz: store the latest data, schedule a single
    // flush, drop anything that arrives before the flush fires.
    private let liveDataLock = OSAllocatedUnfairLock()
    private var pendingAudioFrame: PendingWatchAudioFrame?
    private var isLiveDataFlushScheduled = false
    private static let liveDataFlushInterval: TimeInterval = 0.2  // 5 Hz
    private let visualDCTQueue = DispatchQueue(label: "com.spektowatch.watch-visual-dct", qos: .userInitiated)
    private var displayVisualBinCount: Int
    private(set) var spectrogramDisplayBinCount: Int
    private(set) var spectrogramHistoryFrameCount: Int

    init(connectivityManager: WatchConnectivityManager) {
        self.connectivityManager = connectivityManager
        self.measurementSourcePreference = Self.resolvedMeasurementSourcePreference()
        let resolution = SpectrogramResolution.current
        displayVisualBinCount = resolution.watchDisplayBinCount
        spectrogramDisplayBinCount = resolution.watchDisplayBinCount
        spectrogramHistoryFrameCount = resolution.watchHistoryFrameCount
        audioEngine = AVAudioEngine()
        
        // FFT Setup initialisieren
        guard let setup = vDSP_DFT_zrop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup
        guard let dct = vDSP.DCT(count: fftSize, transformType: .II) else {
            fatalError("Failed to create DCT setup")
        }
        visualDCT = dct

        windowedSamples = [Float](repeating: 0, count: fftSize)
        splitRealIn = [Float](repeating: 0, count: fftSize / 2)
        splitImagIn = [Float](repeating: 0, count: fftSize / 2)
        realOut = [Float](repeating: 0, count: fftSize / 2)
        imagOut = [Float](repeating: 0, count: fftSize / 2)
        window = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        fftLinearMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        fftEnergyScratch = [Float](repeating: 0, count: fftSize / 2)
        lcPeakScratch = [Float](repeating: 0, count: fftSize / 2)
        weightingProcessor = FrequencyWeightingProcessor(fftSize: fftSize, sampleRate: sampleRate)
        metricsCalculator = AcousticMetricsCalculator(sampleRate: sampleRate)
        visualWindowedSamples = [Float](repeating: 0, count: fftSize)
        visualCoefficients = [Float](repeating: 0, count: fftSize)
        visualMagnitudes = [Float](repeating: 0, count: fftSize)
        displayVisualMagnitudes = [Float](repeating: -180.0, count: displayVisualBinCount)
        fftInputScratch = [Float](repeating: 0, count: fftSize)

        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))

        // Bin frequencies are constant for a given fftSize/sampleRate — compute once.
        let binCount = fftSize / 2
        let binWidth = Float(sampleRate) / Float(fftSize)
        var freqs = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount { freqs[i] = Float(i) * binWidth }
        binFrequencies = freqs
        let nyquist = Float(sampleRate / 2.0)
        displayVisualFrequencies = Self.makeDisplayFrequencies(count: displayVisualBinCount, nyquist: nyquist)

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpectrogramResolutionChanged(_:)),
            name: .spectrogramResolutionChanged,
            object: nil
        )

        // Companion mode by default: forward phone spectrogram into liveData.
        // The subscription is replaced when we transition into wearableMic mode
        // so we don't pay for two streams at once.
        //
        // Phone-absent UX (M21/task-1): if the user has chosen standalone, the
        // watch is the source of truth — start in `.standalone` and do NOT
        // subscribe to the phone. Launch never blocks on or assumes a present
        // phone in this mode.
        bindConnectivityForAutoMode()
        reconcileLiveDataSource()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartRecording),
            name: .startRecordingCommand,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopRecording),
            name: .stopRecordingCommand,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGainChange),
            name: .gainOrBandwidthChangedNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMeasurementSourcePreferenceChanged),
            name: .watchMeasurementSourcePreferenceChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        vDSP_DFT_DestroySetup(fftSetup)
    }

    @objc private func handleStartRecording() {
        guard !isRecording else { return }
        startRecording()
    }

    @objc private func handleStopRecording() {
        guard isRecording else { return }
        stopRecording()
    }

    @objc private func handleGainChange(notification: Notification) {
        if let gain = notification.object as? Float {
            setGain(gain)
        }
    }

    @objc private func handleSpectrogramResolutionChanged(_ notification: Notification) {
        let resolution: SpectrogramResolution
        if let value = notification.object as? SpectrogramResolution {
            resolution = value
        } else {
            resolution = .current
        }
        applySpectrogramResolution(resolution)
    }

    private func applySpectrogramResolution(_ resolution: SpectrogramResolution) {
        displayVisualBinCount = resolution.watchDisplayBinCount
        spectrogramDisplayBinCount = resolution.watchDisplayBinCount
        spectrogramHistoryFrameCount = resolution.watchHistoryFrameCount
        displayVisualMagnitudes = [Float](repeating: -180.0, count: displayVisualBinCount)
        let nyquist = Float(sampleRate / 2.0)
        displayVisualFrequencies = Self.makeDisplayFrequencies(count: displayVisualBinCount, nyquist: nyquist)
    }

    @objc private func handleMeasurementSourcePreferenceChanged(notification: Notification) {
        let preference: WatchMeasurementSourcePreference
        if let value = notification.object as? WatchMeasurementSourcePreference {
            preference = value
        } else if let raw = UserDefaults.standard.string(forKey: PersistenceKeys.Watch.measurementSourcePreference),
                  let stored = WatchMeasurementSourcePreference(rawValue: raw) {
            preference = stored
        } else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.measurementSourcePreference != preference {
                self.measurementSourcePreference = preference
            }
            guard !self.isRecording else { return }
            self.reconcileLiveDataSource()
        }
    }

    func setGain(_ newGain: Float) {
        // Clamp the gain to a reasonable range, e.g., 0.0 to 10.0
        self.gain = max(0.0, min(newGain, 10.0))
        print("[WatchAudioEngine] Gain set to \(self.gain)")
    }

    /// Updates the measurement-source policy and re-applies live routing.
    func setMeasurementSourcePreference(_ preference: WatchMeasurementSourcePreference) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !Self.isWatchOnlyApp || preference == .appleWatch else { return }
        guard preference != measurementSourcePreference else { return }
        measurementSourcePreference = preference
        persistMeasurementSourcePreference(preference)
        guard !isRecording else { return }
        reconcileLiveDataSource()
    }

    /// Legacy toggle used by older UI paths (`true` → watch, `false` → iPhone).
    func setStandaloneEnabled(_ enabled: Bool) {
        setMeasurementSourcePreference(enabled ? .appleWatch : .iPhone)
    }

    /// Picks phone mirror vs watch mic from preference, reachability, and phone activity.
    func reconcileLiveDataSource() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRecording else {
            updateActiveMeasurementSource()
            return
        }

        if shouldMirrorPhone() {
            stopLiveMonitoring()
            if operatingMode != .companion {
                transition(to: .companion)
            } else {
                subscribeToPhoneSpectrogram()
            }
            updateActiveMeasurementSource()
        } else {
            phoneSpectrogramSubscription?.cancel()
            phoneSpectrogramSubscription = nil
            transition(to: .standalone)
            startLiveMonitoring()
            updateActiveMeasurementSource()
        }
    }

    private func bindConnectivityForAutoMode() {
        connectivityManager.$isReachable
            .combineLatest(
                connectivityManager.$phoneAppState,
                connectivityManager.$lastPhoneSpectrogramReceivedAt
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self, self.measurementSourcePreference == .auto, !self.isRecording else { return }
                self.reconcileLiveDataSource()
            }
            .store(in: &connectivityCancellables)

        connectivityManager.$spectrogramData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.measurementSourcePreference == .auto, !self.isRecording else { return }
                self.reconcileLiveDataSource()
            }
            .store(in: &connectivityCancellables)
    }

    private func shouldMirrorPhone() -> Bool {
        if Self.isWatchOnlyApp { return false }
        switch measurementSourcePreference {
        case .iPhone:
            return true
        case .appleWatch:
            return false
        case .auto:
            guard connectivityManager.isReachable else { return false }
            if connectivityManager.phoneAppState?.isRecording == true { return true }
            if let receivedAt = connectivityManager.lastPhoneSpectrogramReceivedAt,
               Date().timeIntervalSince(receivedAt) <= Self.phoneStreamFreshness {
                return true
            }
            return false
        }
    }

    private func updateActiveMeasurementSource() {
        if isRecording || isLiveMonitoring {
            activeMeasurementSource = .watchMic
        } else if usesPhoneAsLiveDataSource, liveData != nil {
            activeMeasurementSource = .iPhoneMirror
        } else if liveData != nil, operatingMode.watchMicIsActive {
            activeMeasurementSource = .watchMic
        } else {
            activeMeasurementSource = .idle
        }
    }

    private func persistMeasurementSourcePreference(_ preference: WatchMeasurementSourcePreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: PersistenceKeys.Watch.measurementSourcePreference)
        UserDefaults.standard.set(preference == .appleWatch, forKey: PersistenceKeys.Watch.standaloneEnabled)
    }

    /// Begin watch-mic live preview (levels + spectrogram) without starting a
    /// file recording. Used for watch-only / standalone operation per M21.
    func startLiveMonitoring() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !shouldMirrorPhone() else { return }
        guard !isRecording, !isLiveMonitoring else { return }
        requestMicrophoneAccess { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.main.async {
                self.beginMicCaptureOnMain(recording: false)
            }
        }
    }

    /// Stops live preview and releases the mic when idle (not recording).
    func stopLiveMonitoring() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isLiveMonitoring, !isRecording else { return }
        teardownMicCaptureOnMain(clearLiveDisplay: true)
        isLiveMonitoring = false
    }

    func startRecording() {
        print("[WatchAudioEngine] Starting...")
        requestMicrophoneAccess { [weak self] granted in
            guard granted, let self else { return }
            DispatchQueue.main.async {
                self.beginMicCaptureOnMain(recording: true)
            }
        }
    }

    private func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        if #available(watchOS 10.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: completion)
        } else {
            session.requestRecordPermission(completion)
        }
    }

    /// Arms the watch mic for live display and, when `recording` is true, file capture.
    /// Must run on the main queue (AVAudioSession + @Published state).
    private func beginMicCaptureOnMain(recording: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        if recording {
            guard !isRecording else { return }
            metricsCalculator.reset()
            recordingStartDate = Date()
            transition(to: prefersWatchLocalRecording ? .standalone : .wearableMic)
            isRecording = true
        } else {
            guard !isLiveMonitoring else { return }
            transition(to: .standalone)
            isLiveMonitoring = true
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement)
            try session.setActive(true)

            let inputNode = audioEngine.inputNode
            let tapFormat: AVAudioFormat
            if let micTapFormat {
                tapFormat = micTapFormat
            } else {
                inputNode.removeTap(onBus: 0)
                let hardwareFormat = inputNode.outputFormat(forBus: 0)
                tapFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: hardwareFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                ) ?? hardwareFormat

                inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
                    self?.processAudioBuffer(buffer)
                }
                isMicTapInstalled = true
                micTapFormat = tapFormat
            }

            if recording, prefersWatchLocalRecording {
                let fps = Float(tapFormat.sampleRate) / Float(bufferSize)
                do {
                    activeRecordingSession = try WatchRecordingSession(
                        format: tapFormat,
                        directory: WatchRecordingStore.shared.directory,
                        weighting: "A",
                        fps: fps,
                        fftBlockSize: fftSize,
                        calibrationOffset: watchMicCalibrationOffset
                    )
                } catch {
                    print("[WatchAudioEngine] failed to open recording session: \(error)")
                    activeRecordingSession = nil
                }
            }

            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            if recording {
                let runtimeSession = WKExtendedRuntimeSession()
                runtimeSession.delegate = self
                runtimeSession.start()
                self.session = runtimeSession
            }

            print("[WatchAudioEngine] Mic capture active (recording=\(recording), tap \(tapFormat.sampleRate) Hz)")
        } catch {
            print("Watch audio engine start error: \(error)")
            if recording {
                isRecording = false
                activeRecordingSession = nil
                transition(to: prefersWatchLocalRecording ? .standalone : .companion)
            } else {
                isLiveMonitoring = false
            }
        }
    }

    private func teardownMicCaptureOnMain(clearLiveDisplay: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isMicTapInstalled else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isMicTapInstalled = false
        micTapFormat = nil
        session?.invalidate()
        session = nil
        if clearLiveDisplay {
            currentSpectrogramData = nil
            liveData = nil
        }
    }

    func stopRecording() {
        dispatchPrecondition(condition: .onQueue(.main))
        print("[WatchAudioEngine] Stopping...")
        guard isRecording else { return }

        session?.invalidate()
        session = nil

        if let recordingSession = activeRecordingSession {
            activeRecordingSession = nil
            let title = WatchAudioEngine.defaultRecordingTitle(for: recordingSession.startDate)
            let metadata = recordingSession.finalize(title: title)
            WatchRecordingStore.shared.register(metadata)
            connectivityManager.syncPendingRecordings()
        }

        isRecording = false

        if prefersWatchLocalRecording {
            transition(to: .standalone)
            if !isLiveMonitoring {
                isLiveMonitoring = true
            }
        } else {
            teardownMicCaptureOnMain(clearLiveDisplay: true)
            isLiveMonitoring = false
            transition(to: .companion)
        }
        reconcileLiveDataSource()
        print("[WatchAudioEngine] Stopped")
    }

    // MARK: - Operating Mode transitions

    /// Switches the active operating mode. Manages the `liveData` source so
    /// widgets always see the right stream without branching themselves.
    private func transition(to newMode: WatchOperatingMode) {
        guard newMode != operatingMode else { return }
        operatingMode = newMode

        switch newMode {
        case .companion:
            stopLiveMonitoring()
            currentSpectrogramData = nil
            liveData = nil
            if usesPhoneAsLiveDataSource {
                subscribeToPhoneSpectrogram()
            }
        case .wearableMic, .standalone:
            // Watch mic is master — drop the phone subscription so two streams
            // don't fight for `liveData`.
            phoneSpectrogramSubscription?.cancel()
            phoneSpectrogramSubscription = nil
            // `liveData` will be set from `processAudioBuffer` on the next frame.
        }
    }

    /// Wires `connectivityManager.spectrogramData` into the unified `liveData`
    /// stream when the watch is in companion mode.
    private func subscribeToPhoneSpectrogram() {
        guard usesPhoneAsLiveDataSource else { return }
        phoneSpectrogramSubscription = connectivityManager.$spectrogramData
            .compactMap { $0 }
            .throttle(
                for: .seconds(Self.liveDataFlushInterval),
                scheduler: RunLoop.main,
                latest: true
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self,
                      self.usesPhoneAsLiveDataSource,
                      self.operatingMode == .companion,
                      !self.isRecording,
                      !self.isLiveMonitoring else { return }
                self.liveData = data
                self.updateActiveMeasurementSource()
            }
    }

    /// Whether live UI should mirror the iPhone over WatchConnectivity.
    private var usesPhoneAsLiveDataSource: Bool {
        shouldMirrorPhone()
    }

    /// Persist `.swr` + local catalog when the watch owns the recording.
    private var prefersWatchLocalRecording: Bool {
        Self.isWatchOnlyApp || measurementSourcePreference != .iPhone
    }

    /// `WKWatchOnly` App Store builds — never treat the phone as the live meter source.
    static var isWatchOnlyApp: Bool {
        Bundle.main.object(forInfoDictionaryKey: "WKWatchOnly") as? Bool ?? false
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, fillMonoSamples(from: buffer, frameCount: frameCount) else { return }

        // RMS / debug log
        var rms: Float = 0
        vDSP_rmsqv(monoSampleScratch, 1, &rms, vDSP_Length(frameCount))
        let inputDB = 20 * log10(rms + 1e-9)
        let estimatedSPL = inputDB + watchMicCalibrationOffset

        // Periodic input-level probe. Kept under #if DEBUG so neither the
        // counter increment, the vDSP min/max scan, the `String(format:)`
        // heap allocations, nor the `print` stdout lock run on the audio
        // render thread in release builds. On the watch's constrained CPU
        // these add up to enough churn to be visible in audio glitches.
        #if DEBUG
        debugFrameCount += 1
        if debugFrameCount % 60 == 0 {
            var minSample: Float = 0
            var maxSample: Float = 0
            vDSP_minv(monoSampleScratch, 1, &minSample, vDSP_Length(frameCount))
            vDSP_maxv(monoSampleScratch, 1, &maxSample, vDSP_Length(frameCount))
            print("[WatchAudioEngine] Input RMS: \(String(format: "%.1f", inputDB)) dBFS (~ \(String(format: "%.1f", estimatedSPL)) dB SPL), Samples: [\(String(format: "%.3f", minSample)) ... \(String(format: "%.3f", maxSample))]")
        }
        #endif

        // Berechne lokale FFT für sofortige Anzeige und für den optionalen
        // Watch-als-Quelle-Stream. Raw-Audio wird nicht mehr über WCSession
        // gesendet; der Phone-Pfad bekommt nur verarbeitete Spektrogrammdaten.
        guard frameCount >= fftSize else { return }

        // Copy first `fftSize` samples into our reusable FFT input buffer instead
        // of allocating via `Array(samples.prefix(fftSize))` per call.
        monoSampleScratch.withUnsafeBufferPointer { src in
            fftInputScratch.withUnsafeMutableBufferPointer { dst in
                _ = memcpy(dst.baseAddress!, src.baseAddress!,
                           fftSize * MemoryLayout<Float>.stride)
            }
        }
        performFFT(fftInputScratch)

        let splMagnitudesZ = calibratedSPL(fromDBFS: fftMagnitudes)
        let dbA = weightingProcessor.applyWeighting(
            to: fftMagnitudes, frequencies: binFrequencies, weighting: .a
        )
        let dbC = weightingProcessor.applyWeighting(
            to: fftMagnitudes, frequencies: binFrequencies, weighting: .c
        )
        let splMagnitudesA = calibratedSPL(fromDBFS: dbA)
        let splMagnitudesC = calibratedSPL(fromDBFS: dbC)

        let thirdOctaveZ = SpectrumBandAggregator.thirdOctaveBands(
            frequencies: binFrequencies, spectrum: splMagnitudesZ
        )
        let thirdOctaveA = SpectrumBandAggregator.thirdOctaveBands(
            frequencies: binFrequencies, spectrum: splMagnitudesA
        )
        let thirdOctaveC = SpectrumBandAggregator.thirdOctaveBands(
            frequencies: binFrequencies, spectrum: splMagnitudesC
        )
        let barkZ = SpectrumBandAggregator.barkBands(
            frequencies: binFrequencies, spectrum: splMagnitudesZ
        )

        // Real IEC 61672 metrics (M21/task-2), mirroring the iOS AudioEngine:
        // square the linear spectrum to per-bin energy, then derive Z/A/C frame
        // energies via dot-products with the precomputed (squared) weighting
        // gains. Calibration is applied in the energy domain so the calculator
        // emits dB SPL directly.
        let energyCount = min(fftLinearMagnitudes.count,
                              min(weightingProcessor.aWeightingGainsSq.count,
                                  weightingProcessor.cWeightingGainsSq.count))
        vDSP_vsq(fftLinearMagnitudes, 1, &fftEnergyScratch, 1, vDSP_Length(energyCount))

        var energyZ: Float = 0
        var energyA: Float = 0
        var energyC: Float = 0
        vDSP_sve(fftEnergyScratch, 1, &energyZ, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, weightingProcessor.aWeightingGainsSq, 1, &energyA, vDSP_Length(energyCount))
        vDSP_dotpr(fftEnergyScratch, 1, weightingProcessor.cWeightingGainsSq, 1, &energyC, vDSP_Length(energyCount))

        let calibrationFactor = pow(Float(10.0), watchMicCalibrationOffset / 10.0)
        energyZ *= calibrationFactor
        energyA *= calibrationFactor
        energyC *= calibrationFactor

        // LCpeak: per-bin C-weighted amplitude peak → dB SPL (frequency-domain
        // peak detector; same approach as iOS).
        let cGains = weightingProcessor.getWeightingGains(for: .c)
        let lcPeakCount = min(fftLinearMagnitudes.count, cGains.count)
        vDSP_vmul(fftLinearMagnitudes, 1, cGains, 1, &lcPeakScratch, 1, vDSP_Length(lcPeakCount))
        var cPeakLinear: Float = 0
        vDSP_maxv(lcPeakScratch, 1, &cPeakLinear, vDSP_Length(lcPeakCount))
        let lcPeak = 20.0 * log10(cPeakLinear + 1e-9) + watchMicCalibrationOffset

        let dt: Float = Float(fftSize) / Float(sampleRate)
        let recordingDuration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? 0

        let metricsResult = metricsCalculator.updateMetrics(
            energyZ: energyZ,
            energyA: energyA,
            energyC: energyC,
            peakLevel: lcPeak,
            dt: dt,
            recordingDuration: recordingDuration,
            frequencies: binFrequencies,
            magnitudes: splMagnitudesZ,
            bandsZ: thirdOctaveZ,
            bandsA: thirdOctaveA,
            bandsC: thirdOctaveC,
            loudnessReferenceKey: "LAF"
        )
        let levels = metricsResult.levels
        let levelSPL = levels["LAF"] ?? -120.0

        // Durable standalone capture: persist this buffer's audio + metrics.
        if let session = activeRecordingSession {
            session.writeBuffer(buffer)
            session.writeMeasurementFrame(
                levels: levels,
                timestamp: Float(recordingDuration),
                thirdOctaveZ: thirdOctaveZ,
                thirdOctaveA: thirdOctaveA,
                thirdOctaveC: thirdOctaveC
            )
        }

        var visualSamples = [Float](repeating: 0, count: fftSize)
        fftInputScratch.withUnsafeBufferPointer { src in
            visualSamples.withUnsafeMutableBufferPointer { dst in
                _ = memcpy(dst.baseAddress!, src.baseAddress!, fftSize * MemoryLayout<Float>.stride)
            }
        }

        let pending = PendingWatchAudioFrame(
            magnitudesZ: splMagnitudesZ,
            magnitudesA: splMagnitudesA,
            magnitudesC: splMagnitudesC,
            thirdOctaveZ: thirdOctaveZ,
            thirdOctaveA: thirdOctaveA,
            thirdOctaveC: thirdOctaveC,
            bandLeqZ: metricsResult.bandLeqZ,
            bandLeqA: metricsResult.bandLeqA,
            bandLeqC: metricsResult.bandLeqC,
            barkZ: barkZ,
            levels: levels,
            broadbandLevel: levelSPL,
            sampleRate: sampleRate,
            timestamp: Date(),
            visualSamples: visualSamples
        )

        // Coalesced flush to main (~5 Hz): DCT/visual + phone export run there,
        // not on the audio render thread (matches iOS RT-safety policy).
        scheduleLiveDataFlush(pending)
    }

    private func calibratedSPL(fromDBFS dbfs: [Float]) -> [Float] {
        var result = dbfs
        var offset = watchMicCalibrationOffset
        vDSP_vsadd(result, 1, &offset, &result, 1, vDSP_Length(result.count))
        return result
    }

    private func phoneExportData(from data: SpectrogramData) -> SpectrogramData {
        SpectrogramData(
            frequencies: data.frequencies,
            magnitudes: data.magnitudes,
            magnitudesA: data.magnitudesA,
            magnitudesC: data.magnitudesC,
            visualFrequencies: data.visualFrequencies,
            visualMagnitudes: data.visualMagnitudes,
            thirdOctaveBandsZ: data.thirdOctaveBandsZ,
            thirdOctaveBandsA: data.thirdOctaveBandsA,
            thirdOctaveBandsC: data.thirdOctaveBandsC,
            bandLeqZ: data.bandLeqZ,
            bandLeqA: data.bandLeqA,
            bandLeqC: data.bandLeqC,
            barkBandsZ: data.barkBandsZ,
            broadbandLevel: data.broadbandLevel,
            levels: data.levels,
            sampleRate: data.sampleRate,
            timestamp: data.timestamp
        )
    }

    private func spectrogramData(from frame: PendingWatchAudioFrame) -> SpectrogramData {
        SpectrogramData(
            frequencies: binFrequencies,
            magnitudes: frame.magnitudesZ,
            magnitudesA: frame.magnitudesA,
            magnitudesC: frame.magnitudesC,
            visualFrequencies: displayVisualFrequencies,
            visualMagnitudes: displayVisualMagnitudes,
            thirdOctaveBandsZ: frame.thirdOctaveZ,
            thirdOctaveBandsA: frame.thirdOctaveA,
            thirdOctaveBandsC: frame.thirdOctaveC,
            bandLeqZ: frame.bandLeqZ,
            bandLeqA: frame.bandLeqA,
            bandLeqC: frame.bandLeqC,
            barkBandsZ: frame.barkZ,
            broadbandLevel: frame.broadbandLevel,
            levels: frame.levels,
            sampleRate: frame.sampleRate,
            timestamp: frame.timestamp
        )
    }

    private func scheduleLiveDataFlush(_ frame: PendingWatchAudioFrame) {
        let scheduleNow: Bool = liveDataLock.withLockUnchecked {
            pendingAudioFrame = frame
            guard !isLiveDataFlushScheduled else { return false }
            isLiveDataFlushScheduled = true
            return true
        }
        guard scheduleNow else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.liveDataFlushInterval) { [weak self] in
            self?.flushPendingLiveData()
        }
    }

    private func flushPendingLiveData() {
        let frame = liveDataLock.withLockUnchecked { () -> PendingWatchAudioFrame? in
            let pending = pendingAudioFrame
            pendingAudioFrame = nil
            isLiveDataFlushScheduled = false
            return pending
        }
        guard let frame else { return }

        // DCT + display downsample are ~O(N log N); keep them off the main run loop
        // so TabView swipes and List scrolling stay responsive.
        visualDCTQueue.async { [weak self] in
            guard let self else { return }
            self.performVisualDCT(frame.visualSamples)
            let data = self.spectrogramData(from: frame)
            DispatchQueue.main.async {
                if self.connectivityManager.selectedMicrophoneSource == .appleWatch {
                    self.connectivityManager.sendSpectrogramData(self.phoneExportData(from: data))
                }

                self.currentSpectrogramData = data
                if self.operatingMode.watchMicIsActive && (self.isRecording || self.isLiveMonitoring) {
                    self.liveData = data
                    self.updateActiveMeasurementSource()
                }
            }
        }
    }

    /// Copies the first channel into `monoSampleScratch` with gain applied.
    /// Returns false when the buffer format is unsupported (no silent drop).
    private func fillMonoSamples(from buffer: AVAudioPCMBuffer, frameCount: Int) -> Bool {
        if monoSampleScratch.count != frameCount {
            monoSampleScratch = [Float](repeating: 0, count: frameCount)
        }

        if let channelData = buffer.floatChannelData?[0] {
            var localGain = gain
            monoSampleScratch.withUnsafeMutableBufferPointer { dst in
                vDSP_vsmul(channelData, 1, &localGain, dst.baseAddress!, 1, vDSP_Length(frameCount))
            }
            return true
        }

        if let channelData = buffer.int16ChannelData?[0] {
            let scale = Float(1.0 / 32768.0) * gain
            for index in 0..<frameCount {
                monoSampleScratch[index] = Float(channelData[index]) * scale
            }
            return true
        }

        return false
    }

    /// First-launch default: watch-only installs start standalone; companion
    /// installs default to phone-driven mode until the user toggles.
    static func resolvedMeasurementSourcePreference(
        defaults: UserDefaults = .standard,
        isWatchOnlyApp: Bool = WatchAudioEngine.isWatchOnlyApp
    ) -> WatchMeasurementSourcePreference {
        if isWatchOnlyApp {
            defaults.set(WatchMeasurementSourcePreference.appleWatch.rawValue,
                         forKey: PersistenceKeys.Watch.measurementSourcePreference)
            defaults.set(true, forKey: PersistenceKeys.Watch.standaloneEnabled)
            return .appleWatch
        }

        if let raw = defaults.string(forKey: PersistenceKeys.Watch.measurementSourcePreference),
           let preference = WatchMeasurementSourcePreference(rawValue: raw) {
            return preference
        }

        let legacyKey = PersistenceKeys.Watch.standaloneEnabled
        if defaults.object(forKey: legacyKey) != nil {
            let migrated: WatchMeasurementSourcePreference =
                defaults.bool(forKey: legacyKey) ? .appleWatch : .auto
            defaults.set(migrated.rawValue, forKey: PersistenceKeys.Watch.measurementSourcePreference)
            return migrated
        }

        return .auto
    }
    
    private func performFFT(_ samples: [Float]) {
        // Windowing into the N-length real signal buffer
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        // De-interleave windowed samples into split-complex input
        // (even samples → real, odd samples → imag) — same pattern as
        // Processing/FFTProcessor.swift. zrop expects N/2 split-complex pairs.
        windowedSamples.withUnsafeBytes { rawBuf in
            let complexPtr = rawBuf.bindMemory(to: DSPComplex.self).baseAddress!
            splitRealIn.withUnsafeMutableBufferPointer { realBuf in
                splitImagIn.withUnsafeMutableBufferPointer { imagBuf in
                    var splitDst = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_ctoz(complexPtr, 2, &splitDst, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // FFT
        vDSP_DFT_Execute(fftSetup, splitRealIn, splitImagIn, &realOut, &imagOut)

        // Magnitude (N/2 bins) — split-complex absolute value
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Normalisierung (2/N) — correct for vDSP_DFT_zrop's half-spectrum output.
        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))

        // Capture the linear-amplitude spectrum before the dB conversion below.
        // Preallocated destination → no audio-thread allocation. Used for the
        // weighted-energy and LCpeak math in `processAudioBuffer`.
        fftLinearMagnitudes.withUnsafeMutableBufferPointer { dst in
            fftMagnitudes.withUnsafeBufferPointer { src in
                _ = memcpy(dst.baseAddress!, src.baseAddress!, dst.count * MemoryLayout<Float>.stride)
            }
        }

        // Epsilon addieren um log(0) = -inf zu vermeiden
        var epsilon: Float = 1e-9
        vDSP_vsadd(fftMagnitudes, 1, &epsilon, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))

        var ref: Float = 1.0
        vDSP_vdbcon(fftMagnitudes, 1, &ref, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count), 1)
        
        // DEBUG: FFT Output Range — same #if DEBUG rationale as the input-RMS
        // probe above (avoid heap allocations and stdout lock on the audio
        // render thread in release builds).
        #if DEBUG
        if debugFrameCount % 60 == 0 {
            var minMagnitude: Float = 0
            var maxMagnitude: Float = 0
            var sumMagnitude: Float = 0
            let magnitudeCount = vDSP_Length(fftMagnitudes.count)
            vDSP_minv(fftMagnitudes, 1, &minMagnitude, magnitudeCount)
            vDSP_maxv(fftMagnitudes, 1, &maxMagnitude, magnitudeCount)
            vDSP_sve(fftMagnitudes, 1, &sumMagnitude, magnitudeCount)
            let averageMagnitude = sumMagnitude / Float(fftMagnitudes.count)
            print("[WatchAudioEngine] FFT Output Min: \(String(format: "%.1f", minMagnitude)) dB, Max: \(String(format: "%.1f", maxMagnitude)) dB, Avg: \(String(format: "%.1f", averageMagnitude)) dB")

            if maxMagnitude.isNaN || minMagnitude.isNaN {
                print("[WatchAudioEngine] Error: NaN detected in FFT output!")
            }

            // Prüfen ob DC-Offset (0 Hz) das Problem ist
            print("[WatchAudioEngine] FFT Low Freqs 0Hz: \(String(format: "%.1f", fftMagnitudes[0])) dB, 21Hz: \(String(format: "%.1f", fftMagnitudes[1])) dB")
        }
        #endif
    }

    private func performVisualDCT(_ samples: [Float]) {
        vDSP_vmul(samples, 1, window, 1, &visualWindowedSamples, 1, vDSP_Length(fftSize))
        visualDCT.transform(visualWindowedSamples, result: &visualCoefficients)
        vDSP_vabs(visualCoefficients, 1, &visualMagnitudes, 1, vDSP_Length(fftSize))

        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(visualMagnitudes, 1, &scale, &visualMagnitudes, 1, vDSP_Length(fftSize))

        // M15 task-3: explicit 20·log10 (amplitude convention) — DCT-II
        // coefficients are amplitude-domain values. Previously this used
        // `vDSP_vdbcon(..., 1)`; the explicit sequence matches the iOS
        // `VisualSpectrogramProcessor` code shape and is harder to misread.
        var lo: Float = 1e-10
        var hi: Float = .greatestFiniteMagnitude
        vDSP_vclip(visualMagnitudes, 1, &lo, &hi, &visualMagnitudes, 1, vDSP_Length(fftSize))
        var n = Int32(fftSize)
        vvlog10f(&visualMagnitudes, visualMagnitudes, &n)
        var twenty: Float = 20.0
        vDSP_vsmul(visualMagnitudes, 1, &twenty, &visualMagnitudes, 1, vDSP_Length(fftSize))

        downsampleForDisplay(source: visualMagnitudes, into: &displayVisualMagnitudes)
    }

    private static func makeDisplayFrequencies(count: Int, nyquist: Float) -> [Float] {
        guard count > 1 else { return [0] }
        return (0..<count).map { index in
            Float(index) * nyquist / Float(count - 1)
        }
    }

    private func downsampleForDisplay(source: [Float], into output: inout [Float]) {
        guard !source.isEmpty, !output.isEmpty else { return }

        let outputCount = output.count
        for index in 0..<outputCount {
            let start = index * source.count / outputCount
            let end = max(start + 1, (index + 1) * source.count / outputCount)
            var peak = source[start]
            if end > start + 1 {
                for sourceIndex in (start + 1)..<min(end, source.count) {
                    peak = max(peak, source[sourceIndex])
                }
            }
            output[index] = peak.isFinite ? peak : -180.0
        }
    }
    
    /// Human-readable default title for a freshly captured recording.
    private static func defaultRecordingTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return "Aufnahme \(formatter.string(from: date))"
    }

    // MARK: - WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("[WatchAudioEngine] RuntimeSession invalidated: \(reason.rawValue) error: \(String(describing: error))")
        // WKExtendedRuntimeSession delegate callbacks arrive on an arbitrary
        // background thread. Hop to main before touching @Published state or
        // calling stopRecording() (enforced by dispatchPrecondition there).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.session = nil
            // The session is gone; the audio tap is no longer "kept alive" by
            // the system and would otherwise keep draining the battery in the
            // background. Stop the engine if we still think we're recording.
            if self.isRecording {
                self.stopRecording()
            }
        }
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession started")
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession will expire")
        // Hop to main — same rationale as didInvalidateWith above.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Graceful stop before the system invalidates the session. If the
            // user wants to keep going they'll need to restart explicitly — the
            // audit ("do NOT auto-resume; the user may have lowered the wrist
            // deliberately") rules out automatic re-arming.
            if self.isRecording {
                self.stopRecording()
            }
        }
    }

    // MARK: - Lifecycle defense (called from SwiftUI scenePhase observer)

    /// Called by the watch app when the scene goes to `.background`. Stops
    /// the audio engine to release the mic and prevent silent battery drain
    /// if the `WKExtendedRuntimeSession` is missed or rejected.
    func handleSceneBackgrounded() {
        if isRecording {
            if let session, session.state == .running {
                return
            }
            stopRecording()
            return
        }
        stopLiveMonitoring()
    }
}
