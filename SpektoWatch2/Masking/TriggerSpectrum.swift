import Foundation

// Spectral fingerprint of a disturbing sound, built from one or more captured moments.
// Uses the same 31 third-octave band centers as AudioEngine.thirdOctaveCenters.
struct TriggerSpectrum: Codable, Equatable {

    static let bandCenters: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
        200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300,
        8000, 10000, 12500, 16000, 20000
    ]
    static let bandCount = 31
    static let noiseFloor: Float = -120.0   // dBFS

    // Mean level per band in dB (dB SPL from AudioEngine, same scale throughout)
    var bands: [Float]
    // Standard deviation per band across all captures
    var stdDev: [Float]
    // Index of the band with the highest mean energy
    var peakBandIndex: Int
    // Overall broadband level at capture time (dB)
    var totalRMSdB: Float
    var acquisitionMode: AcquisitionMode
    // Number of individual tap-marks averaged into this spectrum
    var captureCount: Int
    // Ambient spectrum recorded before trigger captures (optional)
    var ambientBands: [Float]?

    // Trigger spectrum with ambient removed (linear subtraction, clamped to noise floor).
    // Use this for masker selection and EQ computation.
    var netBands: [Float] {
        guard let ambient = ambientBands else { return bands }
        return zip(bands, ambient).map { tDB, aDB in
            let tLin = pow(10.0, tDB / 20.0)
            let aLin = pow(10.0, aDB / 20.0)
            let net  = max(tLin - aLin, pow(10.0, Self.noiseFloor / 20.0))
            return 20.0 * log10(net)
        }
    }

    // L1-norm based convergence score [0…1].
    // Returns values near 1 when two spectra are nearly identical.
    static func convergence(between a: [Float], and b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let l1diff = zip(a, b).reduce(0.0 as Float) { $0 + abs($1.0 - $1.1) }
        let l1a    = a.reduce(0.0 as Float) { $0 + abs($1) }
        guard l1a > 0 else { return 0 }
        return max(0, min(1, 1.0 - l1diff / l1a))
    }
}

enum AcquisitionMode: String, Codable {
    case tapToMark       // user held "Das war es" button
    case liveRecording   // classic manual record
    case preset          // built-in trigger library
    case fileImport      // imported audio file
}
