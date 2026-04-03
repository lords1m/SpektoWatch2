import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var recordings: [Recording] = []

    private var timer: Timer?
    private var recordingStartTime: Date?
    private let fileManager = FileManager.default

    private var recordingsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var metadataURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_metadata_v2.json")
    }

    override init() {
        super.init()
        loadRecordings()
    }

    func startRecording(audioEngine: AudioEngine) -> Bool {
        guard !isRecording else { return false }
        isRecording = true
        recordingStartTime = Date()
        currentRecordingDuration = 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.currentRecordingDuration = Date().timeIntervalSince(start)
        }
        return true
    }

    func stopRecording(audioEngine: AudioEngine, completion: @escaping (URL?) -> Void) {
        isRecording = false
        timer?.invalidate()
        timer = nil
        completion(audioEngine.lastRecordingURL)
    }

    func addRecording(_ recording: Recording) {
        var stored = recording

        if let movedAudio = persistRecordingFile(pathOrName: stored.audioFileName, id: stored.id) {
            stored.audioFileName = movedAudio.lastPathComponent
        }

        if let measurementName = stored.measurementDataFileName,
           let movedMeasurement = persistMeasurementFile(pathOrName: measurementName, id: stored.id) {
            stored.measurementDataFileName = movedMeasurement.lastPathComponent
        }

        recordings.insert(stored, at: 0)
        saveRecordings()
    }

    func updateRecording(_ recording: Recording) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index] = recording
        saveRecordings()
    }

    func deleteRecording(at offsets: IndexSet) {
        for index in offsets {
            guard index < recordings.count else { continue }
            let recording = recordings[index]
            let audioURL = url(for: recording)
            if fileManager.fileExists(atPath: audioURL.path) {
                try? fileManager.removeItem(at: audioURL)
            }
            if let measurementURL = measurementURL(for: recording),
               fileManager.fileExists(atPath: measurementURL.path) {
                try? fileManager.removeItem(at: measurementURL)
            }
            for photoName in recording.photoFileNames {
                let photoURL = recordingsDirectory.appendingPathComponent(photoName)
                if fileManager.fileExists(atPath: photoURL.path) {
                    try? fileManager.removeItem(at: photoURL)
                }
            }
        }

        recordings.remove(atOffsets: offsets)
        saveRecordings()
    }

    func url(for recording: Recording) -> URL {
        if recording.audioFileName.contains("/") {
            return URL(fileURLWithPath: recording.audioFileName)
        }
        return recordingsDirectory.appendingPathComponent(recording.audioFileName)
    }

    func measurementURL(for recording: Recording) -> URL? {
        guard let fileName = recording.measurementDataFileName else { return nil }
        if fileName.contains("/") {
            return URL(fileURLWithPath: fileName)
        }
        return recordingsDirectory.appendingPathComponent(fileName)
    }

    private func persistRecordingFile(pathOrName: String, id: UUID) -> URL? {
        guard let sourceURL = resolveSourceURL(pathOrName: pathOrName) else { return nil }
        let fileExtension = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let targetURL = recordingsDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
        return moveOrCopyFile(from: sourceURL, to: targetURL)
    }

    private func persistMeasurementFile(pathOrName: String, id: UUID) -> URL? {
        guard let sourceURL = resolveSourceURL(pathOrName: pathOrName) else { return nil }
        let targetURL = recordingsDirectory.appendingPathComponent("\(id.uuidString).spekto")
        return moveOrCopyFile(from: sourceURL, to: targetURL)
    }

    private func resolveSourceURL(pathOrName: String) -> URL? {
        let trimmed = pathOrName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("/") {
            let absolute = URL(fileURLWithPath: trimmed)
            if fileManager.fileExists(atPath: absolute.path) { return absolute }
            return nil
        }

        let inRecordings = recordingsDirectory.appendingPathComponent(trimmed)
        if fileManager.fileExists(atPath: inRecordings.path) { return inRecordings }
        let inTemp = fileManager.temporaryDirectory.appendingPathComponent(trimmed)
        if fileManager.fileExists(atPath: inTemp.path) { return inTemp }
        return nil
    }

    private func moveOrCopyFile(from sourceURL: URL, to targetURL: URL) -> URL? {
        if sourceURL.standardizedFileURL == targetURL.standardizedFileURL {
            return sourceURL
        }

        if fileManager.fileExists(atPath: targetURL.path) {
            try? fileManager.removeItem(at: targetURL)
        }

        do {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
            return targetURL
        } catch {
            do {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
                try? fileManager.removeItem(at: sourceURL)
                return targetURL
            } catch {
                return nil
            }
        }
    }

    private func saveRecordings() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recordings)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            print("[RecordingManager] Metadata save failed: \(error)")
        }
    }

    private func loadRecordings() {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            recordings = try decoder.decode([Recording].self, from: data)
        } catch {
            print("[RecordingManager] Metadata load failed: \(error)")
        }
    }
}
