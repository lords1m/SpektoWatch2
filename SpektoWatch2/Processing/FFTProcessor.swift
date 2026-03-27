import Foundation
import Accelerate
import os.signpost

// MARK: - Window Function Types

/// Verfügbare Fensterfunktionen für die FFT-Analyse
/// Jede Fensterfunktion hat unterschiedliche Eigenschaften bezüglich spektraler Leckage und Frequenzauflösung
enum WindowFunction: String, CaseIterable, Identifiable {
    case rectangular = "Rectangular"
    case hann = "Hann"
    case hamming = "Hamming"
    case blackman = "Blackman"
    case blackmanHarris = "Blackman-Harris"
    case flatTop = "Flat Top"

    var id: String { rawValue }

    /// Deutscher Name für UI
    var localizedName: String {
        switch self {
        case .rectangular: return "Rechteck"
        case .hann: return "Hann"
        case .hamming: return "Hamming"
        case .blackman: return "Blackman"
        case .blackmanHarris: return "Blackman-Harris"
        case .flatTop: return "Flat Top"
        }
    }

    /// Hauptlappen-Breite in Bins (relativ zu Rectangular)
    var mainLobeWidth: Float {
        switch self {
        case .rectangular: return 1.0
        case .hann: return 2.0
        case .hamming: return 2.0
        case .blackman: return 3.0
        case .blackmanHarris: return 4.0
        case .flatTop: return 5.0
        }
    }

    /// Seitenlappen-Dämpfung in dB (höher = besser für Leckage-Unterdrückung)
    var sidelobeAttenuation: Float {
        switch self {
        case .rectangular: return -13
        case .hann: return -32
        case .hamming: return -43
        case .blackman: return -58
        case .blackmanHarris: return -92
        case .flatTop: return -93
        }
    }

    /// Kurze Beschreibung der Eigenschaften
    var description: String {
        switch self {
        case .rectangular:
            return "Beste Frequenzauflösung, aber starke spektrale Leckage. Geeignet wenn Signalfrequenz exakt auf FFT-Bin fällt."
        case .hann:
            return "Guter Kompromiss zwischen Auflösung und Leckage. Standard für allgemeine Anwendungen."
        case .hamming:
            return "Ähnlich wie Hann, aber bessere Seitenlappen-Unterdrückung auf Kosten von mehr Hauptlappen-Breite."
        case .blackman:
            return "Sehr gute Leckage-Unterdrückung. Ideal für Breitbandanalyse mit schwachen Signalen neben starken."
        case .blackmanHarris:
            return "Exzellente Leckage-Unterdrückung (-92 dB). Für präzise Amplitudenmessung bei bekannten Frequenzen."
        case .flatTop:
            return "Optimiert für genaue Amplitudenmessung. Breitester Hauptlappen, aber präziseste Pegelwerte."
        }
    }

    /// Erzeugt die Fensterfunktion
    func generate(size: Int) -> [Float] {
        var window = [Float](repeating: 0, count: size)
        let n = Float(size)

        switch self {
        case .rectangular:
            for i in 0..<size {
                window[i] = 1.0
            }

        case .hann:
            vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        case .hamming:
            vDSP_hamm_window(&window, vDSP_Length(size), 0)

        case .blackman:
            vDSP_blkman_window(&window, vDSP_Length(size), 0)

        case .blackmanHarris:
            // 4-term Blackman-Harris
            let a0: Float = 0.35875
            let a1: Float = 0.48829
            let a2: Float = 0.14128
            let a3: Float = 0.01168
            for i in 0..<size {
                let x = Float(i) / n
                window[i] = a0 - a1 * cos(2 * .pi * x) + a2 * cos(4 * .pi * x) - a3 * cos(6 * .pi * x)
            }

        case .flatTop:
            // Flat Top Window für präzise Amplitudenmessung
            let a0: Float = 0.21557895
            let a1: Float = 0.41663158
            let a2: Float = 0.277263158
            let a3: Float = 0.083578947
            let a4: Float = 0.006947368
            for i in 0..<size {
                let x = Float(i) / n
                window[i] = a0 - a1 * cos(2 * .pi * x) + a2 * cos(4 * .pi * x) - a3 * cos(6 * .pi * x) + a4 * cos(8 * .pi * x)
            }
        }

        return window
    }

    /// Kohärenter Gain-Korrekturfaktor (für Amplitudenmessung)
    var coherentGain: Float {
        switch self {
        case .rectangular: return 1.0
        case .hann: return 0.5
        case .hamming: return 0.54
        case .blackman: return 0.42
        case .blackmanHarris: return 0.35875
        case .flatTop: return 0.21557895
        }
    }
}

