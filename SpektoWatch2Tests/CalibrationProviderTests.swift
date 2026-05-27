//
//  CalibrationProviderTests.swift
//  SpektoWatch2Tests
//
//  M13 task-3 acceptance: at least two device-model strings covered.
//

import XCTest
@testable import SpektoWatch2

final class CalibrationProviderTests: XCTestCase {

    func testRecommendedOffsetForKnownDevices() {
        // iPhone 12 mini — more sensitive mic, lower offset.
        XCTAssertEqual(CalibrationProvider.recommendedOffset(for: "iPhone13,1"), 91.0)
        // iPhone 15 Pro — newer baseline.
        XCTAssertEqual(CalibrationProvider.recommendedOffset(for: "iPhone16,1"), 94.0)
        // iPhone 8 — older, less sensitive.
        XCTAssertEqual(CalibrationProvider.recommendedOffset(for: "iPhone10,1"), 96.0)
        // iPhone 16 Pro — M19 addition.
        XCTAssertEqual(CalibrationProvider.recommendedOffset(for: "iPhone17,1"), 94.0)
        // iPhone SE (3rd gen) — M19 addition.
        XCTAssertEqual(CalibrationProvider.recommendedOffset(for: "iPhone14,6"), 94.0)
    }

    func testUnknownDeviceFallsBackToDefault() {
        // Simulator and unknown identifiers must fall back cleanly.
        XCTAssertEqual(
            CalibrationProvider.recommendedOffset(for: "Unknown-Device"),
            CalibrationProvider.defaultOffset
        )
        XCTAssertEqual(
            CalibrationProvider.recommendedOffset(for: "x86_64"),
            CalibrationProvider.defaultOffset
        )
    }

    func testDefaultOffsetIsReferenceValue() {
        // The default offset corresponds to the 94 dB SPL pistonphone
        // reference — should stay at 94.0 unless the calibration model
        // changes deliberately.
        XCTAssertEqual(CalibrationProvider.defaultOffset, 94.0)
    }

    func testResolveStartupOffsetUsesSavedValueWhenSchemaMatches() {
        let suite = makeFreshDefaults()
        suite.set(2, forKey: "calibrationVersion")
        suite.set(Float(87.5), forKey: "calibrationOffset")

        let resolved = CalibrationProvider.resolveStartupOffset(defaults: suite)
        XCTAssertEqual(resolved, 87.5)
    }

    func testResolveStartupOffsetFallsBackOnMissingVersion() {
        // Fresh defaults with no calibrationVersion → device default,
        // schema marker is bumped.
        let suite = makeFreshDefaults()
        suite.set(Float(50.0), forKey: "calibrationOffset") // stale, no version

        let resolved = CalibrationProvider.resolveStartupOffset(defaults: suite)
        XCTAssertNotEqual(resolved, 50.0)
        XCTAssertEqual(suite.integer(forKey: "calibrationVersion"), 2)
    }

    // MARK: - Helpers

    private func makeFreshDefaults() -> UserDefaults {
        let suiteName = "CalibrationProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
