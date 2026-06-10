import Foundation
import CoreGraphics

/// Pure axis math shared by the spectrogram's frequency- and time-axis
/// overlays. Extracted to a file-level type (was duplicated as private
/// methods in two view structs, with the frequency-label formatting subtly
/// diverging between them) so the math has a single source of truth and is
/// unit-testable.
enum SpectrogramAxisMath {
    static let minFrequency: Double = 20
    static let maxFrequency: Double = 20_000

    /// Vertical pixel position for a frequency on the default log axis
    /// (20 Hz – 20 kHz). 20 Hz sits at the bottom (y = height), 20 kHz at the
    /// top (y = 0). Kept for callers that use the fixed default range.
    static func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        yPosition(for: freq, height: height, scale: .logarithmic,
                  minFrequency: minFrequency, maxFrequency: maxFrequency)
    }

    /// Vertical pixel position for a frequency on a configurable axis.
    /// The low bound sits at the bottom (y = height), the high bound at the top.
    static func yPosition(
        for freq: Double,
        height: CGFloat,
        scale: SpectrogramFrequencyScale,
        minFrequency lo: Double,
        maxFrequency hi: Double
    ) -> CGFloat {
        let loC = max(1e-6, min(lo, hi))
        let hiC = max(loC + 1e-6, hi)
        let clamped = max(loC, min(hiC, freq))
        let normalized: Double
        switch scale {
        case .logarithmic:
            let span = log10(hiC) - log10(loC)
            normalized = span > 0 ? (log10(clamped) - log10(loC)) / span : 0
        case .linear:
            let span = hiC - loC
            normalized = span > 0 ? (clamped - loC) / span : 0
        }
        return height * (1.0 - CGFloat(normalized))
    }

    /// Frequency tick values to label for the given scale/range. Log uses the
    /// canonical octave-ish ladder filtered to the range; linear uses a "nice"
    /// even step so the labels match the uniform bin grid.
    static func axisTickFrequencies(
        scale: SpectrogramFrequencyScale,
        minFrequency lo: Double,
        maxFrequency hi: Double
    ) -> [Double] {
        guard hi > lo else { return [lo] }
        switch scale {
        case .logarithmic:
            let ladder: [Double] = [20, 31.5, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000, 20000]
            var ticks = ladder.filter { $0 >= lo && $0 <= hi }
            if ticks.first != lo { ticks.insert(lo, at: 0) }
            if ticks.last != hi { ticks.append(hi) }
            return ticks
        case .linear:
            let step = linearTickStep(for: hi - lo)
            var ticks: [Double] = []
            var v = (lo / step).rounded(.up) * step
            while v <= hi + 0.5 {
                if v >= lo { ticks.append(v) }
                v += step
            }
            if ticks.first != lo { ticks.insert(lo, at: 0) }
            if ticks.last != hi { ticks.append(hi) }
            return ticks
        }
    }

    /// Picks a "nice" linear tick step yielding roughly 6–10 labels across the span.
    static func linearTickStep(for span: Double) -> Double {
        guard span > 0 else { return 1000 }
        let rough = span / 8.0
        let candidates: [Double] = [100, 200, 250, 500, 1000, 2000, 2500, 5000, 10000]
        for c in candidates where rough <= c { return c }
        return 10000
    }

    /// Frequency tick label. kHz above 1000, integer Hz when whole,
    /// one decimal otherwise (e.g. "31.5").
    static func frequencyLabel(_ freq: Double) -> String {
        if freq >= 1000 {
            return String(format: "%.0f k", freq / 1000)
        } else if freq.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", freq)
        } else {
            return String(format: "%.1f", freq)
        }
    }

    /// Chooses a "nice" time-axis tick spacing that yields roughly four
    /// ticks across the visible range.
    static func xAxisTickStep(for visibleRange: Double) -> Double {
        guard visibleRange > 0 else { return 0.1 }
        let rough = visibleRange / 4.0
        let candidates: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60]
        for c in candidates where rough <= c { return c }
        return 60
    }

    /// Time-axis label: one decimal under 10 s, integer seconds under a
    /// minute, m:ss above.
    static func formatAxisTime(_ seconds: Double) -> String {
        if seconds < 10 { return String(format: "%.1f", seconds) }
        if seconds < 60 { return String(format: "%.0f", seconds) }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
