import Foundation
import Accelerate

/// Handles FFT computation and magnitude conversion
class FFTProcessor {
    private let fftSize: Int
    private let sampleRate: Double
    private var fftSetup: vDSP_DFT_Setup?
    
    // Pre-allocated buffers for performance
    private var window: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    
    /// Frequency array corresponding to FFT bins
    private(set) var frequencies: [Float]
    
    // MARK: - Initialization
    
    init(fftSize: Int, sampleRate: Double) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        
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
        
        // Create Hann window
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        
        // Compute frequency bins
        let nyquist = Float(sampleRate / 2.0)
        let binCount = fftSize / 2
        self.frequencies = (0..<binCount).map { Float($0) * nyquist / Float(binCount) }
    }
    
    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }
    
    // MARK: - FFT Processing
    
    /// Performs FFT and returns linear magnitudes
    /// - Parameters:
    ///   - samples: Time-domain samples (must be fftSize length)
    ///   - gainBoost: Gain multiplier to apply before FFT
    /// - Returns: Array of linear magnitude values (fftSize/2 length)
    func performFFT(on samples: [Float], gainBoost: Float = 1.0) -> [Float] {
        guard samples.count >= fftSize else {
            return [Float](repeating: 0, count: fftSize / 2)
        }
        
        // Apply window and gain
        var windowed = [Float](repeating: 0, count: fftSize)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        
        if gainBoost != 1.0 {
            var gain = gainBoost
            vDSP_vsmul(windowed, 1, &gain, &windowed, 1, vDSP_Length(fftSize))
        }
        
        // Perform FFT
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: fftSize / 2)
        }

        // zrop expects interleaved input: even indices -> realIn, odd indices -> imagIn
        for i in 0..<(fftSize / 2) {
            realIn[i] = windowed[2 * i]
            imagIn[i] = windowed[2 * i + 1]
        }

        vDSP_DFT_Execute(setup, realIn, imagIn, &realPart, &imagPart)

        // Compute magnitudes using DSPSplitComplex
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Normalize
        var scale = 2.0 / Float(fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))
        
        return magnitudes
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
