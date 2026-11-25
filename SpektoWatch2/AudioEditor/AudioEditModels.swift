import AVFoundation
import Foundation
import UniformTypeIdentifiers

// MARK: - EQ & Filter Models

struct EQBandSetting: Identifiable, Codable, Equatable, Sendable {
    enum BandType: String, Codable, Equatable, Sendable {
        case lowShelf
        case parametric
        case highShelf
    }

    let id: Int
    var frequency: Float
    var gainDB: Float
    var bandwidth: Float
    var filterType: BandType

    static let defaultBands: [EQBandSetting] = [
        EQBandSetting(id: 0, frequency: 60, gainDB: 0, bandwidth: 1.0, filterType: .lowShelf),
        EQBandSetting(id: 1, frequency: 250, gainDB: 0, bandwidth: 1.0, filterType: .parametric),
        EQBandSetting(id: 2, frequency: 1000, gainDB: 0, bandwidth: 1.0, filterType: .parametric),
        EQBandSetting(id: 3, frequency: 4000, gainDB: 0, bandwidth: 1.0, filterType: .parametric),
        EQBandSetting(id: 4, frequency: 12000, gainDB: 0, bandwidth: 1.0, filterType: .highShelf),
    ]
}

enum EQPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case flat = "Flat"
    case speech = "Sprache"
    case reduceHum = "Brummen reduzieren"
    case clarity = "Klarheit"
    case warm = "Warm"

    var id: String { rawValue }

    var bandGainsDB: [Float] {
        switch self {
        case .flat:       return [0, 0, 0, 0, 0]
        case .speech:     return [-4, -1, 2, 4, 2]
        case .reduceHum:  return [-10, -4, 0, 1, 0]
        case .clarity:    return [-2, 0, 1.5, 4.5, 4]
        case .warm:       return [3.5, 2.5, 0, -1.5, -2.5]
        }
    }

    func apply(to bands: [EQBandSetting]) -> [EQBandSetting] {
        let gains = bandGainsDB
        return bands.enumerated().map { idx, band in
            var copy = band
            if gains.indices.contains(idx) {
                copy.gainDB = gains[idx]
            }
            return copy
        }
    }
}

struct FilterChainSettings: Codable, Equatable, Sendable {
    var highPassEnabled: Bool = false
    var highPassCutoffHz: Float = 80

    var lowPassEnabled: Bool = false
    var lowPassCutoffHz: Float = 12000

    var notchEnabled: Bool = false
    var notchCenterHz: Float = 50
    var notchBandwidthOctaves: Float = 0.25

    /// Voice-Memos-style one-tap enhance toggle (gentle HPF + vocal presence + normalize).
    var enhanceVoiceEnabled: Bool = false

    var hasActiveFilters: Bool {
        highPassEnabled || lowPassEnabled || notchEnabled || enhanceVoiceEnabled
    }
}

// MARK: - Time & Recipe Models

struct AudioTimeRange: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    var duration: TimeInterval { max(0, end - start) }

    init(start: TimeInterval, end: TimeInterval) {
        let lo = max(0, min(start, end))
        let hi = max(lo, end)
        self.start = lo
        self.end = hi
    }
}

struct AudioEditRecipe: Codable, Equatable, Sendable {
    static let minimumKeptDuration: TimeInterval = 0.05

    var sourceDuration: TimeInterval
    var keptRanges: [AudioTimeRange]
    var fadeInDuration: TimeInterval = 0
    var fadeOutDuration: TimeInterval = 0
    var gainDB: Float = 0
    var normalizeEnabled: Bool = false
    var eqBands: [EQBandSetting] = EQBandSetting.defaultBands
    var filters: FilterChainSettings = FilterChainSettings()

    init(sourceDuration: TimeInterval) {
        let safeDuration = max(0, sourceDuration)
        self.sourceDuration = safeDuration
        self.keptRanges = safeDuration > 0 ? [AudioTimeRange(start: 0, end: safeDuration)] : []
    }

    var effectiveDuration: TimeInterval {
        keptRanges.reduce(0) { $0 + $1.duration }
    }

    var hasTimeEdits: Bool {
        guard sourceDuration > 0 else { return false }
        if keptRanges.count != 1 { return true }
        guard let only = keptRanges.first else { return false }
        return abs(only.start) > 0.002 || abs(only.end - sourceDuration) > 0.002
    }

