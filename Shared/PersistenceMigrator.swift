import Foundation
import os
import os.signpost

/// One-shot, ordered, idempotent `UserDefaults` migration runner (M13 task-8
/// Phase 2).
///
/// Phase 1 (task-8) centralised every key string into `PersistenceKeys`. This
/// is the runner the registry's doc comments referred to: a single declared
/// list of versioned steps, executed once per launch, that brings a user's
/// stored defaults from whatever schema generation they last ran up to the
/// current `currentSchemaVersion`.
///
/// Design rules:
/// - **Idempotent.** Re-running any step must be a harmless no-op. The stored
///   `PersistenceKeys.persistenceSchemaVersion` short-circuits already-applied
///   steps, but each step is also written so a double-run cannot corrupt data.
/// - **Never touch live keys.** Steps garbage-collect superseded keys and
///   perform value-preserving renames only — never anything the current app
///   still reads or writes.
/// - **Localised schema bumps stay put.** The per-type self-healing version
///   checks (`CalibrationProvider.resolveStartupOffset`,
///   `FFTConfiguration.loadSavedSettings`) are intentionally left in place;
///   this runner handles cross-cutting, app-level cleanup, not those.
///
/// To add a migration: bump `currentSchemaVersion`, add a `migrateToVN` step,
/// and call it from the ladder in `runMigrationsIfNeeded` guarded by the prior
/// stored version.
public enum PersistenceMigrator {

    /// Current app-level persistence schema version. Bump when adding a step.
    public static let currentSchemaVersion = 1

    private enum RunState {
        case notStarted
        case inProgress(DispatchGroup)
        case completed
    }

    private static let stateLock = NSLock()
    private static var runState: RunState = .notStarted

    /// Schedules migrations off the launch critical path. Safe to call multiple
    /// times; `completion` runs on the main queue once migrations have finished.
    public static func startMigrationsIfNeeded(
        defaults: UserDefaults = .standard,
        completion: (() -> Void)? = nil
    ) {
        let notify: () -> Void = {
            if let completion {
                if Thread.isMainThread {
                    completion()
                } else {
                    DispatchQueue.main.async(execute: completion)
                }
            }
        }

        stateLock.lock()
        switch runState {
        case .completed:
            stateLock.unlock()
            notify()
            return
        case .inProgress(let group):
            stateLock.unlock()
            if let completion {
                group.notify(queue: .main, execute: completion)
            }
            return
        case .notStarted:
            let group = DispatchGroup()
            group.enter()
            runState = .inProgress(group)
            stateLock.unlock()

            DispatchQueue.global(qos: .userInitiated).async {
                runMigrationsIfNeeded(defaults: defaults)
                stateLock.lock()
                runState = .completed
                stateLock.unlock()
                group.leave()
                notify()
            }
        }
    }

    /// Blocks the calling thread until migrations have finished. Prefer
    /// `startMigrationsIfNeeded` at launch; use this from tests or before
    /// reading keys that a pending migration step may rewrite.
    public static func ensureMigrationsComplete(defaults: UserDefaults = .standard) {
        stateLock.lock()
        let state = runState
        stateLock.unlock()

        switch state {
        case .completed:
            return
        case .notStarted:
            runMigrationsIfNeeded(defaults: defaults)
        case .inProgress(let group):
            group.wait()
        }
    }

    /// Runs all pending migration steps once, in order, then stamps the version.
    /// Safe to call on every launch; a no-op once the stored version is current.
    public static func runMigrationsIfNeeded(defaults: UserDefaults = .standard) {
        let signpostID = PerformanceSignpost.begin("PersistenceMigration")

        let stored = defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion)
        guard stored < currentSchemaVersion else {
            PerformanceSignpost.end("PersistenceMigration", signpostID: signpostID)
            markCompletedIfNeeded()
            return
        }

        if stored < 1 {
            migrateToV1(defaults: defaults)
        }

        defaults.set(currentSchemaVersion, forKey: PersistenceKeys.persistenceSchemaVersion)
        PerformanceSignpost.end("PersistenceMigration", signpostID: signpostID)
        markCompletedIfNeeded()
    }

    private static func markCompletedIfNeeded() {
        stateLock.lock()
        if case .notStarted = runState {
            runState = .completed
        }
        stateLock.unlock()
    }

    // MARK: - Steps

    /// v0 → v1: garbage-collect superseded dashboard snapshot keys.
    ///
    /// The single-layout dashboard snapshot evolved through several versioned
    /// names before the current `DashboardConfiguration_v5`
    /// (`PersistenceKeys.dashboardLegacySnapshot`) and the multi-layout
    /// `DashboardLayouts_v1` store. Long-time users still carry the orphaned
    /// older snapshots in their defaults domain; nothing in the current app
    /// reads them. Remove them so they stop occupying storage.
    ///
    /// `removeObject` on an absent key is a no-op, so listing the full
    /// `_v1 … _v4` range is safe even for users who never wrote some of them.
    /// The active `_v5` snapshot and `DashboardLayouts_v1` are deliberately
    /// left untouched.
    private static func migrateToV1(defaults: UserDefaults) {
        let supersededDashboardSnapshots = [
            "DashboardConfiguration_v1",
            "DashboardConfiguration_v2",
            "DashboardConfiguration_v3",
            "DashboardConfiguration_v4",
        ]
        for key in supersededDashboardSnapshots {
            defaults.removeObject(forKey: key)
        }
    }
}
