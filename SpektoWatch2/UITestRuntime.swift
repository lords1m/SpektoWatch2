#if DEBUG
import Foundation

/// Launch-argument configuration shared by UI tests and DEBUG app code.
enum UITestRuntime {
    /// When true, `AudioEngine` uses the synthetic test generator instead of
    /// `AVAudioEngine` + microphone permission (stable in XCUITest / CI).
    private(set) static var useTestAudio = false

    static func configureFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        useTestAudio = arguments.contains("-UseTestAudio")
            || arguments.contains("-ResetState")
    }
}
#endif
