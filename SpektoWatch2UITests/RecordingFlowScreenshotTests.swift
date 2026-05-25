import XCTest

/// Screenshots for the recording lifecycle: idle → in-progress → stopped.
///
/// Launch arguments:
///   `-SeedTestData YES` — seeds pre-existing recordings in the recordings list.
///   Microphone access is requested at runtime; on CI devices without a mic the
///   recording-start button remains visible and is photographed regardless.
final class RecordingFlowScreenshotTests: XCTestCase {

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
            "Dashboard controls should be visible"
        )
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testRecordingFlowScreenshots() throws {
        // 01 — dashboard idle state (record button visible)
        XCTContext.runActivity(named: "01-Dashboard-Idle") { _ in
            capture("01-Dashboard-Idle")
        }

        // 02 — tap record; some CI environments deny the mic, so the
        // button state change is the assertion, not actual audio capture.
        let recordButton = app.buttons["playButton"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: viewWait))
        XCTContext.runActivity(named: "02-Recording-Start-Tap") { _ in
            recordButton.tap()
            settle(1.0)
            capture("02-Recording-Start-Tap")
        }

        // 03 — in-progress state (stop button should be visible)
        let stopButton = app.buttons["stopButton"]
        XCTContext.runActivity(named: "03-Recording-InProgress") { _ in
            if stopButton.waitForExistence(timeout: viewWait) {
                settle(0.5)
                capture("03-Recording-InProgress")
            } else {
                // Mic denied or recording failed — capture current state anyway
                capture("03-Recording-InProgress-MicUnavailable")
            }
        }

        // 04 — tap stop (if in-progress)
        XCTContext.runActivity(named: "04-Recording-Stop") { _ in
            if stopButton.exists {
                stopButton.tap()
                settle(1.5)
                capture("04-Recording-Stopped")
            }
        }

        // 05 — navigate to recordings list and open the new (or first) recording
        let recordingsButton = app.buttons["recordingsListButton"]
        XCTContext.runActivity(named: "05-Recording-Detail") { _ in
            if recordingsButton.waitForExistence(timeout: viewWait) {
                recordingsButton.tap()
                settle()
                capture("05-Recordings-List-After-Stop")

                let firstCell = app.cells.element(boundBy: 0)
                if firstCell.waitForExistence(timeout: viewWait) {
                    firstCell.tap()
                    if app.navigationBars.firstMatch.waitForExistence(timeout: viewWait) {
                        settle()
                        capture("05b-Recording-Detail")
                    }
                }
            }
        }
    }
}
