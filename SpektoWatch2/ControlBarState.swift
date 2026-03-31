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

    var playPauseAccessibilityLabel: String {
        isLiveMode ? "Pause" : "Play"
    }

    var recordStopAccessibilityLabel: String {
        isRecording ? "Stop" : "Aufnahme"
    }
}
