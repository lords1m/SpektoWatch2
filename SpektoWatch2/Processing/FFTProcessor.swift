import Foundation
import Accelerate

class FFTProcessor {
    let fftSize: Int
    let sampleRate: Double
    
    private let fftSetup: vDSP_DFT_Setup
    private var window: [Float]
    private var realIn: [Float]
    private var imagIn: [Float]
    private var realOut: [Float]
    private var imagOut: [Float]
    private var fftMagnitudes: [Float]
    
    // Cache frequencies for mapping
    lazy var frequencies: [Float] = {
        let nyquist = Float(sampleRate / 2.0)
        let freqResolution = nyquist / Float(fftSize / 2)
        return (0..<(fftSize / 2)).map { Float($0) * freqResolution }
    }()

    init(fftSize: Int, sampleRate: Double) {
        self.fftSize = fftSize
        self.sampleRate = sampleRate
        
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), vDSP_DFT_Direction.FORWARD) else {
            fatalError("Failed to create FFT setup")
        }
        self.fftSetup = setup
        
        self.realIn = [Float](repeating: 0, count: fftSize)
        self.imagIn = [Float](repeating: 0, count: fftSize)
        self.realOut = [Float](repeating: 0, count: fftSize)
        self.imagOut = [Float](repeating: 0, count: fftSize)
        self.window = [Float](repeating: 0, count: fftSize)
        self.fftMagnitudes = [Float](repeating: 0, count: fftSize / 2)
        
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
    }
    
    deinit {
        vDSP_DFT_DestroySetup(fftSetup)
    }
    
    /// Performs FFT on the provided samples and returns linear magnitudes.
    func performFFT(on samples: [Float], gainBoost: Float) -> [Float] {
        // Clear imaginary input
        vDSP_vclr(&imagIn, 1, vDSP_Length(fftSize))
        
        // Handle sample count (zero pad if necessary)
        let count = min(samples.count, fftSize)
        
        // Apply window and copy to realIn
        if count > 0 {
            vDSP_vmul(samples, 1, window, 1, &realIn, 1, vDSP_Length(count))
        }
        
        // Zero pad the rest of realIn
        if count < fftSize {
            realIn.withUnsafeMutableBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    vDSP_vclr(base.advanced(by: count), 1, vDSP_Length(fftSize - count))
                }
            }
        }
        
        // Execute FFT
        vDSP_DFT_Execute(fftSetup, realIn, imagIn, &realOut, &imagOut)
        
        // Calculate Magnitudes (DSPSplitComplex -> Float array)
        realOut.withUnsafeMutableBufferPointer { realPtr in
            imagOut.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&splitComplex, 1, &fftMagnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }
        
        // Scaling (Normalization + Gain Boost)
        // Normalization factor for DFT is 2/N (for magnitude)
        let normalization = 2.0 / Float(fftSize)
        var scale = normalization * pow(10.0, gainBoost / 20.0)
        vDSP_vsmul(fftMagnitudes, 1, &scale, &fftMagnitudes, 1, vDSP_Length(fftMagnitudes.count))
        
        return fftMagnitudes
    }
    
    /// Converts linear magnitudes to dB.
    func convertToDB(_ magnitudes: [Float]) -> [Float] {
        var dbMagnitudes = [Float](repeating: 0, count: magnitudes.count)
        
        // Add epsilon to avoid log(0)
        var epsilon: Float = 1e-9
        var tempMags = magnitudes
        vDSP_vsadd(tempMags, 1, &epsilon, &tempMags, 1, vDSP_Length(tempMags.count))
        
        var reference: Float = 1.0
        // vDSP_vdbcon: Power/Amplitude to Decibels
        // 0 = power (10*log10), 1 = amplitude (20*log10)
        vDSP_vdbcon(tempMags, 1, &reference, &dbMagnitudes, 1, vDSP_Length(tempMags.count), 1)
        
        return dbMagnitudes
    }
}