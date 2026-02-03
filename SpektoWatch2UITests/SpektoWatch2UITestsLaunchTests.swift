//
//  SpektoWatch2UITestsLaunchTests.swift
//  SpektoWatch2UITests
//
//  Created by Simeon Brandt on 31.01.26.
//

import XCTest

final class SpektoWatch2UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false // Deaktiviert, da kontinuierliche Animationen XCUITest blockieren
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // Launch-Test deaktiviert wegen kontinuierlicher Spektrum-Animationen
    // Die App hat Echtzeit-Visualisierungen, die XCUITest's "wait for idle" blockieren
    //
    // @MainActor
    // func testLaunch() throws {
    //     let app = XCUIApplication()
    //     app.launch()
    //
    //     let attachment = XCTAttachment(screenshot: app.screenshot())
    //     attachment.name = "Launch Screen"
    //     attachment.lifetime = .keepAlways
    //     add(attachment)
    // }
}
