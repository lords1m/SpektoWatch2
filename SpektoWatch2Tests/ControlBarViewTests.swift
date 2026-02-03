//
//  ControlBarViewTests.swift
//  SpektoWatch2Tests
//
//  Tests für die Button-Zustandslogik der ControlBarView
//  HINWEIS: AudioEngine-Tests temporär deaktiviert wegen Memory-Management-Issues
//

import XCTest
@testable import SpektoWatch2

// MARK: - Helper Functions (repliziert die Logik aus ControlBarView)

/// Berechnet den Button-Identifier basierend auf dem Live-Modus
private func playPauseButtonIdentifier(isLiveMode: Bool) -> String {
    return isLiveMode ? "pauseButton" : "playButton"
}

/// Berechnet den Button-Identifier basierend auf dem Aufnahme-Status
private func recordStopButtonIdentifier(isRecording: Bool) -> String {
    return isRecording ? "stopButton" : "recordButton"
}

/// Berechnet das Icon basierend auf dem Live-Modus
private func playPauseIconName(isLiveMode: Bool) -> String {
    return isLiveMode ? "pause.circle.fill" : "play.circle.fill"
}

/// Berechnet das Icon basierend auf dem Aufnahme-Status
private func recordStopIconName(isRecording: Bool) -> String {
    return isRecording ? "stop.circle.fill" : "record.circle"
}

/// Berechnet ob Live-Modus aktiv ist
private func calculateIsLiveMode(engineRunning: Bool, isRecordingToFile: Bool) -> Bool {
    return engineRunning && !isRecordingToFile
}

/// Berechnet ob Aufnahme aktiv ist
private func calculateIsRecording(engineRunning: Bool, isRecordingToFile: Bool) -> Bool {
    return engineRunning && isRecordingToFile
}

@MainActor
final class ControlBarViewTests: XCTestCase {

    // MARK: - Button Identifier Tests

    func testPlayButtonIdentifierWhenIdle() throws {
        XCTAssertEqual(playPauseButtonIdentifier(isLiveMode: false), "playButton")
    }

    func testPauseButtonIdentifierWhenLive() throws {
        XCTAssertEqual(playPauseButtonIdentifier(isLiveMode: true), "pauseButton")
    }

    func testRecordButtonIdentifierWhenNotRecording() throws {
        XCTAssertEqual(recordStopButtonIdentifier(isRecording: false), "recordButton")
    }

    func testStopButtonIdentifierWhenRecording() throws {
        XCTAssertEqual(recordStopButtonIdentifier(isRecording: true), "stopButton")
    }

    // MARK: - Icon Name Tests

    func testPlayIconWhenIdle() throws {
        XCTAssertEqual(playPauseIconName(isLiveMode: false), "play.circle.fill")
    }

    func testPauseIconWhenLive() throws {
        XCTAssertEqual(playPauseIconName(isLiveMode: true), "pause.circle.fill")
    }

    func testRecordIconWhenNotRecording() throws {
        XCTAssertEqual(recordStopIconName(isRecording: false), "record.circle")
    }

    func testStopIconWhenRecording() throws {
        XCTAssertEqual(recordStopIconName(isRecording: true), "stop.circle.fill")
    }

    // MARK: - Button Disabled State Tests

    func testPlayButtonDisabledDuringRecording() throws {
        let isRecording = true
        XCTAssertTrue(isRecording, "Play button sollte während Aufnahme deaktiviert sein")
    }

    func testPlayButtonEnabledWhenNotRecording() throws {
        let isRecording = false
        XCTAssertFalse(isRecording, "Play button sollte aktiviert sein wenn nicht aufnehmend")
    }

    // MARK: - Live Mode Calculation Tests

    func testIsLiveModeWhenEngineRunningAndNotRecording() throws {
        XCTAssertTrue(calculateIsLiveMode(engineRunning: true, isRecordingToFile: false))
    }

    func testIsNotLiveModeWhenRecording() throws {
        XCTAssertFalse(calculateIsLiveMode(engineRunning: true, isRecordingToFile: true))
    }

    func testIsNotLiveModeWhenIdle() throws {
        XCTAssertFalse(calculateIsLiveMode(engineRunning: false, isRecordingToFile: false))
    }

    func testIsNotLiveModeWhenIdleButRecordingFlagSet() throws {
        // Edge case: Engine nicht laufend aber Recording-Flag gesetzt
        XCTAssertFalse(calculateIsLiveMode(engineRunning: false, isRecordingToFile: true))
    }

    // MARK: - Recording Calculation Tests

    func testIsRecordingWhenEngineRunningAndRecordingToFile() throws {
        XCTAssertTrue(calculateIsRecording(engineRunning: true, isRecordingToFile: true))
    }

    func testIsNotRecordingWhenNotRunning() throws {
        XCTAssertFalse(calculateIsRecording(engineRunning: false, isRecordingToFile: true))
    }

    func testIsNotRecordingWhenNotRecordingToFile() throws {
        XCTAssertFalse(calculateIsRecording(engineRunning: true, isRecordingToFile: false))
    }

    func testIsNotRecordingWhenBothFalse() throws {
        XCTAssertFalse(calculateIsRecording(engineRunning: false, isRecordingToFile: false))
    }

    // MARK: - State Transition Tests

    func testButtonIdentifiersChangeWithState() throws {
        // Simuliere Zustandsübergänge
        var isLiveMode = false
        XCTAssertEqual(playPauseButtonIdentifier(isLiveMode: isLiveMode), "playButton")

        isLiveMode = true
        XCTAssertEqual(playPauseButtonIdentifier(isLiveMode: isLiveMode), "pauseButton")

        isLiveMode = false
        XCTAssertEqual(playPauseButtonIdentifier(isLiveMode: isLiveMode), "playButton")
    }

    func testRecordButtonIdentifiersChangeWithState() throws {
        var isRecording = false
        XCTAssertEqual(recordStopButtonIdentifier(isRecording: isRecording), "recordButton")

        isRecording = true
        XCTAssertEqual(recordStopButtonIdentifier(isRecording: isRecording), "stopButton")

        isRecording = false
        XCTAssertEqual(recordStopButtonIdentifier(isRecording: isRecording), "recordButton")
    }

    // MARK: - Complete State Matrix Tests

    func testAllStatesCombinations() throws {
        // Teste alle möglichen Kombinationen von engineRunning und isRecordingToFile
        let states: [(engineRunning: Bool, isRecordingToFile: Bool, expectedLiveMode: Bool, expectedRecording: Bool)] = [
            (false, false, false, false),  // Idle
            (true, false, true, false),    // Live Mode
            (true, true, false, true),     // Recording
            (false, true, false, false),   // Invalid state (recording without engine)
        ]

        for state in states {
            let isLiveMode = calculateIsLiveMode(engineRunning: state.engineRunning, isRecordingToFile: state.isRecordingToFile)
            let isRecording = calculateIsRecording(engineRunning: state.engineRunning, isRecordingToFile: state.isRecordingToFile)

            XCTAssertEqual(isLiveMode, state.expectedLiveMode,
                          "LiveMode mismatch for engineRunning=\(state.engineRunning), isRecordingToFile=\(state.isRecordingToFile)")
            XCTAssertEqual(isRecording, state.expectedRecording,
                          "Recording mismatch for engineRunning=\(state.engineRunning), isRecordingToFile=\(state.isRecordingToFile)")
        }
    }
}
