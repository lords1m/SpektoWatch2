import Foundation
import AVFoundation

final class WatchRecordingSession {
    let fileURL: URL
    let startDate: Date
    let format: AVAudioFormat
    private(set) var peakLevel: Float = 0
    private(set) var frameCount: AVAudioFramePosition = 0

    private let audioFile: AVAudioFile

    var duration: TimeInterval {
        guard format.sampleRate > 0 else { return 0 }
        return Double(frameCount) / format.sampleRate
    }

    init(format: AVAudioFormat) throws {
        let fileName = "watch_rec_\(UUID().uuidString).caf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        self.fileURL = url
        self.startDate = Date()
        self.format = format
        self.audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        // Update peak from channel 0
        if let channel = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            for i in 0..<count {
                let abs = fabsf(channel[i])
                if abs > peakLevel { peakLevel = abs }
            }
        }
        do {
            try audioFile.write(from: buffer)
            frameCount += AVAudioFramePosition(buffer.frameLength)
        } catch {
            print("[WatchRecordingSession] write error: \(error)")
        }
    }

    func close() {
        // AVAudioFile is closed on dealloc; no explicit close needed.
        // This method exists for future flush/finalization logic.
    }
}
