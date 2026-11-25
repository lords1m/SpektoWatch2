#if canImport(ActivityKit)
import ActivityKit
import Foundation
import OSLog

/// Owns the lifecycle of the measurement Live Activity (Dynamic Island +
/// Lock Screen). The main app drives it: `start` when a recording begins,
/// `update` on each throttled metrics tick, `end` when it stops.
///
/// Rendering is provided by the Live Activity widget extension
/// (`MeasurementLiveActivityWidget`). Until that extension target exists the
/// `request` call still runs but there is no UI to render; failures are logged
/// and swallowed so they never affect the recording path.
@MainActor
final class MeasurementLiveActivityController {
    static let shared = MeasurementLiveActivityController()

    private var activity: Activity<MeasurementActivityAttributes>?
    private let logger = Logger(subsystem: "BrandtAcoustics.SpektoWatch2", category: "LiveActivity")

    /// Minimum spacing between pushed updates. ActivityKit rate-limits high
    /// update frequencies, so we cap at ~1 Hz regardless of caller cadence.
    private let minUpdateInterval: TimeInterval = 1.0
    private var lastUpdate: Date = .distantPast
    /// UI-14: watches the current activity's state so a user dismissal (or
    /// a system end) clears `activity` instead of leaving a dead handle.
    private var stateObservation: Task<Void, Never>?

    private init() {
        // UI-14: activities orphaned by a crash/kill of a previous process
        // are never ended by anyone else — end them at launch.
        endOrphanedActivities()
    }

    /// Ends every activity of this type that is not the one we own.
    func endOrphanedActivities() {
        let ownID = activity?.id
        for orphan in Activity<MeasurementActivityAttributes>.activities where orphan.id != ownID {
            logger.info("Ending orphaned Live Activity \(orphan.id, privacy: .public).")
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func observeState(of activity: Activity<MeasurementActivityAttributes>) {
        stateObservation?.cancel()
        let id = activity.id
        stateObservation = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .dismissed || state == .ended else { continue }
                await MainActor.run {
                    guard let self, self.activity?.id == id else { return }
                    self.logger.info("Live Activity \(id, privacy: .public) \(String(describing: state), privacy: .public) externally.")
                    self.activity = nil
                    self.stateObservation = nil
                }
                return
            }
        }
    }

    /// Whether the user has Live Activities enabled for this app.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Begins a Live Activity for a measurement session. No-op if one is
    /// already running or the feature is disabled.
    /// - Returns: `nil` on success, a human-readable reason string on failure.
    @discardableResult
    func start(sessionTitle: String, weighting: String, startedAt: Date = Date()) -> String? {
        let available = isAvailable
        print("[LiveActivity] start() — areActivitiesEnabled=\(available), existingActivity=\(activity?.id ?? "none")")
        guard available else {
            let reason = "Live Activities disabled — enable in Settings → \(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "app") → Live Activities"
            logger.info("Live Activities disabled; skipping start.")
            print("[LiveActivity] SKIPPED: \(reason)")
            return reason
        }
        guard activity == nil else {
            print("[LiveActivity] Already running (\(activity!.id)); skipping.")
            return nil
        }
        // UI-14: never stack a second activity next to a stale one.
        endOrphanedActivities()

        let attributes = MeasurementActivityAttributes(
            sessionTitle: sessionTitle,
            startedAt: startedAt
        )
        let initialState = MeasurementActivityAttributes.ContentState(
            currentLevel: -120,
            peakLevel: -120,
            weighting: weighting,
            isPaused: false
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initialState, staleDate: nil)
            )
            lastUpdate = .distantPast
            if let activity { observeState(of: activity) }
            logger.info("Started Live Activity \(self.activity?.id ?? "?", privacy: .public).")
            print("[LiveActivity] Started: id=\(self.activity?.id ?? "?")")
            return nil
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
            print("[LiveActivity] ERROR: \(error)")
            return "Live Activity failed: \(error.localizedDescription)"
        }
    }

    /// Pushes a new metrics snapshot, throttled to `minUpdateInterval`.
    /// `force` bypasses the throttle (e.g. for pause-state transitions).
    func update(currentLevel: Double, peakLevel: Double, weighting: String, isPaused: Bool, force: Bool = false) {
        guard let activity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastUpdate) >= minUpdateInterval else { return }
        lastUpdate = now

        let state = MeasurementActivityAttributes.ContentState(
            currentLevel: currentLevel,
            peakLevel: peakLevel,
            weighting: weighting,
            isPaused: isPaused
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(8)))
        }
    }

    /// Ends the Live Activity immediately and clears state.
    func end() {
        guard let activity else { return }
        self.activity = nil
        stateObservation?.cancel()
        stateObservation = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        logger.info("Ended Live Activity.")
    }
}
#endif
