import XCTest

/// Captures a screenshot of every widget type at every allowed size by installing the
/// "Screenshot-Preset: Widgetgrößen" layout and paging through the 9 resulting pages.
///
/// Evidence for M9 widget-audit hardware screenshot pass:
///   agent/tasks/milestone-9-widget-audit/task-11-acceptance.md
///
/// Run via xcodebuild -only-testing:SpektoWatch2UITests/WidgetGridScreenshotTests
/// or capture-screenshots.py which extracts PNGs from the xcresult bundle.
final class WidgetGridScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let launchWait: TimeInterval = 60
    private let viewWait: TimeInterval = 15
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
            "-SnapshotCatalog", "YES",
            "-InstallWidgetSizeScreenshotPreset", "YES"
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
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchWait), "App should launch")

        _ = handleSystemAlertsIfNeeded(timeout: 5.0)

        XCTAssertTrue(
            waitForDashboardReady(timeout: launchWait),
            "Dashboard should be visible (controls or layouts button)"
        )

        _ = handleSystemAlertsIfNeeded(timeout: 1.0)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Widget grid pass

    /// Opens the Layouts confirmation dialog, installs the Widgetgrößen preset,
    /// then pages through all 9 widget-type layouts capturing one screenshot each.
    @MainActor
    func testWidgetSizeGrid() throws {
        try waitForWidgetSizePresetInstalled()

        // AudioWidgetType.allCases order (matches DashboardManager.installWidgetSizeScreenshotPreset)
        let pages: [(num: String, name: String)] = [
            ("01", "Spektrogramm"),
            ("02", "Wasserfall"),
            ("03", "Pegelverlauf"),
            ("04", "Frequenz-Spektrum"),
            ("05", "Pegel-Meter"),
            ("06", "Einzelwert"),
            ("07", "Tongenerator"),
            ("08", "Spektralanalyse-Labor"),
            ("09", "Sound-Masking")
        ]

        for (index, page) in pages.enumerated() {
            capture("M9-\(page.num)-\(page.name)-sizes")
            if index < pages.count - 1 {
                app.swipeLeft()
                settle()
            }
        }
    }

    /// Same as testWidgetSizeGrid but also enters edit mode on each page so the
    /// resize handles and delete circles are visible. Useful for verifying that
    /// widget chrome doesn't obscure edit affordances at small sizes.
    @MainActor
    func testWidgetSizeGridEditMode() throws {
        try waitForWidgetSizePresetInstalled()

        let pages: [(num: String, name: String)] = [
            ("01", "Spektrogramm"),
            ("02", "Wasserfall"),
            ("03", "Pegelverlauf"),
            ("04", "Frequenz-Spektrum"),
            ("05", "Pegel-Meter"),
            ("06", "Einzelwert"),
            ("07", "Tongenerator"),
            ("08", "Spektralanalyse-Labor"),
            ("09", "Sound-Masking")
        ]

        for (index, page) in pages.enumerated() {
            // Enter edit mode
            let editButton = controlElement(in: app, identifier: "editDashboardButton")
            if editButton.waitForExistence(timeout: viewWait) {
                editButton.tap()
                settle()
                capture("M9-\(page.num)-\(page.name)-edit")
                // Exit edit mode
                editButton.tap()
                settle()
            }

            if index < pages.count - 1 {
                app.swipeLeft()
                settle()
            }
        }
    }

    // MARK: - Helpers

    /// Opens the Layouts confirmation dialog and taps "Screenshot-Preset: Widgetgrößen".
    /// Retries once because the dialog may be dismissed by an overlapping animation on the
    /// first tap (observed in ScreenshotCatalogTests which also uses a two-tap pattern).
    /// Launch argument `-InstallWidgetSizeScreenshotPreset` installs layouts in
    /// `ModularDashboardView`; wait until edit mode chrome is available.
    private func waitForWidgetSizePresetInstalled() throws {
        let editButton = controlElement(in: app, identifier: "editDashboardButton")
        XCTAssertTrue(
            editButton.waitForExistence(timeout: launchWait),
            "Dashboard should load with widget-size screenshot preset"
        )
        settle(1.0)
    }

    /// Waits until the main dashboard chrome is on screen (deferred audio startup
    /// can delay `playButton` after the splash placeholder).
    private func waitForDashboardReady(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            _ = handleSystemAlertsIfNeeded(timeout: 0.25)
            let layouts = app.descendants(matching: .any)["layoutsButton"].exists
            let play = app.descendants(matching: .any)["playButton"].exists
            let pause = app.descendants(matching: .any)["pauseButton"].exists
            let playLabel = app.buttons["Play"].exists
            let pauseLabel = app.buttons["Pause"].exists
            if layouts || play || pause || playLabel || pauseLabel {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

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
        if let last = alert.buttons.allElementsBoundByIndex.last {
            last.tap()
            settle()
            return true
        }
        return false
    }
}