    var hasChanges: Bool {
        hasTimeEdits
            || fadeInDuration > 0.001
            || fadeOutDuration > 0.001
            || abs(gainDB) > 0.05
            || normalizeEnabled
            || eqBands.contains { abs($0.gainDB) > 0.05 }
            || filters.hasActiveFilters
    }

    /// Trims the edited timeline to keep only `[editedStart, editedEnd]`.
    func applyingTrim(editedStart: TimeInterval, editedEnd: TimeInterval) -> AudioEditRecipe {
        let total = effectiveDuration
        guard total > Self.minimumKeptDuration else { return self }

        let clampedStart = max(0, min(editedStart, total - Self.minimumKeptDuration))
        let clampedEnd = max(clampedStart + Self.minimumKeptDuration, min(editedEnd, total))

        var resultRanges: [AudioTimeRange] = []
        var cursor: TimeInterval = 0

        for seg in keptRanges {
            let segStartEdited = cursor
            let segEndEdited = cursor + seg.duration
            cursor = segEndEdited

            let overlapStart = max(clampedStart, segStartEdited)
            let overlapEnd = min(clampedEnd, segEndEdited)
            if overlapEnd - overlapStart > 0.0005 {
                let srcStart = seg.start + (overlapStart - segStartEdited)
                let srcEnd = seg.start + (overlapEnd - segStartEdited)
                resultRanges.append(AudioTimeRange(start: srcStart, end: srcEnd))
            }
        }

        let merged = Self.coalesce(resultRanges)
        guard merged.reduce(0, { $0 + $1.duration }) >= Self.minimumKeptDuration else {
            return self
        }
        var copy = self
        copy.keptRanges = merged
        return copy
    }

    /// Deletes the edited interval `[editedStart, editedEnd]` (Cut).
    func applyingCut(editedStart: TimeInterval, editedEnd: TimeInterval) -> AudioEditRecipe {
        let total = effectiveDuration
        guard total > Self.minimumKeptDuration else { return self }

        let clampedStart = max(0, min(editedStart, total))
        let clampedEnd = max(clampedStart, min(editedEnd, total))
        guard clampedEnd - clampedStart > 0.005 else { return self }

        var resultRanges: [AudioTimeRange] = []
        var cursor: TimeInterval = 0

        for seg in keptRanges {
            let segStartEdited = cursor
            let segEndEdited = cursor + seg.duration
            cursor = segEndEdited

            // No overlap with cut window
            if clampedEnd <= segStartEdited || clampedStart >= segEndEdited {
                resultRanges.append(seg)
                continue
            }

            // Left remainder before cut
            if clampedStart > segStartEdited + 0.0005 {
                let srcEnd = seg.start + (clampedStart - segStartEdited)
                resultRanges.append(AudioTimeRange(start: seg.start, end: srcEnd))
            }

            // Right remainder after cut
            if clampedEnd < segEndEdited - 0.0005 {
                let srcStart = seg.start + (clampedEnd - segStartEdited)
                resultRanges.append(AudioTimeRange(start: srcStart, end: seg.end))
            }
        }

        let merged = Self.coalesce(resultRanges)
        guard merged.reduce(0, { $0 + $1.duration }) >= Self.minimumKeptDuration else {
            return self
        }
        var copy = self
        copy.keptRanges = merged
        return copy
    }

    func sourceTime(forEditedTime edited: TimeInterval) -> TimeInterval {
        let clamped = max(0, min(edited, effectiveDuration))
        var cursor: TimeInterval = 0
        for seg in keptRanges {
            let nextCursor = cursor + seg.duration
            if clamped <= nextCursor + 1e-6 {
                return seg.start + max(0, clamped - cursor)
            }
            cursor = nextCursor
        }
        return keptRanges.last?.end ?? 0
    }

    func editedTime(forSourceTime source: TimeInterval) -> TimeInterval {
        var cursor: TimeInterval = 0
        for seg in keptRanges {
            if source <= seg.start {
                return cursor
            }
            if source <= seg.end {
                return cursor + (source - seg.start)
            }
            cursor += seg.duration
        }
        return cursor
    }

    private static func coalesce(_ ranges: [AudioTimeRange]) -> [AudioTimeRange] {
        var output: [AudioTimeRange] = []
        for range in ranges where range.duration > 0.0005 {
            if let last = output.last, abs(last.end - range.start) < 0.0005 {
                output[output.count - 1] = AudioTimeRange(start: last.start, end: range.end)
            } else {
                output.append(range)
            }
        }
        return output
    }

