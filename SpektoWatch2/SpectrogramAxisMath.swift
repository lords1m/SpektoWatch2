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

    /// Vertical pixel position for a frequency on the log axis.
    /// 20 Hz sits at the bottom (y = height), 20 kHz at the top (y = 0).
    static func yPosition(for freq: Double, height: CGFloat) -> CGFloat {
        let clamped = max(minFrequency, min(maxFrequency, freq))
        let span = log10(maxFrequency) - log10(minFrequency)
        let normalized = (log10(clamped) - log10(minFrequency)) / span
        return height * (1.0 - CGFloat(normalized))
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