// MARK: - FFT Block Size

/// Verfügbare FFT-Blockgrößen
/// Größere Blöcke = bessere Frequenzauflösung, schlechtere Zeitauflösung (Heisenberg-Prinzip)
enum FFTBlockSize: Int, CaseIterable, Identifiable {
    case size512 = 512
    case size1024 = 1024
    case size2048 = 2048
    case size4096 = 4096
    case size8192 = 8192
    case size16384 = 16384

    var id: Int { rawValue }

    /// Frequenzauflösung bei 44.1 kHz Samplerate
    var frequencyResolution: Float {
        return 44100.0 / Float(rawValue)
    }

    /// Zeitauflösung in Millisekunden bei 44.1 kHz
    var timeResolution: Float {
        return Float(rawValue) / 44100.0 * 1000.0
    }

    /// Beschreibung für UI
    var description: String {
        let freqRes = String(format: "%.1f", frequencyResolution)
        let timeRes = String(format: "%.0f", timeResolution)
        return "\(rawValue) Samples (\(freqRes) Hz / \(timeRes) ms)"
    }

    /// Kurze Beschreibung
    var shortDescription: String {
        return "\(rawValue)"
    }
}

/// Handles FFT computation and magnitude conversion
/// Thread-safe: all access to mutable state is protected by a lock
class FFTProcessor {
    private static let performanceLog = OSLog(subsystem: "com.spektowatch", category: "performance.fft")
    private(set) var fftSize: Int
    private let sampleRate: Double
    private var fftSetup: vDSP_DFT_Setup?

    /// Lock for thread-safe access to FFT setup and buffers
    private let lock = NSLock()

    // Pre-allocated buffers for performance
    private var window: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var windowedSamples: [Float]
    private var magnitudesBuffer: [Float]

    /// Frequency array corresponding to FFT bins
    private(set) var frequencies: [Float]

    /// Aktuelle Fensterfunktion
    private(set) var windowFunction: WindowFunction = .hann

    // MARK: - Initialization

    init(fftSize: Int, sampleRate: Double, windowFunction: WindowFunction = .hann) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        self.windowFunction = windowFunction