    /// Analytic magnitude response (dB) used to draw the live EQ + Filter curve.
    func frequencyResponseDB(at frequencyHz: Float) -> Float {
        let f = max(20, min(20000, frequencyHz))
        var db: Float = 0

        let effectiveHPF = filters.highPassEnabled || filters.enhanceVoiceEnabled
        let hpfCutoff = filters.highPassEnabled ? filters.highPassCutoffHz : 85
        if effectiveHPF && hpfCutoff > 20 {
            let ratio = hpfCutoff / f
            if ratio > 0.25 {
                // 2nd-order HPF roll-off approximation (~12 dB/oct)
                let resp = 1.0 / sqrtf(1.0 + powf(ratio, 4))
                db += 20.0 * log10f(max(resp, 1e-4))
            }
        }

        if filters.lowPassEnabled && filters.lowPassCutoffHz < 20000 {
            let ratio = f / max(filters.lowPassCutoffHz, 200)
            if ratio > 0.25 {
                let resp = 1.0 / sqrtf(1.0 + powf(ratio, 4))
                db += 20.0 * log10f(max(resp, 1e-4))
            }
        }

        if filters.notchEnabled {
            let octaves = abs(log2f(f / max(filters.notchCenterHz, 20)))
            let halfBW = max(0.05, filters.notchBandwidthOctaves * 0.5)
            let norm = octaves / halfBW
            db += -24.0 * expf(-norm * norm * 1.4)
        }

        for band in eqBands {
            var bandGain = band.gainDB
            if filters.enhanceVoiceEnabled && abs(band.frequency - 4000) < 100 {
                bandGain += 2.5
            } else if filters.enhanceVoiceEnabled && abs(band.frequency - 250) < 50 {
                bandGain -= 1.5
            }
            guard abs(bandGain) > 0.01 else { continue }
            let octaves = log2f(f / max(band.frequency, 20))
            switch band.filterType {
            case .lowShelf:
                let t = 1.0 / (1.0 + expf(octaves * 2.4))
                db += bandGain * t
            case .highShelf:
                let t = 1.0 / (1.0 + expf(-octaves * 2.4))
                db += bandGain * t
            case .parametric:
                let bw = max(0.3, band.bandwidth)
                let weight = expf(-(octaves * octaves) / (bw * bw * 0.75))
                db += bandGain * weight
            }
        }

        return max(-30, min(18, db))
    }
}

// MARK: - Non-Destructive Undo / Redo History

struct AudioEditHistory: Equatable {
    private(set) var current: AudioEditRecipe
    private let initialRecipe: AudioEditRecipe
    private var undoStack: [AudioEditRecipe] = []
    private var redoStack: [AudioEditRecipe] = []
    private let maxDepth: Int

    init(sourceDuration: TimeInterval, maxDepth: Int = 40) {
        let initial = AudioEditRecipe(sourceDuration: sourceDuration)
        self.initialRecipe = initial
        self.current = initial
        self.maxDepth = max(1, maxDepth)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func apply(_ newRecipe: AudioEditRecipe) {
        guard newRecipe != current else { return }
        undoStack.append(current)
        if undoStack.count > maxDepth {
            undoStack.removeFirst(undoStack.count - maxDepth)
        }
        redoStack.removeAll()
        current = newRecipe
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        current = next
        return true
    }

    mutating func reset() {
        apply(initialRecipe)
    }
}

// MARK: - Shared AVAudioUnitEQ Configurator

enum AudioUnitEQConfigurator {
    /// 0 = HPF, 1 = LPF, 2 = Notch, 3...7 = 5 EQ bands
    static let bandCount = 8

