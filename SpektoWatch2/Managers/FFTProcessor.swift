import Foundation
import Accelerate

/// Handles all FFT-related calculations including windowing and magnitude extraction
class FFTProcessor {
    
    // MARK: - Properties
    
    private let fftSize: Int
    private let fftSetup: vDSP_DFT_Setup
    private let sampleRate: Double
    
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var window: [Float]
    private var fftMagnitudes: [Float]
    
    // MARK: - Initialization
    
    init(fftSize: Int = 8192, sampleRate: Double = 44100.0) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        
        guard let setup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(fftSize),
            vDSP_DFT_Direction.FORWARD
        ) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup
        
        // Initialize buffers
        realIn = [Float](repeating: 0, count: fftSize)
        imagIn = [Float](repeating: 0, count: fftSize)
        realOut = [Float](repeating: 0, count: fftSize)
        imagOut = [Float](repeating: 0, count: fftSize)
        window = [Float](repeating: 0, count: fftSize)
        fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        
        // Create Hann window
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    // MARK: - Public Methods
    
    /// Performs FFT on input samples and returns frequencies and magnitudes in dB
    /// - Parameters:
    ///   - samples: Input audio samples
    ///   - gainBoost: Gain boost in dB to apply to magnitudes
    /// - Returns: Tuple of frequencies (Hz) and magnitudes (dB)
    func performFFT(on samples: [Float], gainBoost: Float = 0.0) -> (frequencies: [Float], magnitudes: [Float]) {
        // Clear imaginary input
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))
        
        // Apply window to samples
        let maxIndex = min(samples.count, fftSize)
        for i in 0..<maxIndex {
            realIn[i] = samples[i] * window[i]
        }
        
        // Perform FFT
        vDSP_DFT_Execute(fftSetup,
                         realIn, imagIn,
                         &realOut, &imagOut)
        
        // Calculate magnitudes
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Normalize and apply gain boost
        let normalization = 2.0 / Float(fftSize)
        var scale = normalization * pow(10.0, gainBoost / 20.0)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        
        // Convert to dB
        var epsilon: Float = 1e-9
        vDSP_vsadd(fftMagnitudes, 1, &epsilon, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        var reference: Float = 1.0
        var dbMagnitudes = [Float](repeating: 0, count: fftMagnitudes.count)
        vDSP_vdbcon(fftMagnitudes, 1, &reference, &dbMagnitudes, 1, vDSP_Length(fftMagnitudes.count), 1)
        
        // Calculate frequencies
        let frequencies = calculateFrequencies()
        
        return (frequencies, dbMagnitudes)
    }
    
    /// Returns the raw FFT magnitudes (linear scale) for energy calculations
    func getRawMagnitudes() -> [Float] {
        return fftMagnitudes
    }
    
    // MARK: - Private Methods
    
    private func calculateFrequencies() -> [Float] {
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize / 2)
        return (0..<(fftSize / 2)).map { Float($0) * freqResolution }
    }
    
    // MARK: - Utility Methods
    
    /// Aggregates frequency bins by a binning factor
    func aggregateByBinning(
        frequencies: [Float],
        magnitudes: [Float],
        binningFactor: Int
    ) -> (frequencies: [Float], magnitudes: [Float]) {
        
        guard binningFactor > 1 else {
            return (frequencies, magnitudes)
        }
        
        var bandFrequencies: [Float] = []
        var bandMagnitudes: [Float] = []
        
        var i = 0
        while i < frequencies.count {
            let endIndex = min(i + binningFactor, frequencies.count)
            let binCount = endIndex - i
            
            // Average frequency
            let centerFreq = frequencies[i..<endIndex].reduce(0, +) / Float(binCount)
            bandFrequencies.append(centerFreq)
            
            // Average magnitude
            let centerMag = magnitudes[i..<endIndex].reduce(0, +) / Float(binCount)
            bandMagnitudes.append(centerMag)
            
            i = endIndex
        }
        
        return (bandFrequencies, bandMagnitudes)
    }
    
    /// Calculates 1/3 octave bands from FFT results
    func calculateOctaveBands(frequencies: [Float], magnitudes: [Float]) -> [Float] {
        let centerFreqs: [Float] = [
            20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
            1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
        ]
        
        var bands = [Float](repeating: -120.0, count: centerFreqs.count)
        
        for (i, center) in centerFreqs.enumerated() {
            let lower = center * 0.89
            let upper = center * 1.12
            
            let nyquist = Float(sampleRate / 2.0)
            let resolution = nyquist / Float(magnitudes.count)
            
            let startIdx = Int(lower / resolution)
            let endIdx = Int(upper / resolution)
            
            if startIdx < magnitudes.count {
                let safeEnd = min(endIdx, magnitudes.count - 1)
                if startIdx <= safeEnd {
                    let bandMax = magnitudes[startIdx...safeEnd].max() ?? -120.0
                    bands[i] = bandMax
                }
            }
        }
        
        return bands
    }
}
