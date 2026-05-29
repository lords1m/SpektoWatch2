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
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchWait), "App should launch")

        _ = handleSystemAlertsIfNeeded(timeout: 5.0)

        // Wait for the dashboard control bar — either play or pause button.
        let playVisible = app.descendants(matching: .any)["playButton"].waitForExistence(timeout: launchWait)
        let pauseVisible = playVisible ? false
            : app.descendants(matching: .any)["pauseButton"].waitForExistence(timeout: 5.0)
        XCTAssertTrue(playVisible || pauseVisible, "Dashboard controls should be visible")

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
        try installWidgetSizePreset()

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
        try installWidgetSizePreset()

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
            let editButton = app.descendants(matching: .any)["editDashboardButton"]
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
    private func installWidgetSizePreset() throws {
        let layoutsButton = app.descendants(matching: .any)["layoutsButton"]
        XCTAssertTrue(layoutsButton.waitForExistence(timeout: viewWait), "layoutsButton must be visible")

        // Attempt 1 — tap the layouts button and look for the preset action.
        layoutsButton.tap()
        _ = handleSystemAlertsIfNeeded(timeout: 0.5)
        let presetButton = app.buttons["Screenshot-Preset: Widgetgrößen"]

        if !presetButton.waitForExistence(timeout: 4.0) {
            // Dialog may have been dismissed by an overlapping animation; try once more.
            XCTAssertTrue(layoutsButton.waitForExistence(timeout: viewWait), "layoutsButton must reappear")
            layoutsButton.tap()
            _ = handleSystemAlertsIfNeeded(timeout: 0.5)
            XCTAssertTrue(presetButton.waitForExistence(timeout: viewWait),
                          "Screenshot preset button should appear in Layouts dialog")
        }

        presetButton.tap()
        // Allow time for the 9 layout pages to be installed and the first page to render.
        settle(1.5)
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
