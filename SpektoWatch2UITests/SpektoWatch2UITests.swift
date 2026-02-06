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
    private let pollInterval: TimeInterval = 0.2

    // MARK: - Helpers

    private func waitForCondition(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
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

        // Launch app
        self.app.launch()

        // CRITICAL: Handle microphone permission dialog
        // This must happen immediately after launch
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // Try both German and English button labels
        var permissionGranted = false
        let allowButton = springboard.buttons["Allow"]
        let erlaubenButton = springboard.buttons["Erlauben"]

        if allowButton.waitForExistence(timeout: 5) {
            print("[Test Setup] Microphone permission dialog appeared (English), tapping Allow...")
            allowButton.tap()
            permissionGranted = true
            Thread.sleep(forTimeInterval: 0.5)
        } else if erlaubenButton.waitForExistence(timeout: 1) {
            print("[Test Setup] Microphone permission dialog appeared (German), tapping Erlauben...")
            erlaubenButton.tap()
            permissionGranted = true
            Thread.sleep(forTimeInterval: 0.5)
        }

        if !permissionGranted {
            print("[Test Setup] No permission dialog appeared - might already be granted")
        }

        // Warte bis die App vollständig geladen ist
        _ = waitForCondition(timeout: mediumWait) {
            self.app.state == .runningForeground
        }

        // Verify app is in foreground
        XCTAssertTrue(self.app.wait(for: .runningForeground, timeout: mediumWait), "App should be running in foreground")

        // Verify initial UI elements are present
        XCTAssertTrue(self.app.buttons["playButton"].waitForExistence(timeout: mediumWait), "Play button should exist after setup")
        XCTAssertTrue(self.app.buttons["recordButton"].waitForExistence(timeout: mediumWait), "Record button should exist after setup")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - App Launch Test

    @MainActor
    func testAppLaunches() throws {
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
        playButton.tap()

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait))
        pauseButton.tap()

        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait))

        // Record -> Stop -> Record
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))
        recordButton.tap()

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: longWait))

        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })
        stopButton.tap()

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
        playButton.tap()

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
        playButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait))

        // Stoppe Live-Modus
        pauseButton.tap()

        // Prüfe ob Play-Button wieder erscheint
        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait), "Play button should reappear after tapping pause")
    }

    @MainActor
    func testRecordButtonTogglesToStop() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))

        // Tippe auf Record
        recordButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        // Warte auf Stop-Button (länger Timeout wegen Audio-Engine Start)
        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: longWait), "Stop button should appear after tapping record")
    }

    @MainActor
    func testPlayButtonRemainsEnabledDuringRecording() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait))

        // Starte Aufnahme
        recordButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: longWait))

        // Play-Button sollte weiter verfügbar sein (nicht disabled)
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.exists, "Play button should exist during recording")
        XCTAssertTrue(playButton.isEnabled, "Play button should remain enabled during recording")

        // Stoppe Aufnahme nach Minimum-Dauer
        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })
        stopButton.tap()
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
        recordButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: longWait), "Stop button should appear")

        // 2. Warte Minimum-Dauer (5 Sekunden)
        XCTAssertTrue(waitForCondition(timeout: 6) { stopButton.isEnabled })

        // 3. Stoppe Aufnahme
        XCTAssertTrue(stopButton.isEnabled, "Stop button should be enabled")
        stopButton.tap()

        // 4. Save-Dialog sollte erscheinen
        let saveDialog = app.sheets.firstMatch
        XCTAssertTrue(saveDialog.waitForExistence(timeout: mediumWait), "Save dialog should appear")

        // 5. Abbrechen oder Speichern
        let cancelButton = app.buttons["Abbrechen"]
        if cancelButton.exists {
            cancelButton.tap()
        }

        // 6. Play-Button sollte wieder verfügbar sein
        XCTAssertTrue(recordButton.waitForExistence(timeout: mediumWait), "Record button should be available again")
    }

    @MainActor
    func testStatusTextChanges() throws {
        // Prüfe initialer Status "Bereit"
        let bereitLabel = app.staticTexts["Bereit"]
        XCTAssertTrue(bereitLabel.waitForExistence(timeout: mediumWait), "Should show 'Bereit' status initially")

        // Starte Live-Modus
        let playButton = app.buttons["playButton"]
        playButton.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        // Prüfe "Live-Modus" Status
        let liveModeLabel = app.staticTexts["Live-Modus"]
        XCTAssertTrue(liveModeLabel.waitForExistence(timeout: longWait), "Should show 'Live-Modus' status")

        // Stoppe Live-Modus
        let pauseButton = app.buttons["pauseButton"]
        pauseButton.tap()

        // Zurück zu "Bereit"
        XCTAssertTrue(bereitLabel.waitForExistence(timeout: mediumWait), "Should return to 'Bereit' status")
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
        recordButton.tap()

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
        stopButton.tap()

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
        playButton.tap()

        // Kurze Pause für UI-Update und AudioEngine-Start
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: longWait), "Pause button should appear")
        XCTAssertFalse(app.buttons["playButton"].exists, "Play button should NOT exist during live mode")

        // 3. Stoppe Live-Modus → Button sollte zurück zu Play wechseln
        pauseButton.tap()

        XCTAssertTrue(playButton.waitForExistence(timeout: mediumWait), "Play button should reappear")
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
        app.buttons["playButton"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))
        XCTAssertTrue(app.staticTexts["Live-Modus"].waitForExistence(timeout: longWait))
        XCTAssertTrue(app.buttons["pauseButton"].exists)
        XCTAssertTrue(app.buttons["recordButton"].exists)

        // 3. Zurück zu Bereit
        app.buttons["pauseButton"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))
        XCTAssertTrue(app.staticTexts["Bereit"].waitForExistence(timeout: mediumWait))
        XCTAssertTrue(app.buttons["playButton"].exists)

        // 4. Recording: "Aufnahme läuft" + Stop-Button
        app.buttons["recordButton"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(shortWait))
        XCTAssertTrue(app.staticTexts["Aufnahme läuft"].waitForExistence(timeout: longWait))
        XCTAssertTrue(app.buttons["stopButton"].exists)
        XCTAssertTrue(app.buttons["playButton"].exists)
        XCTAssertTrue(app.buttons["playButton"].isEnabled)

        // Cleanup
        XCTAssertTrue(waitForCondition(timeout: 6) { self.app.buttons["stopButton"].isEnabled })
        app.buttons["stopButton"].tap()
        if app.buttons["Abbrechen"].waitForExistence(timeout: 2) {
            app.buttons["Abbrechen"].tap()
        }
    }
}
