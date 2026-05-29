import XCTest

final class ScreenshotCatalogTests: XCTestCase {
    private var app: XCUIApplication!
    private let launchWait: TimeInterval = 60
    private let viewWait: TimeInterval = 12
    private let permissionButtonLabels = [
        "Allow",
        "Allow Once",
        "Allow While Using App",
        "Erlauben",
        "Nur einmal erlauben",
        "Beim Verwenden der App erlauben",
        "OK"
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = [
            "-UIAnimationsDisabled", "YES",
            "-ResetState", "YES",
            "-SeedTestData", "YES",
            "-SnapshotCatalog", "YES"
        ]

        addUIInterruptionMonitor(withDescription: "System Permission Alert") { [weak self] element in
            guard let self else { return false }
            for label in self.permissionButtonLabels {
                let button = element.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            if let last = element.buttons.allElementsBoundByIndex.last, last.isHittable {
                last.tap()
                return true
            }
            return false
        }

        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchWait), "App should be running in foreground")

        // Dismiss any system permission alerts before checking for controls.
        _ = handleSystemAlertsIfNeeded(timeout: 5.0)

        // Wait for the dashboard view to appear. This confirms ContentView is
        // on screen (audioEngine + maskingEngine both initialised), regardless
        // of which button state the control bar happens to be in.
        XCTAssertTrue(
            app.descendants(matching: .any)["dashboardView"].waitForExistence(timeout: launchWait),
            "Dashboard view should be visible after app launch"
        )

        // The engine may already be running by the time setUp reaches this
        // check, flipping the button identifier from "playButton" to
        // "pauseButton". Accept either; also accept a match by accessibility
        // label ("Play" / "Pause") as a fallback for iOS versions where the
        // identifier propagation through PlainButtonStyle differs.
        let playById    = app.descendants(matching: .any)["playButton"].waitForExistence(timeout: 5.0)
        let pauseById   = playById ? false : app.descendants(matching: .any)["pauseButton"].waitForExistence(timeout: 2.0)
        let playByLabel = (playById || pauseById) ? false : app.buttons["Play"].waitForExistence(timeout: 2.0)
        let pauseByLabel = (playById || pauseById || playByLabel) ? false : app.buttons["Pause"].waitForExistence(timeout: 2.0)
        XCTAssertTrue(
            playById || pauseById || playByLabel || pauseByLabel,
            "Dashboard controls should be visible (playButton or pauseButton, by id or label)"
        )