    static func configure(eqNode: AVAudioUnitEQ, recipe: AudioEditRecipe, bypassed: Bool) {
        guard eqNode.bands.count >= bandCount else { return }
        eqNode.bypass = bypassed
        eqNode.globalGain = bypassed ? 0 : recipe.gainDB

        // Band 0: High-pass filter (explicit HPF or Enhance Voice)
        let hpfBand = eqNode.bands[0]
        hpfBand.filterType = .highPass
        let useHPF = recipe.filters.highPassEnabled || recipe.filters.enhanceVoiceEnabled
        hpfBand.frequency = recipe.filters.highPassEnabled
            ? max(20, min(500, recipe.filters.highPassCutoffHz))
            : 85
        hpfBand.bandwidth = 0.7
        hpfBand.bypass = bypassed || !useHPF

        // Band 1: Low-pass filter
        let lpfBand = eqNode.bands[1]
        lpfBand.filterType = .lowPass
        lpfBand.frequency = max(1000, min(20000, recipe.filters.lowPassCutoffHz))
        lpfBand.bandwidth = 0.7
        lpfBand.bypass = bypassed || !recipe.filters.lowPassEnabled

        // Band 2: Notch / Band-stop filter
        let notchBand = eqNode.bands[2]
        notchBand.filterType = .bandStop
        notchBand.frequency = max(20, min(20000, recipe.filters.notchCenterHz))
        notchBand.bandwidth = max(0.05, min(2.0, recipe.filters.notchBandwidthOctaves))
        notchBand.gain = -24
        notchBand.bypass = bypassed || !recipe.filters.notchEnabled

        // Bands 3...7: 5-band EQ
        for (idx, setting) in recipe.eqBands.prefix(5).enumerated() {
            let eqBand = eqNode.bands[3 + idx]
            switch setting.filterType {
            case .lowShelf:   eqBand.filterType = .lowShelf
            case .parametric: eqBand.filterType = .parametric
            case .highShelf:  eqBand.filterType = .highShelf
            }
            eqBand.frequency = setting.frequency
            eqBand.bandwidth = max(0.25, setting.bandwidth)

            var gain = setting.gainDB
            if recipe.filters.enhanceVoiceEnabled {
                if abs(setting.frequency - 250) < 50 {
                    gain -= 1.5
                } else if abs(setting.frequency - 4000) < 100 {
                    gain += 2.5
                }
            }
            eqBand.gain = max(-24, min(24, gain))
            eqBand.bypass = bypassed || abs(gain) < 0.05
        }
    }
}

// MARK: - Export Format & Options

enum AudioExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case m4aAAC = "M4A (AAC)"
    case mp3 = "MP3"
    case wav = "WAV"
    case alac = "ALAC (Lossless)"
    case aiff = "AIFF"
    case caf = "CAF"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var fileExtension: String {
        switch self {
        case .wav:    return "wav"
        case .mp3:    return "mp3"
        case .m4aAAC: return "m4a"
        case .alac:   return "m4a"
        case .aiff:   return "aiff"
        case .caf:    return "caf"
        }
    }

    var subtitle: String {
        switch self {
        case .m4aAAC: return "Komprimiert · klein & Apple-kompatibel"
        case .mp3:    return "Komprimiert · universell kompatibel"
        case .wav:    return "Unkomprimiert PCM · Studio-Standard"
        case .alac:   return "Verlustfrei komprimiert · Apple Lossless"
        case .aiff:   return "Unkomprimiert PCM · macOS / Pro Audio"
        case .caf:    return "Core Audio Format · lange Aufnahmen"
        }
    }

    var isLossless: Bool {
        switch self {
        case .wav, .alac, .aiff, .caf: return true
        case .mp3, .m4aAAC:            return false
        }
    }

    var supportsBitrate: Bool {
        self == .mp3 || self == .m4aAAC
    }

    var supportsBitDepth: Bool {
        self == .wav || self == .aiff || self == .caf
    }

    var utType: UTType {
        switch self {
        case .wav:           return .wav
        case .mp3:           return .mp3
        case .m4aAAC, .alac: return .mpeg4Audio
        case .aiff:          return .aiff
        case .caf:           return UTType(filenameExtension: "caf") ?? .audio
        }
    }
}

struct AudioExportOptions: Equatable, Sendable {
    var format: AudioExportFormat = .m4aAAC
    var pcmBitDepth: Int = 16
    var bitrateKbps: Int = 192
    var useVBR: Bool = false
    var targetSampleRate: Double? = nil
    var downmixToMono: Bool = false
    var title: String = ""

    func estimatedByteSize(duration: TimeInterval, sourceSampleRate: Double, sourceChannels: Int) -> Int64 {
        let dur = max(0, duration)
        let rate = targetSampleRate ?? max(8000, sourceSampleRate)
        let channels = downmixToMono ? 1 : max(1, sourceChannels)

        switch format {
        case .wav, .aiff, .caf:
            let bytesPerSample = Double(max(16, pcmBitDepth) / 8)
            return Int64(dur * rate * Double(channels) * bytesPerSample) + 4096
        case .alac:
            let uncompressed = dur * rate * Double(channels) * 2.0
            return Int64(uncompressed * 0.55) + 4096
        case .m4aAAC, .mp3:
            let bitsPerSecond = Double(bitrateKbps) * 1000.0
            return Int64((dur * bitsPerSecond) / 8.0) + 4096
        }
    }
}
