import Foundation
import OSLog

/// Cohesive home for the live input-signal diagnostics that span the capture
/// thread and the UI thread: impulse end-to-end latency measurement and the
/// one-shot silence warning.
///
/// The impulse latency feature inherently crosses two threads — `detectImpulse`
/// arms it on the audio render thread when a loud transient arrives, and
/// `reportPendingImpulse` (main thread, from the UI publish path) prints the
/// measured delay once the level reaches the display. These fields were plain
/// (unlocked) `var`s on `AudioEngine` accessed from both threads; this type
/// preserves that exact (benign, diagnostics-only) behaviour — no lock is
/// introduced.
///
/// Extracted from `AudioEngine` in VERBESSERUNGSPLAN Phase 3 (post-3.5 shrink).
/// Logic is verbatim. The verbose per-buffer RMS log stays in `AudioEngine`
/// because it is gated by the shared `debugPrintCounter`.
final class InputSignalMonitor {
    /// dBFS level above which a buffer is treated as an impulse onset.
    private let impulseThresholdDbfs: Float = -35.0
    /// Minimum gap between two impulse measurements.
    private let impulseCooldownSeconds: TimeInterval = 1.0

    private var lastImpulseTime: TimeInterval = 0
    private var pendingImpulseLog = false
    private var hasLoggedSilence = false

    /// Audio-render-thread: arm an impulse latency measurement when a loud
    /// transient arrives and the cooldown has elapsed.
    func detectImpulse(signalDBFS: Float, now: TimeInterval) {
        if signalDBFS > impulseThresholdDbfs && (now - lastImpulseTime) > impulseCooldownSeconds {
            lastImpulseTime = now
            pendingImpulseLog = true
        }
    }

    /// Audio-render-thread: emit a single warning the first time the input is
    /// effectively silent, so a dead mic is obvious without log spam.
    func logSilenceIfNeeded(signalDBFS: Float) {
        if signalDBFS < -120 && !hasLoggedSilence {
            Logger.audioEngine.warning("Audio buffer silent/empty: \(signalDBFS, format: .fixed(precision: 1)) dBFS")
            hasLoggedSilence = true
        }
    }

    /// Main thread (UI publish path): if an impulse is armed and the level has
    /// reached the display, print the end-to-end latency and disarm.
    /// `peakDbfs` is the published peak converted back to dBFS.
    func reportPendingImpulse(peakDbfs: Float) {
        guard pendingImpulseLog else { return }
        if peakDbfs > impulseThresholdDbfs {
            let dtMs = (CFAbsoluteTimeGetCurrent() - lastImpulseTime) * 1000.0
            let impulseLine = String(format: "[Impulse] end-to-end %.0f ms (threshold %.0f dBFS)", dtMs, impulseThresholdDbfs)
            print(impulseLine)
            pendingImpulseLog = false
        }
    }

    /// Re-arm the one-shot silence warning (on capture (re)start).
    func resetSilenceLog() {
        hasLoggedSilence = false
    }
}
