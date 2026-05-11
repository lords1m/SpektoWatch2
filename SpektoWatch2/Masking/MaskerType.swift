import Foundation

// Available masking textures. Each carries a pre-computed 1/3-octave natural spectrum
// (31 values, dB relative to the 1 kHz band = 0 dB) used for masker selection.
enum MaskerType: String, CaseIterable, Codable, Identifiable {
    case pinkNoise
    case brownNoise
    case whiteNoise
    case rain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinkNoise:  return "Rosa Rauschen"
        case .brownNoise: return "Braunes Rauschen"
        case .whiteNoise: return "Weißes Rauschen"
        case .rain:       return "Regen"
        }
    }

    var isAssetBased: Bool {
        switch self {
        case .rain: return true
        default:    return false
        }
    }

    // Pre-computed 1/3-octave spectrum in dB relative to the 1 kHz band.
    // Analytical derivations (see plan):
    //   Pink  (1/f):   constant power per 1/3-oct band → flat
    //   Brown (1/f²):  power ∝ 1/f_center → -10 log10(f/1000)
    //   White (flat PSD): power ∝ f_center bandwidth → +10 log10(f/1000)
    //   Rain:          empirical approximation, broad peak 250 Hz – 2 kHz
    var naturalSpectrum: [Float] {
        let centers = TriggerSpectrum.bandCenters
        switch self {
        case .pinkNoise:
            return [Float](repeating: 0.0, count: TriggerSpectrum.bandCount)

        case .brownNoise:
            return centers.map { f in -10.0 * log10(f / 1000.0) }

        case .whiteNoise:
            return centers.map { f in 10.0 * log10(f / 1000.0) }

        case .rain:
            // Roughly pink-noise shaped with a +3 dB bump 250 Hz–2 kHz
            // and a steep rolloff above 4 kHz.
            return centers.map { f in
                let fLog = log10(f / 1000.0)
                let bump: Float = {
                    if f >= 250 && f <= 2000 { return 3.0 }
                    return 0.0
                }()
                let hiRolloff: Float = f > 4000 ? -10.0 * log10(f / 4000.0) : 0.0
                let loRolloff: Float = f < 100  ?  -6.0 * log10(100.0 / f)  : 0.0
                return -fLog * 2.0 + bump + hiRolloff + loRolloff
            }
        }
    }
}

// Trigger preset: a pre-analysed TriggerSpectrum for common ADHD/misophonia sounds.
// Stored as spectral shape (net dB relative to peak band).
struct TriggerPreset: Identifiable {
    let id: String
    let displayName: String
    let spectrum: TriggerSpectrum

    static let library: [TriggerPreset] = [
        .make(id: "keyboard",
              name: "Tastatur-Tippen",
              // Energy concentrated 1–3 kHz; low-energy lows and soft highs
              shapeFn: { f in
                  if f < 100  { return -20.0 }
                  if f < 300  { return -12.0 + 4.0 * log10(f / 100.0) }
                  if f < 800  { return  -6.0 + 3.0 * log10(f / 300.0) }
                  if f < 3000 { return   0.0 - 2.0 * log10(f / 800.0) }
                  return -6.0 - 8.0 * log10(f / 3000.0)
              }),
        .make(id: "pen_click",
              name: "Kugelschreiber klacken",
              // Sharp transient, peaks 2–5 kHz
              shapeFn: { f in
                  if f < 200  { return -25.0 }
                  if f < 500  { return -15.0 }
                  if f < 2000 { return  -5.0 + 2.5 * log10(f / 500.0) }
                  if f < 5000 { return   0.0 - 1.0 * log10(f / 2000.0) }
                  return -8.0 - 10.0 * log10(f / 5000.0)
              }),
        .make(id: "chewing",
              name: "Kauen / Schmatzen",
              // Wet low-mid sound, 300 Hz – 2 kHz
              shapeFn: { f in
                  if f < 100  { return -18.0 }
                  if f < 300  { return  -8.0 + 5.0 * log10(f / 100.0) }
                  if f < 1500 { return   0.0 }
                  if f < 4000 { return  -4.0 * log10(f / 1500.0) }
                  return -12.0 - 8.0 * log10(f / 4000.0)
              }),
        .make(id: "hvac",
              name: "Klimaanlage / Lüftung",
              // Tonal hum, dominant 50–200 Hz
              shapeFn: { f in
                  if f < 50   { return  -3.0 }
                  if f < 200  { return   0.0 }
                  if f < 500  { return  -6.0 * log10(f / 200.0) }
                  return -14.0 - 6.0 * log10(f / 500.0)
              }),
        .make(id: "chair_creak",
              name: "Stuhl knarren",
              // Impulse burst 200–800 Hz
              shapeFn: { f in
                  if f < 100  { return -15.0 }
                  if f < 200  { return  -8.0 + 4.0 * log10(f / 100.0) }
                  if f < 800  { return   0.0 }
                  if f < 2000 { return  -5.0 * log10(f / 800.0) }
                  return -14.0 - 6.0 * log10(f / 2000.0)
              }),
    ]

    private static func make(id: String, name: String, shapeFn: (Float) -> Float) -> TriggerPreset {
        let bands = TriggerSpectrum.bandCenters.map(shapeFn)
        let peakIdx = bands.indices.max(by: { bands[$0] < bands[$1] }) ?? 0
        let spectrum = TriggerSpectrum(
            bands: bands,
            stdDev: [Float](repeating: 0, count: TriggerSpectrum.bandCount),
            peakBandIndex: peakIdx,
            totalRMSdB: -30.0,
            acquisitionMode: .preset,
            captureCount: 1,
            ambientBands: nil
        )
        return TriggerPreset(id: id, displayName: name, spectrum: spectrum)
    }
}
