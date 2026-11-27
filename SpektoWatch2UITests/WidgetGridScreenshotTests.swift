import XCTest

/// Captures every widget-size catalog and the largest editable Home Screen widget.
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
    private let widgetPages = [
        "Spektrogramm",
        "Pegelverlauf",
        "Frequenz-Spektrum",
        "Pegel-Meter",
        "Einzelwert",
        "Tongenerator",
        "Spektralanalyse-Labor",
        "Audio-Editor",
        "Aufnahmen",
        "Einstellungen"
    ]
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

    /// Captures every screenshot layout containing all catalog sizes for its widget type.
    @MainActor
    func testWidgetSizeGrid() throws {
        waitForWidgetSizePresetInstalled()

        for (index, page) in widgetPages.enumerated() {
            selectScreenshotLayout(page)
            capture(String(format: "M9-%02d-%@-sizes", index + 1, page))
        }
    }

    /// Same as testWidgetSizeGrid but also enters edit mode on each layout so the
    /// resize handles and delete circles are visible. Useful for verifying that
    /// widget chrome doesn't obscure edit affordances at small sizes.
    @MainActor
    func testWidgetSizeGridEditMode() throws {
        waitForWidgetSizePresetInstalled()

        for (index, page) in widgetPages.enumerated() {
            selectScreenshotLayout(page)
            let editButton = controlElement(in: app, identifier: "editDashboardButton")
            XCTAssertTrue(editButton.waitForExistence(timeout: viewWait))
            editButton.tap()
            XCTAssertTrue(app.buttons["addWidgetButton"].waitForExistence(timeout: viewWait))
            capture(String(format: "M9-%02d-%@-edit", index + 1, page))
            editButton.tap()
            XCTAssertTrue(waitForEditModeToEnd(timeout: viewWait))
        }
    }

    @MainActor
    func testLargestWidgetScrollsClearOfDockInEditMode() throws {
        waitForWidgetSizePresetInstalled()
        selectScreenshotLayout("Spektrogramm")

        let editButton = controlElement(in: app, identifier: "editDashboardButton")
        XCTAssertTrue(editButton.waitForExistence(timeout: viewWait))
        editButton.tap()
        XCTAssertTrue(app.buttons["addWidgetButton"].waitForExistence(timeout: viewWait))

        let largestResizeHandle = controlElement(
            in: app,
            identifier: "homeResizeHandle-Spektrogramm-4x7"
        )
        let largestWidgetTarget = controlElement(
            in: app,
            identifier: "homeWidgetEditTarget-Spektrogramm-4x7"
        )
        XCTAssertTrue(largestResizeHandle.waitForExistence(timeout: viewWait))
        XCTAssertTrue(largestWidgetTarget.waitForExistence(timeout: viewWait))

        let pageScrollView = app.scrollViews["homeScreenPageScrollView"]
        XCTAssertTrue(pageScrollView.waitForExistence(timeout: viewWait))
        let initialWidgetY = largestWidgetTarget.frame.minY
        for _ in 0..<8 {
            pageScrollView.swipeUp()
            settle(0.2)
        }

        XCTAssertLessThan(largestWidgetTarget.frame.minY, initialWidgetY, "The Home Screen content should scroll")
        XCTAssertTrue(largestResizeHandle.isHittable, "The 4×7 widget resize control should be reachable by scrolling")
        XCTAssertTrue(largestWidgetTarget.isHittable, "The full widget edit and reorder surface should remain reachable")
        XCTAssertTrue(controlElement(in: app, identifier: "recordButton").isHittable, "Dock controls must remain reachable")
        capture("M9-Spektrogramm-largest-widget-edit-scrolled")

        XCTAssertTrue(editButton.isHittable, "The edit-mode exit control should remain reachable")
        editButton.tap()
        XCTAssertTrue(waitForEditModeToEnd(timeout: viewWait))
        XCTAssertTrue(controlElement(in: app, identifier: "recordButton").isHittable)
    }

    // MARK: - Helpers

    @MainActor
    private func waitForWidgetSizePresetInstalled() {
        XCTAssertTrue(
            waitForPageName("Screenshot: Spektrogramm", timeout: launchWait),
            "Dashboard should load with widget-size screenshot preset"
        )
        settle(1.0)
    }

    @MainActor
    private func selectScreenshotLayout(_ pageName: String) {
        let layoutName = "Screenshot: \(pageName)"
        guard !waitForPageName(layoutName, timeout: 0.1) else { return }

        let layoutsButton = controlElement(in: app, identifier: "layoutsButton")
        XCTAssertTrue(layoutsButton.waitForExistence(timeout: viewWait))
        layoutsButton.tap()

        let layoutButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", layoutName)
        ).firstMatch
        XCTAssertTrue(layoutButton.waitForExistence(timeout: viewWait), "Expected custom layout \(layoutName)")
        layoutButton.tap()
        XCTAssertTrue(waitForPageName(layoutName, timeout: viewWait), "Expected \(layoutName) to become active")
    }

    @MainActor
    private func waitForPageName(_ name: String, timeout: TimeInterval) -> Bool {
        let indicator = controlElement(in: app, identifier: "homePageIndicator")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if indicator.exists && indicator.label.contains(name) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return indicator.exists && indicator.label.contains(name)
    }

    @MainActor
    private func waitForEditModeToEnd(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !app.buttons["addWidgetButton"].exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return !app.buttons["addWidgetButton"].exists
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
