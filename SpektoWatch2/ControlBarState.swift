import SwiftUI

struct ControlBarState: Equatable {
    let engineStatus: EngineStatus
    let isRecordingToFile: Bool

    var engineRunning: Bool {
        engineStatus == .running
    }

    var isLiveMode: Bool {
        engineRunning && !isRecordingToFile
    }

    var isRecording: Bool {
        isRecordingToFile && (engineStatus == .running || engineStatus == .starting)
    }

    var playPauseIconName: String {
        isLiveMode ? "pause.circle.fill" : "play.circle.fill"
    }

    var recordStopIconName: String {
        isRecording ? "stop.fill" : "record.circle"
    }

    var playPauseAccessibilityIdentifier: String {
        isLiveMode ? "pauseButton" : "playButton"
    }

    var recordStopAccessibilityIdentifier: String {
        isRecording ? "stopButton" : "recordButton"
    }

    var isStartingRecording: Bool {
        engineStatus == .starting && isRecordingToFile
    }

    var playPauseAccessibilityLabel: String {
        isLiveMode
            ? String(localized: "live_mode.action.stop")
            : String(localized: "live_mode.action.start")
    }

    var recordStopAccessibilityLabel: String {
        if isStartingRecording {
            return String(localized: "recording.action.cancel_start")
        }
        return isRecording
            ? String(localized: "recording.action.stop")
            : String(localized: "recording.action.start")
    }
}
