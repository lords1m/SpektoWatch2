import Foundation

// One saved masking configuration. Persisted as JSON in Documents/Masking/profiles.json,
// mirroring the pattern used by RecordingManager for Recording objects.
struct MaskingProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var triggerSpectrum: TriggerSpectrum
    var maskerType: MaskerType
    var eqBands: [EQBand]
    var volumedBFS: Float        // masker output level in dB, capped at –10 dBFS
    var triggerSampleFileName: String?   // optional M4A in Documents/Masking/
    let createdAt: Date
    var lastUsed: Date

    init(name: String,
         triggerSpectrum: TriggerSpectrum,
         maskerType: MaskerType,
         eqBands: [EQBand],
         volumedBFS: Float) {
        self.id = UUID()
        self.name = name
        self.triggerSpectrum = triggerSpectrum
        self.maskerType = maskerType
        self.eqBands = eqBands
        self.volumedBFS = min(volumedBFS, -10.0)
        self.createdAt = Date()
        self.lastUsed = Date()
    }
}

// A single parametric EQ band for the masker output chain.
struct EQBand: Codable, Equatable {
    enum BandType: String, Codable {
        case lowShelf
        case peak
        case highShelf
    }
    var type: BandType
    var frequency: Float    // Hz
    var q: Float            // bandwidth / resonance (only used for .peak)
    var gainDB: Float       // clamped to [–12, +12] dB
}

// Auto-suggestion result before the user saves it as a profile.
struct MaskerSuggestion {
    var maskerType: MaskerType
    var eqBands: [EQBand]
    var volumedBFS: Float
    var confidenceScore: Float  // 0…1, higher = better spectral match

    func toProfile(name: String, triggerSpectrum: TriggerSpectrum) -> MaskingProfile {
        MaskingProfile(
            name: name,
            triggerSpectrum: triggerSpectrum,
            maskerType: maskerType,
            eqBands: eqBands,
            volumedBFS: volumedBFS
        )
    }
}
