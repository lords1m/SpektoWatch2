import AVFoundation

struct AudioConfiguration {
    let fftSize: Int = 8192
    let tapBlockSize: AVAudioFrameCount = 512
    let maxHistorySize: Int = 1000
    let sampleRate: Double = 44100.0
    let updateDebounceInterval: TimeInterval = 0.05
    
    static let `default` = AudioConfiguration()
}
