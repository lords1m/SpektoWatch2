// Pure model for musical note selection and Hz conversion.
// Used by the ToneGenerator piano input (M11 task-2).
// No SwiftUI, AVFoundation, or UIKit dependencies.

import Darwin  // pow, log2

// Equal-temperament tuning: A4 = 440 Hz, semitone ratio = 2^(1/12).
// MIDI note numbering: C0 = 12, C4 = 60, A4 = 69.
// Supported range: C0 (≈16 Hz) … B8 (≈7902 Hz).

struct MusicalNote: Hashable, Identifiable, CustomStringConvertible {

    // MARK: – Note name (one semitone per step, 12 per octave)

    enum Name: Int, CaseIterable {
        case C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B

        var displayName: String {
            switch self {
            case .C:  return "C"
            case .Cs: return "C#"
            case .D:  return "D"
            case .Ds: return "D#"
            case .E:  return "E"
            case .F:  return "F"
            case .Fs: return "F#"
            case .G:  return "G"
            case .Gs: return "G#"
            case .A:  return "A"
            case .As: return "A#"
            case .B:  return "B"
            }
        }

        /// True for the five black keys in a standard octave layout.
        var isSharp: Bool {
            switch self {
            case .Cs, .Ds, .Fs, .Gs, .As: return true
            default: return false
            }
        }
    }

    // MARK: – Properties

    let name: Name
    let octave: Int  // 0 … 8

    // Unique string identifier, e.g. "A4", "C#3".
    var id: String { label }

    var label: String { "\(name.displayName)\(octave)" }
    var description: String { label }

    // MIDI note number (C0 = 12, A4 = 69, B8 = 119).
    var midiNote: Int { (octave + 1) * 12 + name.rawValue }

    // Equal-temperament frequency in Hz.
    // f(n) = 440 × 2^((n − 69) / 12)
    var frequency: Float {
        let semitoneOffset = Float(midiNote - 69)
        return 440.0 * pow(2.0, semitoneOffset / 12.0)
    }

    // MARK: – Well-known references

    static let a4 = MusicalNote(name: .A, octave: 4)

    // MARK: – Range

    /// Supported octave range for tone generation (C0 ≈ 16 Hz … B8 ≈ 7902 Hz).
    static let supportedOctaveRange = 0...8

    // MARK: – Helpers

    /// All 12 notes for a given octave, ordered C … B.
    static func notes(in octave: Int) -> [MusicalNote] {
        Name.allCases.map { MusicalNote(name: $0, octave: octave) }
    }

    /// The note whose frequency is closest to `frequency` (nearest semitone).
    /// Clamps to the supported range (C0 … B8).
    static func nearest(to frequency: Float) -> MusicalNote {
        guard frequency > 0 else { return .a4 }
        let midi = 69.0 + 12.0 * log2(Double(frequency) / 440.0)
        let rounded = Int(midi.rounded())
        let clamped = max(12, min(119, rounded))  // C0 = 12, B8 = 119
        let octave = clamped / 12 - 1
        let semitone = clamped % 12
        let noteName = Name(rawValue: semitone) ?? .A
        return MusicalNote(name: noteName, octave: octave)
    }
}
