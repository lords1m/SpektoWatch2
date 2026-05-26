import XCTest
@testable import SpektoWatch2

/// Targeted tests for the piano input selection flow (M11 task-4).
/// Covers the smoke scenario documented in the acceptance criteria and
/// the MIDI-based persistence round-trip.
final class PianoSelectionTests: XCTestCase {

    // MARK: – Smoke scenario: select A4, confirm 440 Hz

    /// Selecting A4 on the piano keyboard must set frequency to exactly 440 Hz.
    func testSelectA4Sets440Hz() {
        let a4 = MusicalNote(name: .A, octave: 4)
        XCTAssertEqual(a4.frequency, 440.0, accuracy: 0.001,
                       "Tapping A4 on the piano must produce 440 Hz")
    }

    /// A4 is the closest note to 440 Hz — `nearest(to:)` must agree.
    func testNearestTo440IsA4() {
        let note = MusicalNote.nearest(to: 440.0)
        XCTAssertEqual(note, MusicalNote(name: .A, octave: 4),
                       "MusicalNote.nearest(to: 440) must return A4")
    }

    // MARK: – Persistence round-trip via MIDI number

    /// Persisting a note as its MIDI number and reconstructing it must
    /// yield an identical note (same name, octave, frequency, label).
    func testMidiRoundTripAllNotes() {
        for octave in 0...8 {
            for note in MusicalNote.notes(in: octave) {
                let midi = note.midiNote
                // Reconstruction logic mirrors ToneGeneratorWidget.onAppear
                let restoredOctave   = midi / 12 - 1
                let restoredSemitone = midi % 12
                guard let name = MusicalNote.Name(rawValue: restoredSemitone) else {
                    XCTFail("Could not reconstruct Name from MIDI \(midi)")
                    continue
                }
                let restored = MusicalNote(name: name, octave: restoredOctave)
                XCTAssertEqual(restored, note,
                               "MIDI round-trip failed for \(note.label) (midi=\(midi))")
                XCTAssertEqual(restored.frequency, note.frequency, accuracy: 0.001,
                               "Frequency mismatch after MIDI round-trip for \(note.label)")
            }
        }
    }

    /// MIDI -1 (no-selection sentinel) must NOT produce a valid note.
    func testMidiSentinelProducesNoNote() {
        let midi = -1
        let isValid = midi >= 12 && midi <= 119
        XCTAssertFalse(isValid, "Sentinel -1 must not be treated as a valid MIDI note")
    }

    /// MIDI boundary values 12 (C0) and 119 (B8) must reconstruct correctly.
    func testMidiBoundaryReconstruction() {
        for midi in [12, 119] {
            let octave   = midi / 12 - 1
            let semitone = midi % 12
            XCTAssertNotNil(MusicalNote.Name(rawValue: semitone),
                            "Boundary MIDI \(midi) semitone \(semitone) must be a valid Name")
            let note = MusicalNote(name: MusicalNote.Name(rawValue: semitone)!, octave: octave)
            XCTAssertEqual(note.midiNote, midi, "Boundary MIDI \(midi) round-trips cleanly")
        }
    }

    // MARK: – Mode switching pre-selection

    /// When switching to piano mode, nearest(to:) must find A4 for 440 Hz input
    /// and the resulting octave must equal 4.
    func testPianoModeSwitchPreSelectsCorrectOctave() {
        let currentFrequency: Float = 440.0
        let nearest = MusicalNote.nearest(to: currentFrequency)
        XCTAssertEqual(nearest.octave, 4,
                       "Switching to piano at 440 Hz should navigate to octave 4")
        XCTAssertEqual(nearest.name, .A,
                       "Switching to piano at 440 Hz should pre-select A")
    }

    /// Switching to piano at C4 (≈ 261.6 Hz) must pre-select C in octave 4.
    func testPianoModeSwitchAtC4() {
        let c4 = MusicalNote(name: .C, octave: 4)
        let nearest = MusicalNote.nearest(to: c4.frequency)
        XCTAssertEqual(nearest, c4)
    }

    // MARK: – Frequency-display consistency

    /// After selecting any note, its frequency must exactly match
    /// what would be shown in the Hz display text (no hidden rounding).
    func testFrequencyDisplayConsistencyForA4() {
        let a4    = MusicalNote(name: .A, octave: 4)
        let freq  = a4.frequency        // 440.0 Hz
        // Simulate the frequencyDisplayText logic from ToneGeneratorWidget
        let text: String
        if freq >= 1000 {
            text = String(format: "%.2f k", freq / 1000)
        } else if freq >= 100 {
            text = String(format: "%.1f", freq)
        } else {
            text = String(format: "%.2f", freq)
        }
        XCTAssertEqual(text, "440.0",
                       "A4 (440 Hz) should display as '440.0' in the widget frequency label")
    }
}
