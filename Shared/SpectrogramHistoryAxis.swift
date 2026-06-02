import Foundation

/// Frequency layout of a precomputed playback spectrogram history matrix.
public enum SpectrogramHistoryAxisKind: Equatable, Sendable {
    case thirdOctave
    case logSpaced
    case linearFFT
}

public enum SpectrogramHistoryAxis {
    public static let thirdOctaveCenterFrequencies: [Float] = [
        20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800,
        1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000
    ]

    public static func hopSize(forFFTSize fftSize: Int) -> Int {
        max(256, fftSize / 8)
    }

    public static func logBinCount(forFFTSize fftSize: Int) -> Int {
        max(64, fftSize / 4)
    }

    public static func infer(
        binCount: Int,
        hasFullFFT: Bool,
        fftBinCount: Int
    ) -> SpectrogramHistoryAxisKind {
        if binCount == MeasurementDataFormat.thirdOctaveBandCount {
            return .thirdOctave
        }
        if hasFullFFT, binCount == fftBinCount {
            return .linearFFT
        }
        if binCount > MeasurementDataFormat.thirdOctaveBandCount {
            return .logSpaced
        }
        return .thirdOctave
    }

    public static func frequencyAxis(
        kind: SpectrogramHistoryAxisKind,
        binCount: Int,
        sampleRate: Double
    ) -> [Float] {
        guard binCount > 0 else { return [] }

        switch kind {
        case .thirdOctave:
            return Array(thirdOctaveCenterFrequencies.prefix(binCount))
        case .linearFFT:
            let nyquist = Float(sampleRate / 2.0)
            let denominator = Float(max(binCount - 1, 1))
            return (0..<binCount).map { Float($0) * nyquist / denominator }
        case .logSpaced:
            let nyquist = Float(sampleRate / 2.0)
            let minFrequency: Float = 20
            let maxFrequency = min(nyquist, 20_000)
            let denominator = Float(max(binCount - 1, 1))
            return (0..<binCount).map { index in
                let t = Float(index) / denominator
                return minFrequency * powf(maxFrequency / minFrequency, t)
            }
        }
    }

    public static func frequency(
        yNorm: Float,
        kind: SpectrogramHistoryAxisKind,
        binCount: Int,
        sampleRate: Double
    ) -> Float {
        let clampedY = max(0, min(1, yNorm))
        let axis = frequencyAxis(kind: kind, binCount: binCount, sampleRate: sampleRate)
        guard !axis.isEmpty else { return 0 }

        switch kind {
        case .thirdOctave, .linearFFT:
            let index = min(binCount - 1, max(0, Int((clampedY * Float(binCount - 1)).rounded())))
            return axis[index]
        case .logSpaced:
            let minFrequency: Float = 20
            let maxFrequency = min(Float(sampleRate / 2.0), 20_000)
            return minFrequency * powf(maxFrequency / minFrequency, clampedY)
        }
    }

    public static func binIndex(
        forFrequency frequency: Float,
        kind: SpectrogramHistoryAxisKind,
        binCount: Int,
        sampleRate: Double
    ) -> Int {
        let axis = frequencyAxis(kind: kind, binCount: binCount, sampleRate: sampleRate)
        guard !axis.isEmpty else { return 0 }
        return nearestIndex(for: frequency, in: axis)
    }

    public static func binIndex(
        yNorm: Float,
        kind: SpectrogramHistoryAxisKind,
        binCount: Int,
        sampleRate: Double
    ) -> Int {
        let frequency = frequency(yNorm: yNorm, kind: kind, binCount: binCount, sampleRate: sampleRate)
        return binIndex(forFrequency: frequency, kind: kind, binCount: binCount, sampleRate: sampleRate)
    }

    private static func nearestIndex(for frequency: Float, in axis: [Float]) -> Int {
        guard !axis.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, candidate) in axis.enumerated() {
            let distance = abs(candidate - frequency)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
