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

    private init() {}

    /// Whether the user has Live Activities enabled for this app.
    var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Begins a Live Activity for a measurement session. No-op if one is
    /// already running or the feature is disabled.
    func start(sessionTitle: String, weighting: String, startedAt: Date = Date()) {
        guard isAvailable else {
            logger.info("Live Activities disabled; skipping start.")
            return
        }
        guard activity == nil else { return }

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
            logger.info("Started Live Activity \(self.activity?.id ?? "?", privacy: .public).")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
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
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        logger.info("Ended Live Activity.")
    }
}
#endif
