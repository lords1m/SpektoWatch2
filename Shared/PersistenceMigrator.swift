import Foundation

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

    /// Run all pending migration steps once, in order, then stamp the version.
    /// Safe to call on every launch; a no-op once the stored version is current.
    ///
    /// Call this as early as possible at launch — before any service reads its
    /// keys — so future value-preserving steps land before consumers load.
    public static func runMigrationsIfNeeded(defaults: UserDefaults = .standard) {
        let stored = defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion)
        guard stored < currentSchemaVersion else { return }

        if stored < 1 {
            migrateToV1(defaults: defaults)
        }

        defaults.set(currentSchemaVersion, forKey: PersistenceKeys.persistenceSchemaVersion)
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
