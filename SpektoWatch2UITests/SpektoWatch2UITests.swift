//
//  SpektoWatch2UITests.swift
//  SpektoWatch2UITests
//
//  Created by Simeon Brandt on 31.01.26.
//

import XCTest

final class SpektoWatch2UITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UIAnimationsDisabled", "YES"]
        app.launch()
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
        XCTAssertTrue(playButton.waitForExistence(timeout: 5), "Play button should exist")
    }

    @MainActor
    func testRecordButtonExists() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
    }

    @MainActor
    func testRecordingsListButtonExists() throws {
        let listButton = app.buttons["recordingsListButton"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 5), "Recordings list button should exist")
    }

    @MainActor
    func testPlayButtonTogglesToPause() throws {
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))

        // Tippe auf Play
        playButton.tap()

        // Warte kurz und prüfe ob Pause-Button erscheint
        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3), "Pause button should appear after tapping play")
    }

    @MainActor
    func testPauseButtonTogglesBackToPlay() throws {
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))

        // Starte Live-Modus
        playButton.tap()

        let pauseButton = app.buttons["pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))

        // Stoppe Live-Modus
        pauseButton.tap()

        // Prüfe ob Play-Button wieder erscheint
        XCTAssertTrue(playButton.waitForExistence(timeout: 3), "Play button should reappear after tapping pause")
    }

    @MainActor
    func testRecordButtonTogglesToStop() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))

        // Tippe auf Record
        recordButton.tap()

        // Warte kurz und prüfe ob Stop-Button erscheint
        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3), "Stop button should appear after tapping record")
    }

    @MainActor
    func testPlayButtonDisabledDuringRecording() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))

        // Starte Aufnahme
        recordButton.tap()

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))

        // Prüfe ob Play-Button deaktiviert ist
        let playButton = app.buttons["playButton"]
        XCTAssertFalse(playButton.isEnabled, "Play button should be disabled during recording")

        // Stoppe Aufnahme nach Minimum-Dauer
        Thread.sleep(forTimeInterval: 5.5)
        stopButton.tap()
    }

    @MainActor
    func testStopButtonDisabledDuringFirstFiveSeconds() throws {
        let recordButton = app.buttons["recordButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))

        // Starte Aufnahme
        recordButton.tap()

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3))

        // Prüfe ob Stop-Button in den ersten 5 Sekunden deaktiviert ist
        XCTAssertFalse(stopButton.isEnabled, "Stop button should be disabled during first 5 seconds")

        // Warte 5.5 Sekunden
        Thread.sleep(forTimeInterval: 5.5)

        // Jetzt sollte der Stop-Button aktiviert sein
        XCTAssertTrue(stopButton.isEnabled, "Stop button should be enabled after 5 seconds")

        // Aufräumen: Stoppe Aufnahme
        stopButton.tap()

        // Schließe Save-Dialog falls vorhanden
        let cancelButton = app.buttons["Abbrechen"]
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        }
    }

    @MainActor
    func testRecordingsListButtonOpensSheet() throws {
        let listButton = app.buttons["recordingsListButton"]
        XCTAssertTrue(listButton.waitForExistence(timeout: 5))

        // Tippe auf Recordings List Button
        listButton.tap()

        // Prüfe ob Sheet erscheint (z.B. durch Navigation Bar oder Titel)
        // Note: Der genaue Identifier hängt von RecordingsListView ab
        let sheetAppeared = app.navigationBars.count > 0 || app.sheets.count > 0
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
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        recordButton.tap()

        let stopButton = app.buttons["stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 3), "Stop button should appear")

        // 2. Warte Minimum-Dauer (5 Sekunden)
        Thread.sleep(forTimeInterval: 5.5)

        // 3. Stoppe Aufnahme
        XCTAssertTrue(stopButton.isEnabled, "Stop button should be enabled")
        stopButton.tap()

        // 4. Save-Dialog sollte erscheinen
        let saveDialog = app.sheets.firstMatch
        XCTAssertTrue(saveDialog.waitForExistence(timeout: 3), "Save dialog should appear")

        // 5. Abbrechen oder Speichern
        let cancelButton = app.buttons["Abbrechen"]
        if cancelButton.exists {
            cancelButton.tap()
        }

        // 6. Play-Button sollte wieder verfügbar sein
        XCTAssertTrue(recordButton.waitForExistence(timeout: 2), "Record button should be available again")
    }

    @MainActor
    func testStatusTextChanges() throws {
        // Prüfe initialer Status "Bereit"
        let bereitLabel = app.staticTexts["Bereit"]
        XCTAssertTrue(bereitLabel.waitForExistence(timeout: 5), "Should show 'Bereit' status initially")

        // Starte Live-Modus
        let playButton = app.buttons["playButton"]
        playButton.tap()

        // Prüfe "Live-Modus" Status
        let liveModeLabel = app.staticTexts["Live-Modus"]
        XCTAssertTrue(liveModeLabel.waitForExistence(timeout: 3), "Should show 'Live-Modus' status")

        // Stoppe Live-Modus
        let pauseButton = app.buttons["pauseButton"]
        pauseButton.tap()

        // Zurück zu "Bereit"
        XCTAssertTrue(bereitLabel.waitForExistence(timeout: 3), "Should return to 'Bereit' status")
    }
}
