import XCTest
import Foundation

final class WatchAppScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private let launchWait: TimeInterval = 60
    private let viewWait: TimeInterval = 10
    private let swipeSettle: TimeInterval = 0.6
    private let pollInterval: TimeInterval = 0.2
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
            "-ResetState", "YES"
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
        _ = handleSystemAlertsIfNeeded(timeout: 2.5)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testWatchAppScreenshots() throws {
        let deviceName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        guard deviceName.localizedCaseInsensitiveContains("Watch") else {
            throw XCTSkip("Watch screenshots require a watchOS simulator; current device is \(deviceName)")
        }

        XCTAssertTrue(waitForView("watchDashboardView"), "Dashboard view should be visible")
        takeScreenshot(named: "WatchDashboard")

        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(swipeSettle))
        XCTAssertTrue(waitForView("watchSpectrogramView"), "Spectrogram view should be visible")
        takeScreenshot(named: "WatchSpectrogram")

        app.swipeLeft()
        RunLoop.current.run(until: Date().addingTimeInterval(swipeSettle))
        XCTAssertTrue(waitForView("watchLevelMeterView"), "Level meter view should be visible")
        takeScreenshot(named: "WatchLevelMeter")
    }

    // MARK: - Helpers

    private func waitForView(_ identifier: String) -> Bool {
        let element = app.otherElements[identifier]
        return waitForCondition(timeout: viewWait) { element.exists }
    }

    private func waitForCondition(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
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
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                return true
            }
        }

        let fallbackButtons = alert.buttons.allElementsBoundByIndex
        if let lastButton = fallbackButtons.last {
            lastButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            return true
        }

        return false
    }

    private func takeScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let deviceName = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
            ?? ProcessInfo.processInfo.environment["DEVICE_NAME"]
            ?? "Device"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(deviceName)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let sanitizedDevice = sanitizeFilename(deviceName)
        let sanitizedName = sanitizeFilename(name)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WatchScreenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("\(sanitizedDevice)-\(sanitizedName).png")
        try? screenshot.pngRepresentation.write(to: fileURL)
        print("[UITest] Screenshot saved: \(fileURL.path)")
    }

    internal override func sanitizeFilename(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("") { $0 + String($1) }
    }
}
