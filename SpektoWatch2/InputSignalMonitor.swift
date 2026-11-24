import Foundation
import OSLog
import os

/// Cohesive home for the live input-signal diagnostics that span the capture
/// thread and the UI thread: impulse end-to-end latency measurement and the
/// one-shot silence warning.
///
/// Extracted from `AudioEngine` in VERBESSERUNGSPLAN Phase 3 (post-3.5 shrink).
/// All cross-thread state is protected by an `OSAllocatedUnfairLock` and all
/// logging happens on the main thread so the audio render callback remains
/// real-time safe.
final class InputSignalMonitor {
    private struct State {
        var lastImpulseTime: TimeInterval = 0
        var pendingImpulseLog = false
        var hasLoggedSilence = false
        var pendingSilenceDBFS: Float? = nil
    }

    /// dBFS level above which a buffer is treated as an impulse onset.
    private let impulseThresholdDbfs: Float = -35.0
    /// Minimum gap between two impulse measurements.
    private let impulseCooldownSeconds: TimeInterval = 1.0

    private let stateLock = OSAllocatedUnfairLock<State>(initialState: State())

    /// Audio-render-thread: arm an impulse latency measurement when a loud
    /// transient arrives and the cooldown has elapsed.
    func detectImpulse(signalDBFS: Float, now: TimeInterval) {
        guard signalDBFS > impulseThresholdDbfs else { return }
        stateLock.withLockUnchecked { state in
            if (now - state.lastImpulseTime) > impulseCooldownSeconds {
                state.lastImpulseTime = now
                state.pendingImpulseLog = true
            }
        }
    }

    /// Audio-render-thread: record a one-shot silence warning to be logged on
    /// the main thread by `reportPendingImpulse`.
    func logSilenceIfNeeded(signalDBFS: Float) {
        guard signalDBFS < -120 else { return }
        stateLock.withLockUnchecked { state in
            if !state.hasLoggedSilence {
                state.hasLoggedSilence = true
                state.pendingSilenceDBFS = signalDBFS
            }
        }
    }

    /// Main thread (UI publish path): drain any pending silence warning, and if
    /// an impulse is armed and the level has reached the display, print the
    /// end-to-end latency and disarm. `peakDbfs` is the published peak converted
    /// back to dBFS.
    func reportPendingImpulse(peakDbfs: Float) {
        let (silenceDBFS, impulseTime): (Float?, TimeInterval?) = stateLock.withLock { state in
            let silence = state.pendingSilenceDBFS
            state.pendingSilenceDBFS = nil

            var firedTime: TimeInterval?
            if state.pendingImpulseLog, peakDbfs > impulseThresholdDbfs {
                firedTime = state.lastImpulseTime
                state.pendingImpulseLog = false
            }
            return (silence, firedTime)
        }

        if let silenceDBFS {
            Logger.audioEngine.warning("Audio buffer silent/empty: \(silenceDBFS, format: .fixed(precision: 1)) dBFS")
        }

        if let impulseTime {
            let dtMs = (CFAbsoluteTimeGetCurrent() - impulseTime) * 1000.0
            let impulseLine = String(format: "[Impulse] end-to-end %.0f ms (threshold %.0f dBFS)", dtMs, impulseThresholdDbfs)
            print(impulseLine)
        }
    }

    /// Re-arm the one-shot silence warning (on capture (re)start).
    func resetSilenceLog() {
        stateLock.withLock { state in
            state.hasLoggedSilence = false
            state.pendingSilenceDBFS = nil
        }
    }
}
