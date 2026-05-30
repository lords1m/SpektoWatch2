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

        // Wait for the play/pause button to appear — this confirms ModularDashboardView
        // is on screen with audioEngine + maskingEngine both initialised. We search by
        // both identifier and label because in iOS 26 named container identifiers are
        // inherited by PlainButtonStyle children, so we cannot rely solely on identifiers.
        let playById    = app.descendants(matching: .any)["playButton"].waitForExistence(timeout: launchWait)
        let pauseById   = playById ? false : app.descendants(matching: .any)["pauseButton"].waitForExistence(timeout: 5.0)
        let playByLabel = (playById || pauseById) ? false : app.buttons["Play"].waitForExistence(timeout: 5.0)
        let pauseByLabel = (playById || pauseById || playByLabel) ? false : app.buttons["Pause"].waitForExistence(timeout: 5.0)
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

        // Allow the Widget Picker sheet dismiss animation to complete before
        // interacting with the header bar controls.
        settle()

        XCTAssertTrue(app.buttons["editDashboardButton"].waitForExistence(timeout: viewWait), "Dashboard should return after closing widget picker")
        tap(identifier: "editDashboardButton")
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: viewWait), "Settings button should be visible outside edit mode")

        // Tap settings; retry once if the sheet doesn't appear within 4 s.
        // The header bar DragGesture can rarely swallow the first tap.
        tap(identifier: "settingsButton")
        if !app.navigationBars["Einstellungen"].waitForExistence(timeout: 4.0) {
            tap(identifier: "settingsButton")
        }
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

        // 07d — close the recordings sheet. Try "Schließen" (modern xmark.circle.fill
        // convention), then "Fertig" (legacy label). If neither is found the sheet
        // may have been auto-dismissed when navigating back from recording detail —
        // continue without failing so the rest of the test can run.
        let closeButton = app.buttons["Schließen"]
        if closeButton.waitForExistence(timeout: viewWait) {
            closeButton.tap()
        } else if app.buttons["Fertig"].exists {
            app.buttons["Fertig"].tap()
        }
        // If neither exists, assume sheet already dismissed — proceed.

        XCTAssertTrue(app.buttons["layoutsButton"].waitForExistence(timeout: viewWait), "Layouts menu should be visible")
        tap(identifier: "layoutsButton")
        // Retry once: the action sheet may be dismissed by an in-flight animation on first tap.
        if !app.buttons["Neue leere Seite"].waitForExistence(timeout: 4.0) {
            tap(identifier: "layoutsButton")
        }
        XCTAssertTrue(app.buttons["Neue leere Seite"].waitForExistence(timeout: viewWait), "Layouts dialog should open")
        capture("08-09-Layouts-Dialog")

        // Dismiss the layouts dialog via Cancel so we stay on the current
        // layout. We'll create an empty dashboard by deleting all widgets in
        // edit mode — this avoids the iOS 26 UIPageViewController race where
        // addEmptyLayout() changes activeLayoutIndex but the TabView won't
        // switch to the newly-appended page in the same render cycle.
        let dialogCancel = app.buttons.matching(
            NSPredicate(format: "label == 'Abbrechen' OR label == 'Cancel'")
        ).firstMatch
        if dialogCancel.waitForExistence(timeout: 4.0) {
            dialogCancel.tap()
        }

        // Re-enter edit mode to expose the per-widget delete buttons.
        XCTAssertTrue(app.buttons["editDashboardButton"].waitForExistence(timeout: viewWait), "Edit button should be visible after dialog dismiss")
        tap(identifier: "editDashboardButton")
        XCTAssertTrue(app.buttons["addWidgetButton"].waitForExistence(timeout: viewWait), "Must be in edit mode to delete widgets")

        // Delete every widget card until none remain. The seeded dashboard has
        // 2 widgets (Spectrogram + LevelHistory). widgetDeleteButton is placed
        // on the Image leaf of each card's delete button (iOS 26 PlainButtonStyle
        // fix — see WidgetCardView.deleteButton).
        let deletePred = NSPredicate(format: "identifier == 'widgetDeleteButton'")
        let emptyLabel = app.descendants(matching: .any)["keineWidgetsLabel"]
        for _ in 0..<10 {
            let btn = app.descendants(matching: .any).matching(deletePred).firstMatch
            guard btn.waitForExistence(timeout: 3.0) else { break }
            btn.tap()
            settle(0.5)
            if emptyLabel.exists { break }
        }

        capture("10-Dashboard-Empty")
        XCTAssertTrue(emptyLabel.waitForExistence(timeout: viewWait), "Empty dashboard should be visible")
    }

    private func tap(identifier: String, timeout: TimeInterval = 12) {
        // Use firstMatch so the tap succeeds even when multiple elements share the
        // same identifier (e.g. widgetSettingsButton appears once per widget card).
        let pred = NSPredicate(format: "identifier == %@", identifier)
        let element = app.descendants(matching: .any).matching(pred).firstMatch
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
