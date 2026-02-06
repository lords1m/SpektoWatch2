//
//  ControlBarViewTests.swift
//  SpektoWatch2Tests
//
//  Tests für die Button-Zustandslogik der ControlBarView
//  HINWEIS: AudioEngine-Tests temporär deaktiviert wegen Memory-Management-Issues
//

import XCTest
@testable import SpektoWatch2

@MainActor
final class ControlBarViewTests: XCTestCase {

    // MARK: - Icon Name Tests

    func testPlayIconWhenIdle() throws {
        let state = ControlBarState(engineStatus: .idle, isRecordingToFile: false)
        XCTAssertEqual(state.playPauseIconName, "play.circle.fill")
    }

    func testPauseIconWhenLive() throws {
        let state = ControlBarState(engineStatus: .running, isRecordingToFile: false)
        XCTAssertEqual(state.playPauseIconName, "pause.circle.fill")
    }

    func testRecordIconWhenNotRecording() throws {
        let state = ControlBarState(engineStatus: .idle, isRecordingToFile: false)
        XCTAssertEqual(state.recordStopIconName, "record.circle")
    }

    func testStopIconWhenRecording() throws {
        let state = ControlBarState(engineStatus: .running, isRecordingToFile: true)
        XCTAssertEqual(state.recordStopIconName, "stop.fill")
    }

    // MARK: - Accessibility Identifier Tests

    func testPlayPauseIdentifierWhenIdle() throws {
        let state = ControlBarState(engineStatus: .idle, isRecordingToFile: false)
        XCTAssertEqual(state.playPauseAccessibilityIdentifier, "playButton")
    }

    func testPlayPauseIdentifierWhenLive() throws {
        let state = ControlBarState(engineStatus: .running, isRecordingToFile: false)
        XCTAssertEqual(state.playPauseAccessibilityIdentifier, "pauseButton")
    }

    func testRecordStopIdentifierWhenNotRecording() throws {
        let state = ControlBarState(engineStatus: .idle, isRecordingToFile: false)
        XCTAssertEqual(state.recordStopAccessibilityIdentifier, "recordButton")
    }

    func testRecordStopIdentifierWhenRecording() throws {
        let state = ControlBarState(engineStatus: .running, isRecordingToFile: true)
        XCTAssertEqual(state.recordStopAccessibilityIdentifier, "stopButton")
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
            let engineStatus: EngineStatus = state.engineRunning ? .running : .idle
            let controlBarState = ControlBarState(engineStatus: engineStatus, isRecordingToFile: state.isRecordingToFile)

            XCTAssertEqual(controlBarState.isLiveMode, state.expectedLiveMode,
                          "LiveMode mismatch for engineRunning=\(state.engineRunning), isRecordingToFile=\(state.isRecordingToFile)")
            XCTAssertEqual(controlBarState.isRecording, state.expectedRecording,
                          "Recording mismatch for engineRunning=\(state.engineRunning), isRecordingToFile=\(state.isRecordingToFile)")
        }
    }
}