        // Create FFT setup
        self.fftSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        )

        // Pre-allocate buffers
        self.window = [Float](repeating: 0, count: fftSize)
        self.realIn = [Float](repeating: 0, count: fftSize / 2)
        self.imagIn = [Float](repeating: 0, count: fftSize / 2)
        self.realPart = [Float](repeating: 0, count: fftSize / 2)
        self.imagPart = [Float](repeating: 0, count: fftSize / 2)
        self.windowedSamples = [Float](repeating: 0, count: fftSize)
        self.magnitudesBuffer = [Float](repeating: 0, count: fftSize / 2)

        // Create window
        self.window = windowFunction.generate(size: fftSize)

        // Compute frequency bins
        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        self.frequencies = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
    }

    // MARK: - Configuration

    /// Ändert die Fensterfunktion
    /// Thread-safe: locks access during window change
    func setWindowFunction(_ function: WindowFunction) {
        lock.lock()
        defer { lock.unlock() }

        guard function != windowFunction else { return }
        windowFunction = function
        window = function.generate(size: fftSize)
    }

    /// Ändert die FFT-Größe (erfordert Neuinitialisierung)
    /// Thread-safe: locks access during reconfiguration
    func reconfigure(fftSize newSize: Int, windowFunction newWindow: WindowFunction? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard newSize != fftSize || (newWindow != nil && newWindow != windowFunction) else { return }

        // Validiere dass newSize eine Potenz von 2 ist
        guard newSize > 0 && (newSize & (newSize - 1)) == 0 else {
            print("[FFTProcessor] Invalid FFT size: \(newSize) - must be power of 2")
            return
        }

        // Erstelle neues Setup BEVOR wir das alte zerstören
        let newSetup = vDSP_DFT_zrop_CreateSetup(
            nil,
            vDSP_Length(newSize),
            vDSP_DFT_Direction.FORWARD
        )

        // Prüfe ob Setup erfolgreich erstellt wurde
        guard newSetup != nil else {
            print("[FFTProcessor] Failed to create FFT setup for size: \(newSize)")
            return
        }

        // Jetzt ist es sicher, das alte Setup zu zerstören
        if let oldSetup = fftSetup {
            vDSP_DFT_DestroySetup(oldSetup)
        }

        fftSetup = newSetup
        fftSize = newSize

        if let newWindow = newWindow {
            windowFunction = newWindow
        }

        // Reallocate buffers
        window = windowFunction.generate(size: fftSize)
        realIn = [Float](repeating: 0, count: fftSize / 2)
        imagIn = [Float](repeating: 0, count: fftSize / 2)
        realPart = [Float](repeating: 0, count: fftSize / 2)
        imagPart = [Float](repeating: 0, count: fftSize / 2)
        windowedSamples = [Float](repeating: 0, count: fftSize)
        magnitudesBuffer = [Float](repeating: 0, count: fftSize / 2)

        // Recompute frequency bins
        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        frequencies = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
    }

    /// Gibt die aktuelle Fensterfunktion als Array zurück (für Visualisierung)
    func getWindowValues() -> [Float] {
        return window
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
            fftSetup = nil
        }
    }

    // MARK: - FFT Processing

    /// Performs FFT and returns linear magnitudes
    /// Thread-safe: locks access during FFT computation
    /// - Parameters:
    ///   - samples: Time-domain samples (must be fftSize length)
    ///   - gainBoost: Gain multiplier to apply before FFT
    /// - Returns: Array of linear magnitude values (fftSize/2 length)
    func performFFT(on samples: [Float], gainBoost: Float = 1.0) -> [Float] {
        let signpostID = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "PerformFFT", signpostID: signpostID)
        defer { os_signpost(.end, log: Self.performanceLog, name: "PerformFFT", signpostID: signpostID) }

        lock.lock()
        defer { lock.unlock() }

        guard samples.count >= fftSize else {
            return [Float](repeating: 0, count: fftSize / 2)
        }

        // Apply window and gain
        vDSP_vmul(samples, 1, window, 1, &windowedSamples, 1, vDSP_Length(fftSize))

        if gainBoost != 1.0 {
            var gain = gainBoost
            vDSP_vsmul(windowedSamples, 1, &gain, &windowedSamples, 1, vDSP_Length(fftSize))
        }

        // Perform FFT
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: fftSize / 2)
        }

        // zrop expects interleaved input: even indices -> realIn, odd indices -> imagIn
        for i in 0..<(fftSize / 2) {
            realIn[i] = windowedSamples[2 * i]
            imagIn[i] = windowedSamples[2 * i + 1]
        }

        vDSP_DFT_Execute(setup, realIn, imagIn, &realPart, &imagPart)

        // Compute magnitudes using DSPSplitComplex
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &magnitudesBuffer, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Normalize
        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudesBuffer, 1, &scale, &magnitudesBuffer, 1, vDSP_Length(fftSize / 2))

        return magnitudesBuffer
    }
    
    /// Converts linear magnitudes to dB scale
    /// - Parameter linearMagnitudes: Linear magnitude values
    /// - Returns: dB magnitude values (20 * log10(magnitude))
    func convertToDB(_ linearMagnitudes: [Float]) -> [Float] {
        var dbMagnitudes = [Float](repeating: -120.0, count: linearMagnitudes.count)
        
        for i in 0..<linearMagnitudes.count {
            let mag = max(linearMagnitudes[i], 1e-10) // Prevent log(0)
            dbMagnitudes[i] = 20.0 * log10(mag)
        }
        
        return dbMagnitudes
    }
    
    /// Converts dB magnitudes back to linear scale
    /// - Parameter dbMagnitudes: dB magnitude values
    /// - Returns: Linear magnitude values
    func convertToLinear(_ dbMagnitudes: [Float]) -> [Float] {
        var linearMagnitudes = [Float](repeating: 0, count: dbMagnitudes.count)
        
        for i in 0..<dbMagnitudes.count {
            linearMagnitudes[i] = pow(10.0, dbMagnitudes[i] / 20.0)
        }
        
        return linearMagnitudes
    }
    
    /// Returns the frequency of a specific FFT bin
    /// - Parameter bin: Bin index
    /// - Returns: Frequency in Hz
    func frequencyForBin(_ bin: Int) -> Float {
        guard bin >= 0 && bin < frequencies.count else { return 0 }
        return frequencies[bin]
    }
    
    /// Returns the bin index for a specific frequency
    /// - Parameter frequency: Frequency in Hz
    /// - Returns: Closest bin index
    func binForFrequency(_ frequency: Float) -> Int {
        let nyquist = Float(sampleRate / 2.0)
        let normalizedFreq = min(max(frequency, 0), nyquist)
        let bin = Int((normalizedFreq / nyquist) * Float(fftSize / 2))
        return min(bin, fftSize / 2 - 1)
    }
}
