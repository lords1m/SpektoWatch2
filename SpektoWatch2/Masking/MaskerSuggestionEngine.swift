import Foundation

// Selects the best masker for a given TriggerSpectrum and computes a 3-band EQ correction.
//
// Algorithm:
//   1. Compute cosine distance on log-spectrum between trigger and each masker's natural spectrum.
//   2. Pick the masker with the smallest distance (best spectral shape match).
//   3. For each 1/3-octave band, compute how much gain the masker needs to exceed the
//      trigger by 6 dB (psychoacoustic masking threshold estimate).
//   4. Collapse the 31 per-band gains into 3 parametric EQ bands for MVP.
//
// All inputs in dB (same scale as AudioEngine octave bands).

struct MaskerSuggestionEngine {

    // MARK: – Public entry point

    static func suggest(for trigger: TriggerSpectrum) -> MaskerSuggestion {
        let sourceBands = trigger.netBands    // use ambient-subtracted spectrum if available

        // 1. Select masker via cosine distance on log-spectrum
        let best = bestMasker(for: sourceBands)

        // 2. Normalise trigger to peak = 0 before EQ computation.
        //    netBands is in absolute dBFS; naturalSpectrum is relative (1 kHz = 0 dB).
        //    Without normalisation the subtraction in perBandGains produces nonsense gains.
        let peak = sourceBands.max() ?? TriggerSpectrum.noiseFloor
        let normBands = sourceBands.map { max($0 - peak, TriggerSpectrum.noiseFloor) }

        // 3. Compute per-band gain correction
        let rawGains = perBandGains(trigger: normBands, masker: best.masker)

        // 3. Collapse to 3 EQ bands
        let eqBands = collapseToThreeBands(gains: rawGains)

        // 4. Safe initial volume: trigger level + 6 dB headroom – 6 dB safety, cap at –10 dBFS
        let safeVolume = min(trigger.totalRMSdB + 6.0 - 6.0, -10.0)

        return MaskerSuggestion(
            maskerType: best.masker,
            eqBands: eqBands,
            volumedBFS: safeVolume,
            confidenceScore: 1.0 - best.distance   // distance 0 = perfect match
        )
    }

    // MARK: – Masker selection

    private struct RankedMasker {
        let masker: MaskerType
        let distance: Float
    }

    private static func bestMasker(for triggerBands: [Float]) -> RankedMasker {
        let logTrigger = logSpectrum(triggerBands)

        var best = RankedMasker(masker: .pinkNoise, distance: .infinity)
        for masker in MaskerType.allCases {
            let logNatural = logSpectrum(masker.naturalSpectrum)
            let dist = cosineDistance(logTrigger, logNatural)
            if dist < best.distance {
                best = RankedMasker(masker: masker, distance: dist)
            }
        }
        return best
    }

    // MARK: – Per-band gain

    private static func perBandGains(trigger: [Float], masker: MaskerType) -> [Float] {
        let natural = masker.naturalSpectrum
        // We want masker_output[b] ≥ trigger[b] + 6 dB
        // masker_output[b] = natural[b] + gain[b]
        // → gain[b] = trigger[b] + 6 - natural[b]
        let gains = zip(trigger, natural).map { t, n in
            let needed = t + 6.0 - n
            return max(-12.0, min(12.0, needed))   // clamp to ±12 dB
        }
        return gains
    }

    // MARK: – 3-band collapse (MVP)

    // Band split for 31 third-octave centers (20 Hz – 20 kHz):
    //   Low  (indices  0–10):  20–200 Hz   → Low Shelf  @ 200 Hz
    //   Mid  (indices 11–22): 250–3150 Hz  → Peak       @ 1000 Hz, Q = 1.0
    //   High (indices 23–30): 4000–20000 Hz → High Shelf @ 4000 Hz
    private static func collapseToThreeBands(gains: [Float]) -> [EQBand] {
        let lowGain  = averageGains(gains, indices: Array(0...10))
        let midGain  = averageGains(gains, indices: Array(11...22))
        let highGain = averageGains(gains, indices: Array(23...30))

        return [
            EQBand(type: .lowShelf,  frequency: 200,  q: 0.7, gainDB: lowGain),
            EQBand(type: .peak,      frequency: 1000, q: 1.0, gainDB: midGain),
            EQBand(type: .highShelf, frequency: 4000, q: 0.7, gainDB: highGain),
        ]
    }

    private static func averageGains(_ gains: [Float], indices: [Int]) -> Float {
        let values = indices.compactMap { $0 < gains.count ? gains[$0] : nil }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }

    // MARK: – Math helpers

    // Log-spectrum with noise floor clamping to avoid log(0).
    private static func logSpectrum(_ bandsDB: [Float]) -> [Float] {
        // bandsDB are already in dB; take log10 of linear amplitude for cosine distance.
        // Clamp at noise floor before converting.
        return bandsDB.map { db in
            let clamped = max(db, TriggerSpectrum.noiseFloor)
            return log10(pow(10.0, clamped / 20.0))   // = clamped / 20  (log10 of linear amp)
        }
    }

    // Cosine distance ∈ [0, 2]; 0 = identical directions, 2 = opposite.
    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 2.0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot   += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 2.0 }
        return 1.0 - dot / denom
    }
}
