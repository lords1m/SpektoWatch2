import Foundation

/// Two-axis navigation window over a precomputed spectrogram.
///
/// All coordinates are normalized to `[0, 1]`:
/// - Time: `0` = start of recording, `1` = end.
/// - Frequency: `0` = lowest bin (bottom of the rendered image), `1` = highest
///   bin (top). This matches the texture-row convention used by
///   `PlaybackSpectrogramRenderer` and `SpectrogramHistoryAxis.frequency(yNorm:…)`.
///
/// The viewport is a clamped value type so gestures stay inside the recording
/// and never invert. Zoom is anchored at a focal point so pinch-to-zoom keeps
/// the point under the user's fingers stationary.
struct SpectrogramViewport: Equatable {
    /// Normalized start of the visible time window (`0…1`).
    var timeStart: Float
    /// Normalized width of the visible time window (`0…1`).
    var timeWidth: Float
    /// Normalized start of the visible frequency window, measured from the
    /// bottom (low frequency).
    var freqStart: Float
    /// Normalized height of the visible frequency window.
    var freqWidth: Float

    /// Smallest allowed time window — caps how far the user can zoom in.
    var minTimeWidth: Float = 0.004
    /// Smallest allowed frequency window.
    var minFreqWidth: Float = 0.06

    static let full = SpectrogramViewport(timeStart: 0, timeWidth: 1, freqStart: 0, freqWidth: 1)

    var isFitted: Bool {
        timeStart <= 0.0001 && timeWidth >= 0.9999 &&
        freqStart <= 0.0001 && freqWidth >= 0.9999
    }

    var timeEnd: Float { timeStart + timeWidth }
    var freqEnd: Float { freqStart + freqWidth }

    // MARK: - Mutation

    /// Clamps both windows back into `[0, 1]` with their minimum widths.
    mutating func clamp() {
        timeWidth = min(max(timeWidth, minTimeWidth), 1)
        freqWidth = min(max(freqWidth, minFreqWidth), 1)
        timeStart = min(max(timeStart, 0), 1 - timeWidth)
        freqStart = min(max(freqStart, 0), 1 - freqWidth)
    }

    /// Zooms the time axis by `factor` (`< 1` zooms in) keeping the global
    /// position under `focus` (a `0…1` fraction across the visible window)
    /// stationary.
    mutating func zoomTime(by factor: Float, focus: Float) {
        let focusGlobal = timeStart + max(0, min(1, focus)) * timeWidth
        timeWidth = min(max(timeWidth * factor, minTimeWidth), 1)
        timeStart = focusGlobal - max(0, min(1, focus)) * timeWidth
        clamp()
    }

    /// Zooms the frequency axis by `factor` keeping the global position under
    /// `focus` (a `0…1` fraction up the visible window from the bottom)
    /// stationary.
    mutating func zoomFreq(by factor: Float, focus: Float) {
        let focusGlobal = freqStart + max(0, min(1, focus)) * freqWidth
        freqWidth = min(max(freqWidth * factor, minFreqWidth), 1)
        freqStart = focusGlobal - max(0, min(1, focus)) * freqWidth
        clamp()
    }

    /// Pans the window by normalized deltas (positive `dt` moves later in time,
    /// positive `df` moves toward higher frequency).
    mutating func pan(dt: Float, df: Float) {
        timeStart += dt
        freqStart += df
        clamp()
    }

    /// Recenters the time window on `normalizedTime` without changing zoom.
    mutating func centerTime(on normalizedTime: Float) {
        timeStart = max(0, min(1, normalizedTime)) - timeWidth / 2
        clamp()
    }

    // MARK: - Mapping helpers

    /// Maps a normalized recording time to a `0…1` x-position inside the
    /// visible window. Values outside the window fall outside `0…1`.
    func localX(forNormalizedTime t: Float) -> Float {
        guard timeWidth > 0 else { return 0 }
        return (t - timeStart) / timeWidth
    }

    /// Inverse of `localX`: maps a `0…1` x-position in the window back to a
    /// normalized recording time.
    func normalizedTime(forLocalX x: Float) -> Float {
        timeStart + max(0, min(1, x)) * timeWidth
    }

    /// Maps a `0…1` y-position from the bottom of the window to a global
    /// frequency-normalized value.
    func normalizedFreq(forLocalYFromBottom y: Float) -> Float {
        freqStart + max(0, min(1, y)) * freqWidth
    }
}
