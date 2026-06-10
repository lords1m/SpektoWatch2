import Foundation

/// Pure timing gates for the live publish path — no domain logic, no state
/// beyond the last-publish timestamps:
///
/// - `shouldEnqueueUI`: 60 Hz gate for the per-frame main-thread UI enqueue
///   (currentLevel / octave bands / etc.). Called from the audio render thread.
/// - `shouldPublishSpectrogram`: 15 Hz gate for `currentSpectrogramData` (the
///   heaviest `objectWillChange` source). Called from the main thread.
/// - `shouldSendToWatch`: 0.1 s gate for the WatchConnectivity spectrogram
///   send. Called from the main thread.
///
/// Each gate touches only its own timestamp, and each is driven from a single
/// thread, so no cross-thread field is shared (matching the pre-extraction
/// `AudioEngine` behaviour).
///
/// Extracted from `AudioEngine.updateUI` in VERBESSERUNGSPLAN Phase 3, Task 3.5.
final class UIPublishThrottle {
    /// 60 Hz live-metric publish cadence.
    let uiInterval: TimeInterval = 1.0 / 60.0
    /// 15 Hz spectrogram publish cadence.
    let spectrogramInterval: TimeInterval = 1.0 / 15.0
    /// 0.1 s WatchConnectivity send cadence.
    let watchInterval: TimeInterval = 0.1

    private var lastUIEnqueue: TimeInterval = 0
    private var lastSpectrogramEnqueue: TimeInterval = 0
    private var lastWatchUpdate: TimeInterval = 0

    /// 60 Hz gate. Returns `false` (drop) if called within `uiInterval` of the
    /// previous accepted enqueue; advances the gate when it returns `true`.
    func shouldEnqueueUI(now: TimeInterval) -> Bool {
        if now - lastUIEnqueue < uiInterval { return false }
        lastUIEnqueue = now
        return true
    }

    /// 15 Hz gate for `currentSpectrogramData`.
    func shouldPublishSpectrogram(now: TimeInterval) -> Bool {
        guard now - lastSpectrogramEnqueue >= spectrogramInterval else { return false }
        lastSpectrogramEnqueue = now
        return true
    }

    /// 0.1 s gate for the watch send.
    func shouldSendToWatch(now: TimeInterval) -> Bool {
        guard now - lastWatchUpdate > watchInterval else { return false }
        lastWatchUpdate = now
        return true
    }
}
