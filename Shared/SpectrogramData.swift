import Foundation

enum MicrophoneSource: String, Codable, CaseIterable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
}

struct SpectrogramData: Codable {
    let frequencies: [Float]
    let magnitudes: [Float]
    let broadbandLevel: Float
    let levels: [String: Float]
    let timestamp: Date
    let sampleRate: Double

    init(frequencies: [Float], magnitudes: [Float], broadbandLevel: Float = -120.0, levels: [String: Float] = [:], sampleRate: Double) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.broadbandLevel = broadbandLevel
        self.levels = levels
        self.timestamp = Date()
        self.sampleRate = sampleRate
    }
}

struct AudioData: Codable {
    let samples: [Float]
    let sampleRate: Double
    let timestamp: Date

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = Date()
    }
}

struct SpectrogramFrame: Identifiable {
    let id = UUID()
    let magnitudes: [Float]
    let timestamp: Date
}