        _ = handleSystemAlertsIfNeeded(timeout: 1.0)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testIOSScreenshotCatalog() throws {
        capture("01-Dashboard-Default")

        // Diagnostic: log all button identifiers/labels visible in the tree
        // so we can confirm what accessibility elements actually exist.
        let allButtons = app.buttons.allElementsBoundByIndex
        let buttonDesc = allButtons.map { "\($0.identifier)|\($0.label)" }.joined(separator: ", ")
        XCTContext.runActivity(named: "Accessible buttons: \(buttonDesc)") { _ in }
        let allAny = app.descendants(matching: .any).allElementsBoundByIndex
        let anyDesc = allAny.prefix(30).map { "\($0.elementType.rawValue):\($0.identifier)|\($0.label)" }.joined(separator: "\n  ")
        XCTContext.runActivity(named: "First 30 elements:\n  \(anyDesc)") { _ in }

        tap(identifier: "editDashboardButton")
        XCTAssertTrue(app.buttons["addWidgetButton"].waitForExistence(timeout: viewWait), "Edit controls should be visible")
        capture("02-Dashboard-Edit")

        tap(identifier: "widgetSettingsButton")
        XCTAssertTrue(app.navigationBars["Spektrogramm"].waitForExistence(timeout: viewWait), "Widget settings should open")
        capture("03-Widget-Settings")
        app.buttons["Speichern"].tap()

        XCTAssertTrue(app.buttons["addWidgetButton"].waitForExistence(timeout: viewWait), "Edit controls should return after closing widget settings")
        tap(identifier: "addWidgetButton")
        XCTAssertTrue(app.navigationBars["Widget hinzufügen"].waitForExistence(timeout: viewWait), "Widget picker should open")
        capture("04-Widget-Picker")
        app.buttons["Abbrechen"].tap()

        XCTAssertTrue(app.buttons["editDashboardButton"].waitForExistence(timeout: viewWait), "Dashboard should return after closing widget picker")
        tap(identifier: "editDashboardButton")
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: viewWait), "Settings button should be visible outside edit mode")

        tap(identifier: "settingsButton")
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: viewWait), "Settings should open")
        capture("05-App-Settings-Top")
        app.swipeUp()
        settle()
        capture("06-App-Settings-Bottom")
        app.buttons["Fertig"].tap()

        XCTAssertTrue(app.buttons["recordingsListButton"].waitForExistence(timeout: viewWait), "Recordings button should be visible")
        tap(identifier: "recordingsListButton")
        XCTAssertTrue(app.navigationBars["Aufnahmen"].waitForExistence(timeout: viewWait), "Recordings list should open")
        capture("07-Recordings-List")

        // 07b — recordings list with the first recording's swipe actions
        // partially revealed, so the screenshot documents the Teilen /
        // Löschen affordances. Wrap in a try? so the screenshot still
        // captures the base list if the swipe gesture path changes.
        let firstRecording = app.cells.element(boundBy: 0)
        if firstRecording.waitForExistence(timeout: viewWait) {
            firstRecording.swipeLeft()
            settle()
            capture("07b-Recordings-List-Swipe-Actions")
            // Tap somewhere neutral to dismiss the swipe actions before
            // moving on, otherwise the next swipe/tap can trigger them.
            app.navigationBars["Aufnahmen"].tap()
        }

        // 07c — push into recording detail for one of the seeded entries.
        if firstRecording.waitForExistence(timeout: viewWait) {
            firstRecording.tap()
            // RecordingDetailView doesn't expose a single stable accessibility
            // identifier yet; wait for the back button as a proxy.
            if app.navigationBars.firstMatch.waitForExistence(timeout: viewWait) {
                settle()
                capture("07c-Recording-Detail")
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
        }

        // 07d — sheet's close button is now an `xmark.circle.fill` on the
        // leading edge (modern sheet convention). Tap by accessibility
        // label "Schließen" rather than the legacy "Fertig" string.
        let closeButton = app.buttons["Schließen"]
        if closeButton.waitForExistence(timeout: viewWait) {
            closeButton.tap()
        } else {
            // Fallback for legacy build state where the button still says "Fertig".
            app.buttons["Fertig"].tap()
        }

        XCTAssertTrue(app.buttons["layoutsButton"].waitForExistence(timeout: viewWait), "Layouts menu should be visible")
        tap(identifier: "layoutsButton")
        // Retry once: the action sheet may be dismissed by an in-flight animation on first tap.
        if !app.buttons["Neue leere Seite"].waitForExistence(timeout: 4.0) {
            tap(identifier: "layoutsButton")
        }
        XCTAssertTrue(app.buttons["Neue leere Seite"].waitForExistence(timeout: viewWait), "Layouts dialog should open")
        capture("08-09-Layouts-Dialog")

        app.buttons["Neue leere Seite"].tap()
        XCTAssertTrue(app.staticTexts["Keine Widgets"].waitForExistence(timeout: viewWait), "Empty dashboard should be visible")
        capture("10-Dashboard-Empty")
    }

    private func tap(identifier: String, timeout: TimeInterval = 12) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Expected \(identifier) to exist")
        element.tap()
        _ = handleSystemAlertsIfNeeded(timeout: 0.2)
    }

    // capture(_:), settle(_:), and sanitizeFilename(_:) are provided by
    // UITestScreenshot.swift as XCTestCase extensions.

    @discardableResult
    private func handleSystemAlertsIfNeeded(timeout: TimeInterval = 2.5) -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.exists || alert.waitForExistence(timeout: timeout) else {
            return false
        }

        for label in permissionButtonLabels {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                settle()
                return true
            }
        }

        let fallbackButtons = alert.buttons.allElementsBoundByIndex
        if let lastButton = fallbackButtons.last {
            lastButton.tap()
            settle()
            return true
        }

        return false
    }

}
