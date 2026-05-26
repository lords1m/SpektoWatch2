import XCTest
@testable import SpektoWatch2

/// Unit tests for MusicalNote model (M11 task-2).
/// Covers frequency accuracy, octave relationships, labels, and MIDI numbering.
final class NoteFrequencyModelTests: XCTestCase {

    // MARK: – Frequency accuracy

    func testA4Is440Hz() {
        let a4 = MusicalNote(name: .A, octave: 4)
        XCTAssertEqual(a4.frequency, 440.0, accuracy: 0.001,
                       "A4 must be exactly 440 Hz in equal-temperament tuning")
    }

    func testC4IsMiddleC() {
        // C4 = MIDI 60, f = 440 × 2^((60−69)/12) ≈ 261.626 Hz
        let c4 = MusicalNote(name: .C, octave: 4)
        XCTAssertEqual(c4.frequency, 261.626, accuracy: 0.001)
    }

    func testA4StaticReferenceMatchesInstance() {
        XCTAssertEqual(MusicalNote.a4.frequency, MusicalNote(name: .A, octave: 4).frequency)
    }

    // MARK: – Octave relationships

    func testOctaveAboveDoubles() {
        let a4 = MusicalNote(name: .A, octave: 4)
        let a5 = MusicalNote(name: .A, octave: 5)
        XCTAssertEqual(a5.frequency, a4.frequency * 2.0, accuracy: 0.001,
                       "One octave up should double the frequency")
    }

    func testOctaveBelowHalves() {
        let a4 = MusicalNote(name: .A, octave: 4)
        let a3 = MusicalNote(name: .A, octave: 3)
        XCTAssertEqual(a3.frequency, a4.frequency / 2.0, accuracy: 0.001,
                       "One octave down should halve the frequency")
    }

    func testC0LowestSupported() {
        // C0 = MIDI 12, f ≈ 16.352 Hz
        let c0 = MusicalNote(name: .C, octave: 0)
        XCTAssertEqual(c0.frequency, 16.352, accuracy: 0.001)
    }

    func testB8HighestSupported() {
        // B8 = MIDI 119, f ≈ 7902.133 Hz
        let b8 = MusicalNote(name: .B, octave: 8)
        XCTAssertEqual(b8.frequency, 7902.133, accuracy: 0.5)
    }

    // MARK: – MIDI numbering

    func testMidiNoteA4() {
        XCTAssertEqual(MusicalNote(name: .A, octave: 4).midiNote, 69)
    }

    func testMidiNoteC4() {
        XCTAssertEqual(MusicalNote(name: .C, octave: 4).midiNote, 60)
    }

    func testMidiNoteC0() {
        XCTAssertEqual(MusicalNote(name: .C, octave: 0).midiNote, 12)
    }

    func testMidiNoteB8() {
        XCTAssertEqual(MusicalNote(name: .B, octave: 8).midiNote, 119)
    }

    // MARK: – Display labels

    func testLabelNaturalNote() {
        XCTAssertEqual(MusicalNote(name: .A, octave: 4).label, "A4")
    }

    func testLabelSharpNote() {
        XCTAssertEqual(MusicalNote(name: .Cs, octave: 3).label, "C#3")
    }

    func testLabelLowest() {
        XCTAssertEqual(MusicalNote(name: .C, octave: 0).label, "C0")
    }

    func testIdEqualsLabel() {
        let note = MusicalNote(name: .Fs, octave: 5)
        XCTAssertEqual(note.id, note.label)
    }

    func testDescriptionEqualsLabel() {
        let note = MusicalNote(name: .G, octave: 2)
        XCTAssertEqual(note.description, note.label)
    }

    // MARK: – Sharp identification

    func testSharpsAreSharp() {
        let sharps: [MusicalNote.Name] = [.Cs, .Ds, .Fs, .Gs, .As]
        for s in sharps {
            XCTAssertTrue(s.isSharp, "\(s) should be sharp")
        }
    }

    func testNaturalsAreNotSharp() {
        let naturals: [MusicalNote.Name] = [.C, .D, .E, .F, .G, .A, .B]
        for n in naturals {
            XCTAssertFalse(n.isSharp, "\(n) should not be sharp")
        }
    }

    // MARK: – notes(in:) helper

    func testNotesInOctaveCount() {
        let notes = MusicalNote.notes(in: 4)
        XCTAssertEqual(notes.count, 12)
    }

    func testNotesInOctaveOrder() {
        let notes = MusicalNote.notes(in: 4)
        XCTAssertEqual(notes.first?.name, .C)
        XCTAssertEqual(notes.last?.name, .B)
    }

    func testNotesInOctaveAllSameOctave() {
        let notes = MusicalNote.notes(in: 3)
        XCTAssertTrue(notes.allSatisfy { $0.octave == 3 })
    }

    // MARK: – nearest(to:) helper

    func testNearestToA4() {
        let note = MusicalNote.nearest(to: 440.0)
        XCTAssertEqual(note.name, .A)
        XCTAssertEqual(note.octave, 4)
    }

    func testNearestToC4() {
        let note = MusicalNote.nearest(to: 261.626)
        XCTAssertEqual(note.name, .C)
        XCTAssertEqual(note.octave, 4)
    }

    func testNearestClampsLow() {
        // Frequency below C0 clamps to C0 (MIDI 12)
        let note = MusicalNote.nearest(to: 1.0)
        XCTAssertEqual(note.midiNote, 12)
    }

    func testNearestClampsHigh() {
        // Frequency above B8 clamps to B8 (MIDI 119)
        let note = MusicalNote.nearest(to: 99_999.0)
        XCTAssertEqual(note.midiNote, 119)
    }

    func testNearestToZeroReturnsA4() {
        // Guard branch: non-positive input returns .a4
        let note = MusicalNote.nearest(to: 0.0)
        XCTAssertEqual(note.midiNote, MusicalNote.a4.midiNote)
    }

    // MARK: – Hashable / Identifiable conformance

    func testUniqueIdsAcrossRange() {
        var ids = Set<String>()
        for octave in 0...8 {
            for note in MusicalNote.notes(in: octave) {
                ids.insert(note.id)
            }
        }
        XCTAssertEqual(ids.count, 9 * 12, "All 108 notes must have unique IDs")
    }

    func testHashableEqualityMatchesValues() {
        let n1 = MusicalNote(name: .G, octave: 5)
        let n2 = MusicalNote(name: .G, octave: 5)
        XCTAssertEqual(n1, n2)
    }
}
