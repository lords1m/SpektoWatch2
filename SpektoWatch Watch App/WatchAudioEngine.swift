import Foundation
import AVFoundation
import WatchKit
import Combine
import Accelerate
import os

class WatchAudioEngine: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
    /// Single source of truth for what the watch is doing.
    /// Widgets observe `$liveData` instead of branching on `isRecording`.
    @Published private(set) var operatingMode: WatchOperatingMode = .companion

    /// User preference: operate watch-first (standalone) instead of as a phone
    /// companion. Persisted in `UserDefaults`. When set, a recording captures
    /// with the watch mic into `.standalone` mode (local storage, no phone
    /// coordination); when clear, recording uses `.wearableMic` and hands the
    /// mic back to the phone (`.companion`) on stop.
    @Published private(set) var standaloneEnabled: Bool

    private var phoneSpectrogramSubscription: AnyCancellable?
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
    private let displayVisualFrequencies: [Float]

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
    private var pendingLiveData: SpectrogramData?
    private var isLiveDataFlushScheduled = false
    private static let liveDataFlushInterval: TimeInterval = 0.2  // 5 Hz
    private static let displayVisualBinCount = 40

    init(connectivityManager: WatchConnectivityManager) {
        self.connectivityManager = connectivityManager
        self.standaloneEnabled = UserDefaults.standard.bool(forKey: PersistenceKeys.Watch.standaloneEnabled)
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
        displayVisualMagnitudes = [Float](repeating: -180.0, count: Self.displayVisualBinCount)
        fftInputScratch = [Float](repeating: 0, count: fftSize)

        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_DENORM))

        // Bin frequencies are constant for a given fftSize/sampleRate — compute once.
        let binCount = fftSize / 2
        let binWidth = Float(sampleRate) / Float(fftSize)
        var freqs = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount { freqs[i] = Float(i) * binWidth }
        binFrequencies = freqs
        let nyquist = Float(sampleRate / 2.0)
        displayVisualFrequencies = Self.makeDisplayFrequencies(count: Self.displayVisualBinCount, nyquist: nyquist)

        super.init()

        // Companion mode by default: forward phone spectrogram into liveData.
        // The subscription is replaced when we transition into wearableMic mode
        // so we don't pay for two streams at once.
        //
        // Phone-absent UX (M21/task-1): if the user has chosen standalone, the
        // watch is the source of truth — start in `.standalone` and do NOT
        // subscribe to the phone. Launch never blocks on or assumes a present
        // phone in this mode.
        if standaloneEnabled {
            operatingMode = .standalone
        } else {
            subscribeToPhoneSpectrogram()
        }

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

    func setGain(_ newGain: Float) {
        // Clamp the gain to a reasonable range, e.g., 0.0 to 10.0
        self.gain = max(0.0, min(newGain, 10.0))
        print("[WatchAudioEngine] Gain set to \(self.gain)")
    }

    /// Toggle the watch-first (standalone) preference. Persists the choice and,
    /// when idle, re-points the live-data source: standalone drops the phone
    /// subscription (watch-first), companion re-subscribes. A no-op while
    /// recording — the active capture finishes in its current mode and the new
    /// preference takes effect on the next start/stop.
    func setStandaloneEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled != standaloneEnabled else { return }
        standaloneEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: PersistenceKeys.Watch.standaloneEnabled)
        guard !isRecording else { return }
        transition(to: enabled ? .standalone : .companion)
    }

    func startRecording() {
        print("[WatchAudioEngine] Starting...")
        let session = AVAudioSession.sharedInstance()
        
        let handlePermission: (Bool) -> Void = { [weak self] granted in
            guard granted, let self = self else { return }

            // Fresh integration window for LAeq/LCpeak each session.
            self.metricsCalculator.reset()
            self.recordingStartDate = Date()

            do {
                // Configure audio session BEFORE querying inputNode format or installing tap,
                // otherwise the tap may be installed with the wrong sample rate/channel layout.
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)

                let inputNode = self.audioEngine.inputNode
                inputNode.removeTap(onBus: 0) // Remove existing tap to prevent crash
                let recordingFormat = inputNode.outputFormat(forBus: 0)

                // Standalone: open a durable on-watch recording (audio + .swr)
                // BEFORE the engine starts so the first frames are captured. In
                // companion/wearableMic the phone owns storage — no local file.
                if self.standaloneEnabled {
                    let fps = Float(self.sampleRate) / Float(self.bufferSize)
                    do {
                        self.activeRecordingSession = try WatchRecordingSession(
                            format: recordingFormat,
                            directory: WatchRecordingStore.shared.directory,
                            weighting: "A",
                            fps: fps)
                    } catch {
                        print("[WatchAudioEngine] failed to open recording session: \(error)")
                        self.activeRecordingSession = nil
                    }
                }

                inputNode.installTap(onBus: 0, bufferSize: self.bufferSize, format: recordingFormat) { [weak self] buffer, _ in
                    self?.processAudioBuffer(buffer)
                }

                try self.audioEngine.start()

                // Keep app alive during recording
                self.session = WKExtendedRuntimeSession()
                self.session?.delegate = self
                self.session?.start()

                DispatchQueue.main.async {
                    self.isRecording = true
                    // Watch mic is now driving — switch into the watch-mic mode and
                    // detach the phone-spectrogram subscription so liveData reflects
                    // the local FFT exclusively. Standalone keeps the recording
                    // phone-independent (local storage, opportunistic later sync);
                    // wearableMic coordinates with a present phone.
                    self.transition(to: self.standaloneEnabled ? .standalone : .wearableMic)
                }
                print("[WatchAudioEngine] Started successfully")
            } catch {
                print("Watch audio engine start error: \(error)")
            }
        }

        if #available(watchOS 10.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handlePermission)
        } else {
            session.requestRecordPermission(handlePermission)
        }
    }

    func stopRecording() {
        dispatchPrecondition(condition: .onQueue(.main))
        print("[WatchAudioEngine] Stopping...")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        session?.invalidate()
        session = nil

        // The tap is removed — no more audio frames. Flush both files to disk
        // and add the recording to the durable catalog. Done before clearing
        // isRecording so a missed/expired runtime session can't double-finalize.
        if let recordingSession = activeRecordingSession {
            activeRecordingSession = nil
            let title = WatchAudioEngine.defaultRecordingTitle(for: recordingSession.startDate)
            let metadata = recordingSession.finalize(title: title)
            WatchRecordingStore.shared.register(metadata)
            // Opportunistically offer the fresh recording to the phone. The
            // transfer is OS-queued, so this is safe even if not reachable yet;
            // reachability/activation also retry via syncPendingRecordings.
            connectivityManager.syncPendingRecordings()
        }

        isRecording = false
        // Hand the microphone back to the phone — re-enter companion mode and
        // resubscribe to phone spectrogram updates. In standalone the user is
        // watch-first: stay phone-independent (no resubscribe), just clear the
        // live display.
        if standaloneEnabled {
            transition(to: .standalone)
            // transition() is a no-op when already in `.standalone`; clear the
            // live display directly so a stopped recording doesn't leave the
            // last frame frozen on screen.
            currentSpectrogramData = nil
            liveData = nil
        } else {
            transition(to: .companion)
        }
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
            // Phone is master; clear any stale local FFT and re-subscribe to phone.
            currentSpectrogramData = nil
            liveData = nil
            subscribeToPhoneSpectrogram()
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
        phoneSpectrogramSubscription = connectivityManager.$spectrogramData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self, self.operatingMode == .companion else { return }
                self.liveData = data
            }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Reuse `monoSampleScratch` instead of allocating `[Float]` per callback.
        // `channelData` points into AVAudioPCMBuffer's internal storage and must
        // not be written in place; we apply gain into our owned buffer.
        if monoSampleScratch.count != frameCount {
            monoSampleScratch = [Float](repeating: 0, count: frameCount)
        }
        var localGain = gain
        monoSampleScratch.withUnsafeMutableBufferPointer { dst in
            vDSP_vsmul(channelData, 1, &localGain, dst.baseAddress!, 1, vDSP_Length(frameCount))
        }

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
        performVisualDCT(fftInputScratch)

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
            magnitudes: fftMagnitudes)
        let levels = metricsResult.levels
        let levelSPL = levels["LAF"] ?? -120.0

        // Durable standalone capture: persist this buffer's audio + metrics.
        // The session's writers are internally thread-safe (the .swr writer
        // dispatches disk I/O off this audio thread); audioFile.write is the
        // same call the engine already makes for live FFT.
        if let session = activeRecordingSession {
            session.writeBuffer(buffer)
            session.writeMeasurementFrame(levels: levels, timestamp: Float(recordingDuration))
        }

        // `binFrequencies` is a single immutable property — no per-frame rebuild.
        let data = SpectrogramData(frequencies: binFrequencies,
                                   magnitudes: fftMagnitudes,
                                   visualFrequencies: displayVisualFrequencies,
                                   visualMagnitudes: displayVisualMagnitudes,
                                   broadbandLevel: levelSPL,
                                   levels: levels,
                                   sampleRate: sampleRate)

        if connectivityManager.selectedMicrophoneSource == .appleWatch {
            connectivityManager.sendSpectrogramData(phoneExportData(from: data))
        }

        // Coalesced flush to main — see `liveDataLock` block above for the
        // rationale. This replaces a per-callback `DispatchQueue.main.async`
        // that delivered 1024-float copies at the FFT framerate.
        scheduleLiveDataFlush(data)
    }

    private func phoneExportData(from data: SpectrogramData) -> SpectrogramData {
        SpectrogramData(
            frequencies: data.frequencies,
            magnitudes: addCalibrationOffset(to: data.magnitudes),
            visualFrequencies: data.visualFrequencies,
            visualMagnitudes: data.visualMagnitudes.map { addCalibrationOffset(to: $0) },
            broadbandLevel: data.broadbandLevel,
            levels: data.levels,
            sampleRate: data.sampleRate,
            timestamp: data.timestamp
        )
    }

    private func addCalibrationOffset(to values: [Float]) -> [Float] {
        var result = values
        var offset = watchMicCalibrationOffset
        vDSP_vsadd(result, 1, &offset, &result, 1, vDSP_Length(result.count))
        return result
    }

    private func scheduleLiveDataFlush(_ data: SpectrogramData) {
        let scheduleNow: Bool = liveDataLock.withLockUnchecked {
            pendingLiveData = data
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
        let data = liveDataLock.withLockUnchecked { () -> SpectrogramData? in
            let pending = pendingLiveData
            pendingLiveData = nil
            isLiveDataFlushScheduled = false
            return pending
        }
        guard let data else { return }
        currentSpectrogramData = data
        // Surface to the unified stream when the local mic owns the truth.
        if operatingMode.watchMicIsActive {
            liveData = data
        }
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
                memcpy(dst.baseAddress!, src.baseAddress!, dst.count * MemoryLayout<Float>.stride)
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
        guard isRecording else { return }
        // When an extended runtime session is active and `.running`, the
        // system is intentionally keeping the audio tap alive — don't kill
        // it from a backgrounding event in that case.
        if let session, session.state == .running {
            return
        }
        stopRecording()
    }
}
