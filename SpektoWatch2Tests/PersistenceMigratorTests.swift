import XCTest
@testable import SpektoWatch2

/// Tests for the M13 task-8 Phase 2 persistence migration runner.
///
/// Each test uses an isolated `UserDefaults(suiteName:)` so it never touches
/// the real `.standard` domain. Covers: cold launch (fresh install), pre-M13
/// state cleanup, idempotency, and the invariant that live keys are never
/// disturbed.
final class PersistenceMigratorTests: XCTestCase {

    private let suiteName = "PersistenceMigratorTests"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Cold launch (fresh install)

    /// A brand-new install has no stored version; the runner stamps the
    /// current schema version and removing the (absent) legacy keys is a no-op.
    func testFreshInstallStampsCurrentVersion() {
        XCTAssertEqual(defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion), 0)

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)

        XCTAssertEqual(
            defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion),
            PersistenceMigrator.currentSchemaVersion
        )
    }

    // MARK: - Pre-M13 state

    /// A long-time user carries orphaned `DashboardConfiguration_v1…v4`
    /// snapshots. After migration they are gone, while the active `_v5`
    /// snapshot and the multi-layout store are preserved untouched.
    func testV1RemovesSupersededDashboardSnapshots() {
        let superseded = [
            "DashboardConfiguration_v1",
            "DashboardConfiguration_v2",
            "DashboardConfiguration_v3",
            "DashboardConfiguration_v4",
        ]
        for key in superseded {
            defaults.set(Data([0x1]), forKey: key)
        }
        defaults.set(Data([0xAA]), forKey: PersistenceKeys.dashboardLegacySnapshot) // _v5, active
        defaults.set(Data([0xBB]), forKey: PersistenceKeys.dashboardLayouts)        // active

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)

        for key in superseded {
            XCTAssertNil(defaults.object(forKey: key), "\(key) should be garbage-collected")
        }
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.dashboardLegacySnapshot), Data([0xAA]),
                       "Active _v5 snapshot must be preserved")
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.dashboardLayouts), Data([0xBB]),
                       "Active multi-layout store must be preserved")
    }

    // MARK: - Idempotency

    /// Running twice is safe: the second call short-circuits on the stored
    /// version and leaves all keys as the first run left them.
    func testRunningTwiceIsIdempotent() {
        defaults.set(Data([0xAA]), forKey: PersistenceKeys.dashboardLegacySnapshot)

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)
        let versionAfterFirst = defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion)

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)
        let versionAfterSecond = defaults.integer(forKey: PersistenceKeys.persistenceSchemaVersion)

        XCTAssertEqual(versionAfterFirst, PersistenceMigrator.currentSchemaVersion)
        XCTAssertEqual(versionAfterSecond, versionAfterFirst)
        XCTAssertEqual(defaults.data(forKey: PersistenceKeys.dashboardLegacySnapshot), Data([0xAA]))
    }

    /// A user already on the current version is never re-migrated: a freshly
    /// re-introduced legacy key (e.g. written by an older paired process)
    /// survives because the runner short-circuits.
    func testAlreadyCurrentVersionSkipsSteps() {
        defaults.set(PersistenceMigrator.currentSchemaVersion, forKey: PersistenceKeys.persistenceSchemaVersion)
        defaults.set(Data([0x1]), forKey: "DashboardConfiguration_v2")

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)

        XCTAssertNotNil(defaults.object(forKey: "DashboardConfiguration_v2"),
                        "Steps must not run once the stored version is current")
    }

    // MARK: - Live-key safety

    /// The migrator must never disturb keys the current app still reads.
    func testDoesNotTouchLiveKeys() {
        defaults.set(-12.5, forKey: PersistenceKeys.Calibration.offset)
        defaults.set(2, forKey: PersistenceKeys.Calibration.version)
        defaults.set(2048, forKey: PersistenceKeys.FFT.blockSize)
        defaults.set(2, forKey: PersistenceKeys.FFT.configVersion)
        defaults.set(0.25, forKey: PersistenceKeys.spectrogramFrequencySmoothing)
        defaults.set(true, forKey: PersistenceKeys.Watch.standaloneEnabled)

        PersistenceMigrator.runMigrationsIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.float(forKey: PersistenceKeys.Calibration.offset), -12.5)
        XCTAssertEqual(defaults.integer(forKey: PersistenceKeys.Calibration.version), 2)
        XCTAssertEqual(defaults.integer(forKey: PersistenceKeys.FFT.blockSize), 2048)
        XCTAssertEqual(defaults.integer(forKey: PersistenceKeys.FFT.configVersion), 2)
        XCTAssertEqual(defaults.double(forKey: PersistenceKeys.spectrogramFrequencySmoothing), 0.25, accuracy: 1e-9)
        XCTAssertTrue(defaults.bool(forKey: PersistenceKeys.Watch.standaloneEnabled))
    }
}
