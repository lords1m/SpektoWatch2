import XCTest

/// Screenshots for the export flow: PDF, CSV, and spectrogram PNG.
///
/// Launch arguments:
///   `-SeedTestData YES` — ensures at least one recording is present so the
///   recordings list and recording detail are reachable.
final class ExportFlowScreenshotTests: XCTestCase {

    private var app: XCUIApplication!
    private let launchWait: TimeInterval = 60
    private let viewWait: TimeInterval = 12

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-UIAnimationsDisabled", "YES",
            "-SeedTestData", "YES",
        ]
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: launchWait),
            "App should be running"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["playButton"].waitForExistence(timeout: launchWait),
            "Dashboard should be visible"
        )
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testExportFlowScreenshots() throws {
        // Navigate to recordings list → first recording detail
        let recordingsButton = app.buttons["recordingsListButton"]
        guard recordingsButton.waitForExistence(timeout: viewWait) else {
            XCTFail("Recordings button not found")
            return
        }
        recordingsButton.tap()
        settle()

        let firstCell = app.cells.element(boundBy: 0)
        guard firstCell.waitForExistence(timeout: viewWait) else {
            XCTFail("No seeded recording found in list")
            return
        }
        firstCell.tap()
        guard app.navigationBars.firstMatch.waitForExistence(timeout: viewWait) else {
            XCTFail("Recording detail did not open")
            return
        }
        settle()
        XCTContext.runActivity(named: "01-RecordingDetail-Base") { _ in
            capture("01-RecordingDetail-Base")
        }

        // 02 — PDF export
        let pdfButton = app.buttons["exportPDFButton"]
        XCTContext.runActivity(named: "02-Export-PDF") { _ in
            if pdfButton.waitForExistence(timeout: viewWait) {
                pdfButton.tap()
                settle()
                capture("02-Export-PDF-Overlay")
                // Dismiss
                let cancelButton = app.buttons["Abbrechen"]
                if cancelButton.waitForExistence(timeout: viewWait) {
                    cancelButton.tap()
                    settle()
                    capture("02b-Export-PDF-Dismissed")
                }
            } else {
                capture("02-Export-PDF-ButtonNotFound")
            }
        }

        // 03 — CSV export
        let csvButton = app.buttons["exportCSVButton"]
        XCTContext.runActivity(named: "03-Export-CSV") { _ in
            if csvButton.waitForExistence(timeout: viewWait) {
                csvButton.tap()
                settle()
                capture("03-Export-CSV-Overlay")
                let cancelButton = app.buttons["Abbrechen"]
                if cancelButton.waitForExistence(timeout: viewWait) {
                    cancelButton.tap()
                    settle()
                    capture("03b-Export-CSV-Dismissed")
                }
            } else {
                capture("03-Export-CSV-ButtonNotFound")
            }
        }

        // 04 — Spectrogram PNG export
        let spectrogramButton = app.buttons["exportSpectrogramButton"]
        XCTContext.runActivity(named: "04-Export-Spectrogram") { _ in
            if spectrogramButton.waitForExistence(timeout: viewWait) {
                spectrogramButton.tap()
                settle()
                capture("04-Export-Spectrogram-Overlay")
                let cancelButton = app.buttons["Abbrechen"]
                if cancelButton.waitForExistence(timeout: viewWait) {
                    cancelButton.tap()
                    settle()
                    capture("04b-Export-Spectrogram-Dismissed")
                }
            } else {
                capture("04-Export-Spectrogram-ButtonNotFound")
            }
        }
    }
}
