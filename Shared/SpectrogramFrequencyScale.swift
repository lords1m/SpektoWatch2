import Foundation

/// User-facing spectrogram frequency-axis scale.
///
/// - `.logarithmic`: equal musical intervals get equal vertical space (default).
///   Low frequencies are emphasised; FFT-bin rows are unevenly tall (tall at the
///   bottom, thin at the top).
/// - `.linear`: equal Hz steps get equal vertical space, so the underlying
///   linearly-spaced FFT bins render with uniform row height. Trades away
///   low-frequency emphasis for an even bin grid.
public enum SpectrogramFrequencyScale: String, CaseIterable, Identifiable, Sendable {
    case logarithmic
    case linear

    public var id: String { rawValue }

    public var germanTitle: String {
        switch self {
        case .logarithmic: return "Logarithmisch"
        case .linear: return "Linear"
        }
    }

    public var germanDetail: String {
        switch self {
        case .logarithmic:
            return "Gleiche Oktaven gleich hoch — betont tiefe Frequenzen"
        case .linear:
            return "Gleiche Hz-Schritte gleich hoch — gleichmäßige Bin-Abstände"
        }
    }

    public static let defaultValue: SpectrogramFrequencyScale = .logarithmic

    public static var current: SpectrogramFrequencyScale {
        let raw = UserDefaults.standard.string(forKey: PersistenceKeys.spectrogramFrequencyScale)
        return SpectrogramFrequencyScale(rawValue: raw ?? "") ?? .defaultValue
    }

    public static func save(_ scale: SpectrogramFrequencyScale) {
        guard scale != current else { return }
        UserDefaults.standard.set(scale.rawValue, forKey: PersistenceKeys.spectrogramFrequencyScale)
        NotificationCenter.default.post(
            name: .spectrogramFrequencyScaleChanged,
            object: scale
        )
    }
}

/// Lower/upper bound of the displayed spectrogram frequency range, in Hz.
///
/// Persisted as two `Double` values. The default upper bound is microphone-
/// dependent: it is clamped to the Nyquist frequency of the active processing
/// sample rate (e.g. a 44.1 kHz mic tops out at ~22 kHz, but the display default
/// is 20 kHz), while the user can narrow or widen it freely within the device's
/// physical limits.
public struct SpectrogramFrequencyRange: Equatable, Sendable {
    public var minHz: Double
    public var maxHz: Double

    public init(minHz: Double, maxHz: Double) {
        self.minHz = minHz
        self.maxHz = maxHz
    }

    /// Hard limits the UI/renderer should never exceed.
    public static let absoluteMin: Double = 1
    public static let absoluteMax: Double = 24_000

    /// Default display range for a given microphone sample rate. The lower bound
    /// stays at 20 Hz (typical mic roll-off); the upper bound is the smaller of
    /// 20 kHz and the mic's Nyquist frequency.
    public static func microphoneDefault(sampleRate: Double) -> SpectrogramFrequencyRange {
        let nyquist = max(1_000, sampleRate / 2.0)
        return SpectrogramFrequencyRange(minHz: 20, maxHz: min(20_000, nyquist))
    }

    /// Clamp to sane bounds and enforce `min < max` with at least a half-octave
    /// of separation so the axis never collapses.
    public func sanitized(nyquist: Double) -> SpectrogramFrequencyRange {
        let upperLimit = min(SpectrogramFrequencyRange.absoluteMax, max(2_000, nyquist))
        var lo = max(SpectrogramFrequencyRange.absoluteMin, min(minHz, upperLimit - 1))
        var hi = min(upperLimit, max(maxHz, lo + 1))
        // Keep at least a 1.2× ratio so log mapping stays well-conditioned.
        if hi < lo * 1.2 {
            hi = min(upperLimit, lo * 1.2)
            lo = min(lo, hi / 1.2)
        }
        return SpectrogramFrequencyRange(minHz: lo, maxHz: hi)
    }

    public static func current(sampleRate: Double) -> SpectrogramFrequencyRange {
        let defaults = UserDefaults.standard
        let fallback = microphoneDefault(sampleRate: sampleRate)
        let lo = defaults.object(forKey: PersistenceKeys.spectrogramMinFrequency) as? Double ?? fallback.minHz
        let hi = defaults.object(forKey: PersistenceKeys.spectrogramMaxFrequency) as? Double ?? fallback.maxHz
        return SpectrogramFrequencyRange(minHz: lo, maxHz: hi).sanitized(nyquist: sampleRate / 2.0)
    }
}
