import Foundation

/// Selects spectral columns from a stored `.spekto` frame for waterfall / spectrogram playback.
enum WaterfallSpectrogramBins {
    static func bins(
        from frame: MeasurementFrame,
        weighting: FrequencyWeighting,
        preferFullFFT: Bool
    ) -> [Float] {
        if preferFullFFT, !frame.fullFFT.isEmpty {
            return frame.fullFFT
        }
        switch weighting {
        case .z: return frame.thirdOctaveZ
        case .a: return frame.thirdOctaveA
        case .c: return frame.thirdOctaveC
        }
    }
}
