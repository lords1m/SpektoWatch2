import XCTest

final class ScreenshotCatalogTests: XCTestCase {
    private var app: XCUIApplication!
    private let launchWait: TimeInterval = 60
    private let viewWait: TimeInterval = 12
    private let settleDelay: TimeInterval = 0.7
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
        XCTAssertTrue(app.descendants(matching: .any)["playButton"].waitForExistence(timeout: launchWait), "Dashboard controls should be visible")
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
        app.buttons["Fertig"].tap()

        XCTAssertTrue(app.buttons["layoutsButton"].waitForExistence(timeout: viewWait), "Layouts menu should be visible")
        tap(identifier: "layoutsButton")
        XCTAssertTrue(app.buttons["Layouts abrufen"].waitForExistence(timeout: viewWait), "Layouts menu should open")
        capture("08-Layouts-Menu")

        app.buttons["Layouts abrufen"].tap()
        XCTAssertTrue(app.buttons["Neue leere Seite"].waitForExistence(timeout: viewWait), "Layouts dialog should open")
        capture("09-Layouts-Dialog")

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

    private func capture(_ name: String) {
        settle()

        let screenshot = XCUIScreen.main.screenshot()
        let deviceName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
            ?? ProcessInfo.processInfo.environment["DEVICE_NAME"]
            ?? "Device"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceName)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCatalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(sanitizeFilename(deviceName))-\(sanitizeFilename(name)).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
        print("[UITest] Screenshot saved: \(fileURL.path)")
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(settleDelay))
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

        let fallbackButtons = alert.buttons.allElementsBoundByIndex
        if let lastButton = fallbackButtons.last {
            lastButton.tap()
            settle()
            return true
        }

        return false
    }

    private func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("") { $0 + String($1) }
    }
}
