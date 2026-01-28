import Foundation

public enum MicrophoneSource: String, Codable, CaseIterable {
    case iPhone = "iPhone"
    case appleWatch = "Apple Watch"
}

public struct SpectrogramData: Codable {
    public let frequencies: [Float]
    public let magnitudes: [Float]
    public let broadbandLevel: Float
    public let levels: [String: Float]
    public let timestamp: Date
    public let sampleRate: Double

    public init(frequencies: [Float], magnitudes: [Float], broadbandLevel: Float = -120.0, levels: [String: Float] = [:], sampleRate: Double) {
        self.frequencies = frequencies
        self.magnitudes = magnitudes
        self.broadbandLevel = broadbandLevel
        self.levels = levels
        self.timestamp = Date()
        self.sampleRate = sampleRate
    }
}

public struct AudioData: Codable {
    public let samples: [Float]
    public let sampleRate: Double
    public let timestamp: Date

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.timestamp = Date()
    }
}

public struct SpectrogramFrame: Identifiable {
    public let id = UUID()
    public let magnitudes: [Float]
    public let timestamp: Date
    
    public init(magnitudes: [Float], timestamp: Date) {
        self.magnitudes = magnitudes
        self.timestamp = timestamp
    }
}
