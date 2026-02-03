//
//  SpektoWatch2UITests.swift
//  SpektoWatch2UITests
//
//  Created by Simeon Brandt on 31.01.26.
//

import XCTest

final class SpektoWatch2UITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    // MARK: - App Launch Test

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIAnimationsDisabled", "YES"]
        app.launch()

        // Einfach prüfen ob die App startet
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    // MARK: - Launch Performance Test

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
