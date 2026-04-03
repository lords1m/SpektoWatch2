import Foundation
import AVFoundation
import UIKit

@MainActor
class RecordingManager: ObservableObject {
    static let shared = RecordingManager()
    
    @Published var recordings: [Recording] = []
    @Published var isRecording: Bool = false
    @Published var currentRecordingDuration: TimeInterval = 0

    // Preserved after stopRecording so saveRecording can read the correct values
    private(set) var lastRecordingDuration: TimeInterval = 0
    private(set) var lastRecordingStart: Date?

    private var recordingTimer: Timer?
    private var currentRecordingStart: Date?
    private var audioRecorder: AVAudioRecorder?
    
    // File Management
    private let fileManager = FileManager.default
    private var recordingsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings")
        
        // Erstelle Ordner falls nicht vorhanden
        if !fileManager.fileExists(atPath: recordingsPath.path) {
            try? fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        }
        return recordingsPath
    }
    
    private var metadataFileURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_metadata.json")
    }
    
    init() {
        print("[RecordingManager] Initializing...")
        loadRecordings()
    }
    
    // MARK: - Recording Control
    
    /// Startet eine neue Aufnahme
    func startRecording(audioEngine: AudioEngine) -> Bool {
        guard !isRecording else {
            print("[RecordingManager] ERROR: Already recording")
            return false
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true)
            
            // Audio-Datei vorbereiten
            let fileName = "recording_\(Date().timeIntervalSince1970).m4a"
            let audioURL = recordingsDirectory.appendingPathComponent(fileName)
            
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            
            // Aufnahme-State
            isRecording = true
            currentRecordingStart = Date()
            currentRecordingDuration = 0
            
            // Timer für Dauer-Anzeige
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let start = self.currentRecordingStart else { return }
                self.currentRecordingDuration = Date().timeIntervalSince(start)
            }
            
            print("[RecordingManager] Recording started: \(fileName)")
            return true
            
        } catch {
            print("[RecordingManager] ERROR starting recording: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Stoppt die aktuelle Aufnahme und zeigt Speicher-Dialog
    func stopRecording(audioEngine: AudioEngine, completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            print("[RecordingManager] ERROR: Not recording")
            completion(nil)
            return
        }
        
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let audioURL = audioRecorder?.url
        // Preserve for saveRecording before clearing live state
        lastRecordingDuration = currentRecordingDuration
        lastRecordingStart = currentRecordingStart

        isRecording = false
        currentRecordingDuration = 0
        currentRecordingStart = nil
        
        // Berechne Statistiken aus AudioEngine
        let stats = audioEngine.getRecordingStatistics()
        
        print("[RecordingManager] Recording stopped. Duration: \(String(format: "%.1f", lastRecordingDuration))s")
        print("[RecordingManager] LAeq,Fast: \(String(format: "%.1f", stats.laeqFast)) dB")
        print("[RecordingManager] Peak: \(String(format: "%.1f", stats.peak)) dB")
        
        completion(audioURL)
    }
    
    /// Speichert eine Aufnahme mit Metadaten
    func saveRecording(
        audioURL: URL,
        name: String,
        description: String,
        audioEngine: AudioEngine
    ) {
        let stats = audioEngine.getRecordingStatistics()
        let timeWeighting = audioEngine.timeWeighting
        let freqWeighting = audioEngine.frequencyWeighting
        
        let recording = Recording(
            name: name.isEmpty ? "Messung \(recordings.count + 1)" : name,
            description: description,
            startDate: lastRecordingStart ?? Date(),
            duration: lastRecordingDuration,
            audioFileName: audioURL.lastPathComponent,
            sampleRate: 44100.0,
            channelCount: 1,
            laeqFast: stats.laeqFast,
            peakLevel: stats.peak,
            minLevel: stats.min,
            timeWeighting: timeWeighting.displayName,
            frequencyWeighting: freqWeighting.rawValue
        )
        
        recordings.insert(recording, at: 0)
        saveMetadata()
        
        print("[RecordingManager] Recording saved: \(recording.name)")
        
        // Haptic Feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    // MARK: - File Management
    
    func deleteRecording(_ recording: Recording) {
        // Lösche Audio-Datei
        let audioURL = recordingsDirectory.appendingPathComponent(recording.audioFileName)
        try? fileManager.removeItem(at: audioURL)
        
        // Lösche Fotos
        for photoFileName in recording.photoFileNames {
            let photoURL = recordingsDirectory.appendingPathComponent(photoFileName)
            try? fileManager.removeItem(at: photoURL)
        }
        
        // Entferne aus Liste
        recordings.removeAll { $0.id == recording.id }
        saveMetadata()
        
        print("[RecordingManager] Recording deleted: \(recording.name)")
    }
    
    func getAudioURL(for recording: Recording) -> URL {
        return recordingsDirectory.appendingPathComponent(recording.audioFileName)
    }
    
    // MARK: - Persistence
    
    private func saveMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(recordings)
            try data.write(to: metadataFileURL)
            print("[RecordingManager] Metadata saved (\(recordings.count) recordings)")
        } catch {
            print("[RecordingManager] ERROR saving metadata: \(error.localizedDescription)")
        }
    }
    
    private func loadRecordings() {
        guard fileManager.fileExists(atPath: metadataFileURL.path) else {
            print("[RecordingManager] No saved recordings found")
            return
        }
        
        do {
            let data = try Data(contentsOf: metadataFileURL)
            recordings = try JSONDecoder().decode([Recording].self, from: data)
            print("[RecordingManager] Loaded \(recordings.count) recordings")
        } catch {
            print("[RecordingManager] ERROR loading recordings: \(error.localizedDescription)")
        }
    }
    
    /// Gibt den Speicherplatz aller Aufnahmen zurück
    func getTotalStorageSize() -> String {
        var totalSize: Int64 = 0
        
        for recording in recordings {
            let url = getAudioURL(for: recording)
            if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }
}

// MARK: - AudioEngine Extension für Statistiken
extension AudioEngine {
    func getRecordingStatistics() -> (laeqFast: Float, peak: Float, min: Float) {
        // TODO: Implementiere echte Statistik-Berechnung
        // Hier vorerst Platzhalter-Werte
        return (
            laeqFast: currentLevel,
            peak: maxLevel,
            min: minLevel
        )
    }
}
