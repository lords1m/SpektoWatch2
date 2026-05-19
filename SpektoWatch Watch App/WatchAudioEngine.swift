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

    private var phoneSpectrogramSubscription: AnyCancellable?
    private var audioEngine: AVAudioEngine
    private let bufferSize: AVAudioFrameCount = 4096
    private let sampleRate: Double = 44100.0
    private var session: WKExtendedRuntimeSession?
    private let connectivityManager: WatchConnectivityManager
    private var gain: Float = 1.0

    // Lokale FFT Konfiguration (Abgespeckt für Watch)
    private let fftSize: Int = 2048
    private let fftSetup: vDSP_DFT_Setup
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var window: [Float]
    private var fftMagnitudes: [Float]
    #if DEBUG
    private var debugFrameCount = 0
    #endif
    private var lafEnergy: Float = 1e-12

    // Pre-computed once, reused per-frame: bin frequencies (constant for given fftSize/sampleRate)
    // and a scratch buffer for converting magnitude-dB to linear power for energy summation.
    private let binFrequencies: [Float]
    private var linearPowerScratch: [Float]

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

    init(connectivityManager: WatchConnectivityManager) {
        self.connectivityManager = connectivityManager
        audioEngine = AVAudioEngine()
        
        // FFT Setup initialisieren
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD) else {
            fatalError("Failed to create FFT setup")
        }
        fftSetup = setup
        
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        fftInputScratch = [Float](repeating: 0, count: fftSize)
        linearPowerScratch = [Float](repeating: 0, count: fftSize / 2)

        // Hann window — manual implementation to avoid vDSP API compatibility issues.
        let n = Float(fftSize)
        for i in 0..<fftSize {
            let x = Float(i) / n
            window[i] = 0.5 - 0.5 * cos(2 * .pi * x)
        }

        // Bin frequencies are constant for a given fftSize/sampleRate — compute once.
        let binCount = fftSize / 2
        let binWidth = Float(sampleRate) / Float(fftSize)
        var freqs = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount { freqs[i] = Float(i) * binWidth }
        binFrequencies = freqs

        super.init()

        // Companion mode by default: forward phone spectrogram into liveData.
        // The subscription is replaced when we transition into wearableMic mode
        // so we don't pay for two streams at once.
        subscribeToPhoneSpectrogram()

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

    func startRecording() {
        print("[WatchAudioEngine] Starting...")
        let session = AVAudioSession.sharedInstance()
        
        let handlePermission: (Bool) -> Void = { [weak self] granted in
            guard granted, let self = self else { return }
            
            do {
                // Configure audio session BEFORE querying inputNode format or installing tap,
                // otherwise the tap may be installed with the wrong sample rate/channel layout.
                try session.setCategory(.record, mode: .measurement)
                try session.setActive(true)

                let inputNode = self.audioEngine.inputNode
                inputNode.removeTap(onBus: 0) // Remove existing tap to prevent crash
                let recordingFormat = inputNode.outputFormat(forBus: 0)

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
                    // Watch mic is now driving — switch into wearableMic mode and
                    // detach the phone-spectrogram subscription so liveData reflects
                    // the local FFT exclusively.
                    self.transition(to: .wearableMic)
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
        print("[WatchAudioEngine] Stopping...")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        session?.invalidate()
        session = nil

        DispatchQueue.main.async {
            self.isRecording = false
            // Hand the microphone back to the phone — re-enter companion mode
            // and resubscribe to phone spectrogram updates.
            self.transition(to: .companion)
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
        // Watch mic ≈ 100 dB SPL @ 0 dBFS (rough calibration constant)
        let estimatedSPL = inputDB + 100.0

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

        // LAF energy: convert dB → linear power, then sum with vDSP_sve.
        // 10^(magDB/10) is equivalent to exp(magDB * ln(10) / 10).
        var scale = Float(log(10.0) / 10.0)
        let n = vDSP_Length(fftMagnitudes.count)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &linearPowerScratch, 1, n)
        vForce.exp(linearPowerScratch, result: &linearPowerScratch)
        var frameEnergy: Float = 0
        vDSP_sve(linearPowerScratch, 1, &frameEnergy, n)

        // EMA: τ = 125 ms (IEC 61672 "F"), dt = fftSize / sampleRate ≈ 46 ms
        let dt: Float = Float(fftSize) / Float(sampleRate)
        let alpha = 1.0 - exp(-dt / 0.125)
        lafEnergy = (1.0 - alpha) * lafEnergy + alpha * frameEnergy
        let level = 10.0 * log10(lafEnergy + 1e-12)

        // `binFrequencies` is a single immutable property — no per-frame rebuild.
        let data = SpectrogramData(frequencies: binFrequencies,
                                   magnitudes: fftMagnitudes,
                                   broadbandLevel: level,
                                   sampleRate: sampleRate)

        if connectivityManager.selectedMicrophoneSource == .appleWatch {
            connectivityManager.sendSpectrogramData(data)
        }

        // Coalesced flush to main — see `liveDataLock` block above for the
        // rationale. This replaces a per-callback `DispatchQueue.main.async`
        // that delivered 1024-float copies at the FFT framerate.
        scheduleLiveDataFlush(data)
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
        // Windowing
        vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))
        
        // FFT
        vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)
        
        // Magnitude & dB
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var complex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // FIX: Normalisierung (2/N) um korrekte Amplitude zu erhalten
        // Ohne das sind die Werte um Faktor 2048 zu hoch (~ +66 dB), was zum türkisen Bild führt
        var scale: Float = 2.0 / Float(fftSize)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        
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
    
    // MARK: - WKExtendedRuntimeSessionDelegate

    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("[WatchAudioEngine] RuntimeSession invalidated: \(reason.rawValue) error: \(String(describing: error))")
        self.session = nil
        // The session is gone; the audio tap is no longer "kept alive" by the
        // system and would otherwise keep draining the battery in the
        // background. Stop the engine if we still think we're recording.
        if isRecording {
            stopRecording()
        }
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession started")
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession will expire")
        // Graceful stop before the system invalidates the session. If the
        // user wants to keep going they'll need to restart explicitly — the
        // audit ("do NOT auto-resume; the user may have lowered the wrist
        // deliberately") rules out automatic re-arming.
        if isRecording {
            stopRecording()
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
