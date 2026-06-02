import Foundation

/// Detects whether a measurement sidecar contains usable third-octave spectra
/// (legacy watch recordings wrote zero-filled bands).
public enum MeasurementSpectralAvailability {
    /// Terzband-Pegel unterhalb dieses Schwellwerts gelten als „leer“ (Legacy-Watch schrieb 0.0).
    private static let signalThresholdDB: Float = 15

    /// Probes a small set of frames spread across the file.
    public static func hasUsableSpectralData(fileURL: URL, maxFramesToProbe: Int = 8) -> Bool {
        guard let reader = try? MeasurementDataReader(fileURL: fileURL),
              reader.frameCount > 0 else {
            return false
        }

        for index in probeIndices(frameCount: reader.frameCount, maxSamples: maxFramesToProbe) {
            guard let frame = try? reader.readFrameSummary(at: index) else { continue }
            if bandsContainSignal(frame.thirdOctaveZ)
                || bandsContainSignal(frame.thirdOctaveA)
                || bandsContainSignal(frame.thirdOctaveC) {
                return true
            }
        }
        return false
    }

    private static func bandsContainSignal(_ bands: [Float]) -> Bool {
        bands.contains { $0 > signalThresholdDB }
    }

    private static func probeIndices(frameCount: Int, maxSamples: Int) -> [Int] {
        guard frameCount > 0 else { return [] }
        if frameCount <= maxSamples {
            return Array(0..<frameCount)
        }

        var indices: Set<Int> = [0, frameCount - 1]
        let interior = max(0, maxSamples - 2)
        if interior > 0 {
            let denominator = Double(interior + 1)
            for slot in 1...interior {
                let position = Double(slot) / denominator
                indices.insert(Int((position * Double(frameCount - 1)).rounded()))
            }
        }
        return indices.sorted()
    }
}
