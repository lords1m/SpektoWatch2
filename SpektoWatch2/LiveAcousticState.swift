import Combine
import Foundation

/// Live acoustic measurements published from the AudioEngine.
///
/// Extracted from `AudioEngine` as part of M13 task-4 to give views
/// a narrower observation scope. Today the AudioEngine bridges this
/// child's `objectWillChange` to its own so existing
/// `@ObservedObject var audioEngine` consumers keep updating
/// transparently — no consumer migration was required to land this
/// extraction.
///
/// The actual re-render breadth win comes when individual widgets
/// migrate from `@ObservedObject var audioEngine: AudioEngine` to
/// `@ObservedObject var live = audioEngine.live`. That migration is
/// per-widget and can ship incrementally; this file is the
/// prerequisite seam. See the task-4 doc for the migration plan.
final class LiveAcousticState: ObservableObject {

    // MARK: - Broadband + history

    /// Current calibrated broadband level in dB SPL.
    @Published var currentLevel: Float = -120.0
    /// Session-max broadband level. Reset by callers when starting a
    /// new measurement.
    @Published var maxLevel: Float = -120.0
    /// Session-min broadband level. Reset by callers when starting a
    /// new measurement.
    @Published var minLevel: Float = -120.0
    /// Rolling history of `currentLevel`, used by the LAF graph and
    /// recordings.
    @Published var levelHistory: [Float] = []
    /// Current peak level (LCpeak / LAFmax depending on caller).
    @Published var currentPeakLevel: Float = -120.0

    // MARK: - Spectral

    /// Latest spectrogram frame (mags + frequencies + per-weighting
    /// levels). Updated at ~15 Hz.
    @Published var currentSpectrogramData: SpectrogramData?
    /// Latest broadband spectrum (mirrors `currentSpectrogramData.magnitudes`).
    /// Kept as a separate publish for widgets that want the bare
    /// spectrum array.
    @Published var currentSpectrum: [Float] = []
    /// Active third-octave bands matching the engine's current
    /// frequency weighting.
    @Published var currentOctaveBands: [Float] = Array(repeating: -120.0, count: 31)
    /// Third-octave bands per weighting — driven independently so a
    /// widget can pick a weighting that differs from the engine
    /// default.
    @Published var currentOctaveBandsZ: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentOctaveBandsA: [Float] = Array(repeating: -120.0, count: 31)
    @Published var currentOctaveBandsC: [Float] = Array(repeating: -120.0, count: 31)

    // MARK: - Stereo

    /// Current L↔R correlation in [-1, +1].
    @Published var currentStereoPhase: Float = 1.0
    /// True when the active input has two or more channels.
    @Published var isStereoActive: Bool = false
}
