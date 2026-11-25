import Foundation
import Observation

/// Live acoustic measurements published from the AudioEngine.
@Observable
final class LiveAcousticState {

    // MARK: - Broadband + history

    /// Current calibrated broadband level in dB SPL.
    var currentLevel: Float = -120.0
    /// Session-max broadband level. Reset by callers when starting a
    /// new measurement.
    var maxLevel: Float = -120.0
    /// Session-min broadband level. Reset by callers when starting a
    /// new measurement.
    var minLevel: Float = -120.0
    /// Rolling history of `currentLevel`, used by the LAF graph and
    /// recordings.
    var levelHistory: [Float] = []
    /// Current peak level (LCpeak / LAFmax depending on caller).
    var currentPeakLevel: Float = -120.0

    // MARK: - Spectral

    /// Latest spectrogram frame (mags + frequencies + per-weighting
    /// levels). Updated at ~15 Hz.
    var currentSpectrogramData: SpectrogramData?
    /// Third-octave bands per weighting — driven independently so a
    /// widget can pick a weighting that differs from the engine
    /// default.
    var currentOctaveBandsZ: [Float] = Array(repeating: -120.0, count: 31)
    var currentOctaveBandsA: [Float] = Array(repeating: -120.0, count: 31)
    var currentOctaveBandsC: [Float] = Array(repeating: -120.0, count: 31)

    /// Per-band Leq (31 third-octave), EMA-smoothed in the metrics layer.
    /// Updated at the UI rate (~15 Hz). Widgets use these instead of
    /// maintaining their own @State EMA.
    var bandLeqZ: [Float] = Array(repeating: -120.0, count: 31)
    var bandLeqA: [Float] = Array(repeating: -120.0, count: 31)
    var bandLeqC: [Float] = Array(repeating: -120.0, count: 31)
    /// Octave-band Leq (10 bands), derived from `bandLeq*` in the engine.
    var bandLeqOctaveZ: [Float] = []
    var bandLeqOctaveA: [Float] = []
    var bandLeqOctaveC: [Float] = []

    /// Pre-aggregated Bark bands (24 critical bands).
    /// Empty when no widget requests Bark mode — zero-cost in that case.
    /// Populated by `AudioEngine.processFFTFrame` when
    /// `widgetBarkBandsRequired` is set via `setWidgetBarkBandsRequired(_:)`.
    var currentBarkBandsZ: [Float] = []
    var currentBarkBandsA: [Float] = []
    var currentBarkBandsC: [Float] = []

    // MARK: - Stereo

    /// Current L↔R correlation in [-1, +1].
    var currentStereoPhase: Float = 1.0
    /// True when the active input has two or more channels.
    var isStereoActive: Bool = false
}
