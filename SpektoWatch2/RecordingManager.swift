import Foundation
import SwiftUI
import AVFoundation
import Combine
import OSLog

class RecordingManager: NSObject, ObservableObject {
    
    @Published var isRecording = false
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var recordings: [AudioRecording] = []
    
    private var timer: Timer?
    private var recordingStartTime: Date?
    
    override init() {
        super.init()
    }
    
    func startRecording(audioEngine: AudioEngine) -> Bool {
        // In a real implementation, you would set up an AVAudioFile here
        // and write buffers received from AudioEngine.
        // For now, we track the state and duration.
        
        isRecording = true
        recordingStartTime = Date()
        currentRecordingDuration = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            self.currentRecordingDuration = Date().timeIntervalSince(startTime)
        }
        
        return true
    }
    
    func stopRecording(audioEngine: AudioEngine, completion: @escaping (URL?) -> Void) {
        isRecording = false
        timer?.invalidate()
        timer = nil
        
        // Get the URL from AudioEngine
        if let url = audioEngine.lastRecordingURL {
            completion(url)
        } else {
            completion(nil)
        }
    }
    
    func deleteRecording(at offsets: IndexSet) {
        let recordingsToDelete = offsets.map { recordings[$0] }
        
        for recording in recordingsToDelete {
            do {
                try FileManager.default.removeItem(at: recording.url)
                Logger.recording.info("Successfully deleted file: \(recording.url.lastPathComponent)")
            } catch {
                Logger.recording.error("Error deleting file at \(recording.url): \(error.localizedDescription)")
            }
        }
        
        recordings.remove(atOffsets: offsets)
    }
    
    func addRecording(_ recording: AudioRecording) {
        recordings.append(recording)
    }
}

struct AudioRecording: Identifiable, Codable {
    var id = UUID()
    let url: URL
    let date: Date
    let duration: TimeInterval
    var title: String
    
    // Extended Metadata
    var laeqFast: Float = 0.0
    var peakLevel: Float = 0.0
    var minLevel: Float = 0.0
    var timeWeighting: String = "Fast"
    var frequencyWeighting: String = "A"
    var sampleRate: Double = 44100.0
    var channelCount: Int = 1
    var description: String = ""
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}