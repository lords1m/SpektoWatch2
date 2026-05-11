//
//  SpektoWatch2UITests.swift
//  SpektoWatch2UITests
//
//  Created by Simeon Brandt on 31.01.26.
//

import XCTest

final class SpektoWatch2UITests: XCTestCase {

    var app: XCUIApplication!
    private let shortWait: TimeInterval = 0.5
    private let mediumWait: TimeInterval = 3
    private let longWait: TimeInterval = 15
    private let launchWait: TimeInterval = 60
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

    // MARK: - Helpers

    private func waitForCondition(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    private func waitForConditionHandlingAlerts(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            _ = handleSystemAlertsIfNeeded(timeout: 0.1)
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        _ = handleSystemAlertsIfNeeded(timeout: 0.1)
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

        // Safe fallback without index-race on dynamic alert trees.
        let fallbackButtons = alert.buttons.allElementsBoundByIndex
        if let lastButton = fallbackButtons.last {
            lastButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            return true
        }

        return false
    }

    private func tapAndHandleAlerts(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: mediumWait), "Expected element to exist before tap")
        element.tap()
        handleSystemAlertsIfNeeded()
    }

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Terminate any existing instance first
        let app = XCUIApplication()
        if app.state == .runningForeground || app.state == .runningBackground {
            app.terminate()
            Thread.sleep(forTimeInterval: 1)
        }

        // Create fresh app instance
        self.app = XCUIApplication()
        self.app.launchArguments = [
            "-UIAnimationsDisabled", "YES",
            "-ResetState", "YES"  // Signal app to reset state
        ]

        // Reset authorization BEFORE launch
        self.app.resetAuthorizationStatus(for: .microphone)

        // Auto-grant permission dialogs (mic, etc.) that interrupt tests
        addUIInterruptionMonitor(withDescription: "System Permission Alert") { [weak self] element in
            guard let self else { return false }
            for label in self.permissionButtonLabels {
                let button = element.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            // Fallback: last button is usually the allow action
            if let last = element.buttons.allElementsBoundByIndex.last, last.isHittable {
                last.tap()
                return true
            }
            return false
        }

        // Launch app
        self.app.launch()

        // Verify app is in foreground (generous timeout for Xcode Cloud simulators)
        XCTAssertTrue(self.app.wait(for: .runningForeground, timeout: launchWait), "App should be running in foreground")

        // Verify initial UI elements are present (wait for async AudioEngine init to complete)
        XCTAssertTrue(self.app.buttons["playButton"].waitForExistence(timeout: launchWait), "Play button should exist after setup")
        XCTAssertTrue(self.app.buttons["recordButton"].waitForExistence(timeout: launchWait), "Record button should exist after setup")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Test

    @MainActor
    func testAppLaunches() throws {
        // setUp already verified foreground + UI; just confirm state is stable
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: launchWait))
        XCTAssertTrue(app.buttons["playButton"].exists, "Play button must be visible on launch")
    }

    // MARK: - Launch Performance Test

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    // MARK: - Control Bar Button Tests

    @MainActor
    func testPlayButtonExists() throws {
        // Warte bis die UI geladen ist
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait), "Play button should exist")
    }

    @MainActor
    func testRecordButtonExists() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait), "Record button should exist")
    }

    @MainActor
    func testRecordingsListButtonExists() throws {
        let listButton = app.buttons["recordingsListButton"]
        XCTAssertTrue(listButton.waitForExistence(timeout: mediumWait), "Recordings list button should exist")
    }

    @MainActor
    func testControlBarIdentifiersToggle() throws {
        // Play -> Pause -> Play
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))
        tapAndHandleAlerts(playButton)

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait))
        tapAndHandleAlerts(pauseButton)

        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))

        // Record -> Stop -> Record
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))
        tapAndHandleAlerts(recordButton)

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: longWait))

        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })
        tapAndHandleAlerts(stopButton)

        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))
    }

    @MainActor
    func testPlayButtonTogglesToPause() throws {
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))

        print("[TEST] Initial state - buttons present:")
        print("[TEST] playButton exists: \(playButton.exists)")
        print("[TEST] pauseButton exists: \(app.buttons["pauseButton"].exists)")

        // Tippe auf Play
        print("[TEST] Tapping play button...")
        tapAndHandleAlerts(playButton)

        // Warte und prüfe Buttons
        print("[TEST] Waiting for button state change...")
        for i in 1...20 {
            RunLoop.current.run(until: Date().addingTimeInterval(1.0))
            let playExists = app.buttons["playButton"].exists
            let pauseExists = app.buttons["pauseButton"].exists
            print("[TEST] Attempt \(i)/20: playButton=\(playExists), pauseButton=\(pauseExists)")

            if pauseExists {
                print("[TEST] ✅ Pause button appeared after \(i) seconds!")
                return // Test passed!
            }
        }

        XCTFail("Pause button did not appear after 20 seconds")
    }

    @MainActor
    func testPauseButtonTogglesBackToPlay() throws {
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))

        // Starte Live-Modus
        tapAndHandleAlerts(playButton)

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait))

        // Stoppe Live-Modus
        tapAndHandleAlerts(pauseButton)

        // Prüfe ob Play-Button wieder erscheint
        XCTAssertTrue(waitForCondition(timeout: mediumWait) {
            self.app.buttons["playButton"].exists && !self.app.buttons["pauseButton"].exists
        }, "Play button should reappear after tapping pause")
    }

    @MainActor
    func testRecordButtonTogglesToStop() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))

        // Tippe auf Record
        tapAndHandleAlerts(recordButton)

        // Warte auf Stop-Button (länger Timeout wegen Audio-Engine Start)
        XCTAssertTrue(waitForConditionHandlingAlerts(timeout: longWait) {
            self.app.buttons["stopButton"].exists
        }, "Stop button should appear after tapping record")
    }

    @MainActor
    func testPlayButtonRemainsEnabledDuringRecording() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))

        // Starte Aufnahme
        tapAndHandleAlerts(recordButton)

        XCTAssertTrue(waitForConditionHandlingAlerts(timeout: longWait) { self.app.buttons["stopButton"].exists })
        let stopButton = app.buttons["stopButton"]

        // Play-Button sollte weiter verfügbar sein (nicht disabled)
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.exists, "Play button should exist during recording")
        XCTAssertTrue(playButton.isEnabled, "Play button should remain enabled during recording")

        // Stoppe Aufnahme nach Minimum-Dauer
        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })
        tapAndHandleAlerts(stopButton)
    }

    @MainActor
    func testRecordingsListButtonOpensSheet() throws {
        let listButton = app.buttons["recordingsListButton"]
        XCTAssertTrue(listButton.waitForExistence(timeout: mediumWait))

        // Tippe auf Recordings List Button
        listButton.tap()

        // Prüfe ob Sheet erscheint (z.B. durch Navigation Bar oder Titel)
        // Note: Der genaue Identifier hängt von RecordingsListView ab
        let sheetAppeared = waitForCondition(timeout: mediumWait) {
            self.app.navigationBars.count > 0 || self.app.sheets.count > 0
        }
        XCTAssertTrue(sheetAppeared, "Recordings list sheet should appear")

        // Schließe Sheet wenn möglich
        if let closeButton = app.buttons.matching(identifier: "Fertig").firstMatch.exists ? app.buttons["Fertig"] : nil {
            closeButton.tap()
        } else {
            // Swipe down falls kein Close-Button
            app.swipeDown()
        }
    }

    @MainActor
    func testCompleteRecordingFlow() throws {
        // 1. Starte Aufnahme
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))
        tapAndHandleAlerts(recordButton)

        XCTAssertTrue(waitForConditionHandlingAlerts(timeout: longWait) { self.app.buttons["stopButton"].exists }, "Stop button should appear")
        let stopButton = app.buttons["stopButton"]

        // 2. Warte Minimum-Dauer (5 Sekunden)
        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })

        // 3. Stoppe Aufnahme
        XCTAssertTrue(stopButton.isEnabled, "Stop button should be enabled")
        tapAndHandleAlerts(stopButton)

        // 4. Die App speichert automatisch und kehrt zum Aufnahme-Button zurück.
        XCTAssertTrue(recordButton.waitForExistence(timeout: longWait), "Record button should be available after automatic save")

        // 5. Die gespeicherte Aufnahme sollte in der Aufnahmenliste sichtbar sein.
        let listButton = app.buttons["recordingsListButton"]
        XCTAssertTrue(listButton.waitForExistence(timeout: mediumWait), "Recordings list button should exist")
        listButton.tap()

        let recordingVisible = waitForCondition(timeout: mediumWait) {
            self.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Messung")).count > 0
        }
        XCTAssertTrue(recordingVisible, "Automatically saved recording should appear in the recordings list")
    }

    @MainActor
    func testStatusTextChanges() throws {
        // Prüfe initialer Status "Bereit"
        let bereitLabel = app.staticTexts["Bereit"]
        XCTAssertTrue(bereitLabel.waitForExistence(timeout: mediumWait), "Should show 'Bereit' status initially")

        // Starte Live-Modus
        let playButton = app.buttons["playButton"]
        tapAndHandleAlerts(playButton)

        // Prüfe "Live-Modus" Status
        let liveModeLabel = app.staticTexts["Live-Modus"]
        XCTAssertTrue(liveModeLabel.waitForExistence(timeout: longWait), "Should show 'Live-Modus' status")

        // Stoppe Live-Modus
        let pauseButton = app.buttons["pauseButton"]
        tapAndHandleAlerts(pauseButton)

        // Zurück zu "Bereit"
        XCTAssertTrue(waitForCondition(timeout: mediumWait) {
            self.app.staticTexts["Bereit"].exists
        }, "Should return to 'Bereit' status")
    }

    // MARK: - Visual State Tests

    @MainActor
    func testRecordButtonVisualStateChanges() throws {
        // 1. Initial: Record Button sollte existieren
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))
        XCTAssertTrue(recordButton.exists, "Record button should exist initially")
        XCTAssertFalse(app.buttons["stopButton"].exists, "Stop button should NOT exist initially")

        // 2. Starte Aufnahme → Button sollte zu Stop wechseln
        print("[TEST] Tapping record button...")
        tapAndHandleAlerts(recordButton)

        // Warte und prüfe mehrfach mit längeren Intervallen
        var stopButtonAppeared = false
        for attempt in 1...10 {
            RunLoop.current.run(until: Date().addingTimeInterval(2.0))
            print("[TEST] Attempt \(attempt)/10: Checking for stopButton...")

            if app.buttons["stopButton"].exists {
                stopButtonAppeared = true
                print("[TEST] ✅ Stop button found on attempt \(attempt)!")
                break
            }

            // Debug: Print what buttons DO exist
            let allButtons = app.buttons.allElementsBoundByIndex.compactMap { $0.identifier }
            print("[TEST] Current buttons: \(allButtons)")
        }

        XCTAssertTrue(stopButtonAppeared, "Stop button should appear after tapping record button (waited 20 seconds)")

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.exists, "Stop button must exist")
        XCTAssertFalse(app.buttons["recordButton"].exists, "Record button should NOT exist during recording")

        // 3. Warte Minimum-Dauer
        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })

        // 4. Stoppe Aufnahme → Button sollte zurück zu Record wechseln
        tapAndHandleAlerts(stopButton)

        // Schließe Save-Dialog
        let cancelButton = app.buttons["Abbrechen"]
        if cancelButton.waitForExistence(timeout: mediumWait) {
            cancelButton.tap()
        }

        // 5. Record Button sollte wieder da sein
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait), "Record button should reappear")
        XCTAssertFalse(app.buttons["stopButton"].exists, "Stop button should NOT exist after stopping")
    }

    @MainActor
    func testPlayButtonVisualStateChanges() throws {
        // 1. Initial: Play Button sollte existieren
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))
        XCTAssertTrue(playButton.exists, "Play button should exist initially")
        XCTAssertFalse(app.buttons["pauseButton"].exists, "Pause button should NOT exist initially")

        // 2. Starte Live-Modus → Button sollte zu Pause wechseln
        tapAndHandleAlerts(playButton)

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait), "Pause button should appear")
        XCTAssertFalse(app.buttons["playButton"].exists, "Play button should NOT exist during live mode")

        // 3. Stoppe Live-Modus → Button sollte zurück zu Play wechseln
        tapAndHandleAlerts(pauseButton)

        XCTAssertTrue(waitForCondition(timeout: mediumWait) { self.app.buttons["playButton"].exists }, "Play button should reappear")
        XCTAssertFalse(app.buttons["pauseButton"].exists, "Pause button should NOT exist after stopping")
    }

    @MainActor
    func testStatusTextMatchesButtonStates() throws {
        // Test: Status-Text und Button-States sollten synchron sein

        // 1. Initial: "Bereit" + Play-Button
        XCTAssertTrue(app.staticTexts["Bereit"].exists)
        XCTAssertTrue(app.buttons["playButton"].exists)
        XCTAssertTrue(app.buttons["recordButton"].exists)

        // 2. Live-Modus: "Live-Modus" + Pause-Button
        tapAndHandleAlerts(app.buttons["playButton"])
        XCTAssertTrue(app.staticTexts["Live-Modus"].waitForExistence(timeout: longWait))
        XCTAssertTrue(app.buttons["pauseButton"].exists)
        XCTAssertTrue(app.buttons["recordButton"].exists)

        // 3. Zurück zu Bereit
        tapAndHandleAlerts(app.buttons["pauseButton"])
        XCTAssertTrue(app.staticTexts["Bereit"].waitForExistence(timeout: mediumWait))
        XCTAssertTrue(app.buttons["playButton"].exists)

        // 4. Recording: "Aufnahme läuft" + Stop-Button
        tapAndHandleAlerts(app.buttons["recordButton"])
        XCTAssertTrue(app.staticTexts["Aufnahme läuft"].waitForExistence(timeout: longWait))
        XCTAssertTrue(app.buttons["stopButton"].exists)
        XCTAssertTrue(app.buttons["playButton"].exists)
        XCTAssertTrue(app.buttons["playButton"].isEnabled)

        // Cleanup
        XCTAssertTrue(waitForCondition(timeout: 6) { self.app.buttons["stopButton"].isEnabled })
        tapAndHandleAlerts(app.buttons["stopButton"])
        if app.buttons["Abbrechen"].waitForExistence(timeout: 2) {
            app.buttons["Abbrechen"].tap()
        }
    }
}
