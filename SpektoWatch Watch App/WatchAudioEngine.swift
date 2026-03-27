import Foundation
import AVFoundation
import WatchKit
import Combine
import Accelerate

class WatchAudioEngine: NSObject, ObservableObject, WKExtendedRuntimeSessionDelegate {
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
    private var debugFrameCount = 0
    private var lafEnergy: Float = 1e-12

    @Published var isRecording = false
    @Published var currentSpectrogramData: SpectrogramData?

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
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        super.init()

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
        startRecording()
    }

    @objc private func handleStopRecording() {
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
        }
        print("[WatchAudioEngine] Stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frameCount = Int(buffer.frameLength)
        // Copy into a local buffer before applying gain — channelData points into
        // AVAudioPCMBuffer's internal storage which must not be written in-place.
        var samples = [Float](repeating: 0, count: frameCount)
        vDSP_vsmul(channelData, 1, &gain, &samples, 1, vDSP_Length(frameCount))

        // DEBUG: Input Level prüfen
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let inputDB = 20 * log10(rms + 1e-9)
        
        // Kalibrierung: dBFS zu geschätztem dB SPL (Sound Pressure Level)
        // Apple Watch Mikrofone haben oft einen Offset von ca. 100 dB (0 dBFS ≈ 100 dB SPL)
        let estimatedSPL = inputDB + 100.0
        
        debugFrameCount += 1
        if debugFrameCount % 60 == 0 {
            let minSample = samples.min() ?? 0
            let maxSample = samples.max() ?? 0
            print("[WatchAudioEngine] Input RMS: \(String(format: "%.1f", inputDB)) dBFS (~ \(String(format: "%.1f", estimatedSPL)) dB SPL), Samples: [\(String(format: "%.3f", minSample)) ... \(String(format: "%.3f", maxSample))]")
        }

        // 1. Sende Audio an iPhone (für High-End Verarbeitung/Speicherung)
        let audioData = AudioData(samples: samples, sampleRate: sampleRate)
        self.connectivityManager.sendAudioData(audioData)
        
        // 2. Berechne lokale FFT für sofortige Anzeige (Latenzfrei)
        if samples.count >= fftSize {
            let input = Array(samples.prefix(fftSize))
            let magnitudes = performFFT(input)
            
            // Calculate LAF (approximate)
            var frameEnergy: Float = 0.0
            for magDB in magnitudes {
                frameEnergy += pow(10.0, magDB / 10.0)
            }
            // Watch update rate is ~21Hz (2048 samples @ 44.1k) -> dt = 0.046s
            let dt: Float = Float(fftSize) / Float(sampleRate)
            let alpha = 1.0 - exp(-dt / 0.125)
            lafEnergy = (1.0 - alpha) * lafEnergy + alpha * frameEnergy
            let level = 10.0 * log10(lafEnergy + 1e-12)
            
            // Dummy Frequenzen (werden für die Anzeige nicht zwingend gebraucht, da wir Indizes mappen)
            let freqs = [Float](repeating: 0, count: magnitudes.count)
            let data = SpectrogramData(frequencies: freqs, magnitudes: magnitudes, broadbandLevel: level, sampleRate: sampleRate)
            
            DispatchQueue.main.async {
                self.currentSpectrogramData = data
            }
        }
    }
    
    private func performFFT(_ samples: [Float]) -> [Float] {
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
        
        // DEBUG: FFT Output Range
        if debugFrameCount % 60 == 0 {
            if let max = fftMagnitudes.max(), let min = fftMagnitudes.min() {
                let avg = fftMagnitudes.reduce(0, +) / Float(fftMagnitudes.count)
                print("[WatchAudioEngine] FFT Output Min: \(String(format: "%.1f", min)) dB, Max: \(String(format: "%.1f", max)) dB, Avg: \(String(format: "%.1f", avg)) dB")
                
                if max.isNaN || min.isNaN {
                    print("[WatchAudioEngine] Error: NaN detected in FFT output!")
                }
                
                // Prüfen ob DC-Offset (0 Hz) das Problem ist
                print("[WatchAudioEngine] FFT Low Freqs 0Hz: \(String(format: "%.1f", fftMagnitudes[0])) dB, 21Hz: \(String(format: "%.1f", fftMagnitudes[1])) dB")
            }
        }
        
        return Array(fftMagnitudes)
    }
    
    // MARK: - WKExtendedRuntimeSessionDelegate
    
    func extendedRuntimeSession(_ session: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        print("[WatchAudioEngine] RuntimeSession invalidated: \(reason.rawValue) error: \(String(describing: error))")
        self.session = nil
    }

    func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession started")
    }

    func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        print("[WatchAudioEngine] RuntimeSession will expire")
    }
}
