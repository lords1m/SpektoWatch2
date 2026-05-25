import XCTest

/// Screenshots for the playback weighting picker in the recording detail.
///
/// Cycles through Z / A / C / Z (back to default) and captures each state.
///
/// Launch arguments:
///   `-SeedTestData YES` — ensures a recording is available.
final class WeightingPickerScreenshotTests: XCTestCase {

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
    func testWeightingPickerScreenshots() throws {
        // Navigate to first recording detail
        let recordingsButton = app.buttons["recordingsListButton"]
        guard recordingsButton.waitForExistence(timeout: viewWait) else {
            XCTFail("Recordings button not found")
            return
        }
        recordingsButton.tap()
        settle()

        let firstCell = app.cells.element(boundBy: 0)
        guard firstCell.waitForExistence(timeout: viewWait) else {
            XCTFail("No seeded recording found")
            return
        }
        firstCell.tap()
        guard app.navigationBars.firstMatch.waitForExistence(timeout: viewWait) else {
            XCTFail("Recording detail did not open")
            return
        }
        settle()
        XCTContext.runActivity(named: "01-WeightingZ-Default") { _ in
            capture("01-WeightingZ-Default")
        }

        // Cycle through A, C, then back to Z weighting
        let weightings: [(String, String)] = [
            ("weightingButtonA", "02-WeightingA"),
            ("weightingButtonC", "03-WeightingC"),
            ("weightingButtonZ", "04-WeightingZ-Restored"),
        ]

        for (identifier, shotName) in weightings {
            XCTContext.runActivity(named: shotName) { _ in
                let button = app.buttons[identifier]
                if button.waitForExistence(timeout: viewWait) {
                    button.tap()
                    settle()
                    capture(shotName)
                } else {
                    // Weighting picker may be labelled by text rather than identifier
                    let label = identifier
                        .replacingOccurrences(of: "weightingButton", with: "")
                    let textButton = app.buttons[label]
                    if textButton.waitForExistence(timeout: 2.0) {
                        textButton.tap()
                        settle()
                    }
                    capture(shotName)
                }
            }
        }
    }
}
