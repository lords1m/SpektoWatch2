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
    private var pendingAudioURL: URL?
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
        pendingAudioURL = createPlaceholderRecordingFile()

        let startTime = recordingStartTime
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = startTime else { return }
            Task { @MainActor in
                self.currentRecordingDuration = Date().timeIntervalSince(start)
            }
        }
        return true
    }

    func stopRecording(audioEngine: AudioEngine, completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        if let start = recordingStartTime {
            currentRecordingDuration = max(currentRecordingDuration, Date().timeIntervalSince(start))
        }
        isRecording = false
        recordingStartTime = nil
        timer?.invalidate()
        timer = nil

        let engineURL = audioEngine.lastRecordingURL
        let url = engineURL ?? pendingAudioURL
        if engineURL != nil, let pendingAudioURL {
            try? fileManager.removeItem(at: pendingAudioURL)
        }
        pendingAudioURL = nil
        completion(url)
    }

    func addRecording(_ recording: Recording) {
        var stored = recording
        if stored.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stored.name = "Messung \(recordings.count + 1)"
        }

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
        // Convert positional delete to id-based to avoid race conditions
        // when the array mutates between swipe and confirm.
        let ids = Set(offsets.compactMap { idx -> UUID? in
            guard idx < recordings.count else { return nil }
            return recordings[idx].id
        })
        deleteRecordings(ids: ids)
    }

    /// Id-based hard delete. Removes the metadata entries and their
    /// backing files immediately.
    func deleteRecordings(ids: Set<UUID>) {
        let toDelete = recordings.filter { ids.contains($0.id) }
        for recording in toDelete {
            removeFiles(for: recording)
        }
        recordings.removeAll { ids.contains($0.id) }
        saveRecordings()
    }

    /// Buffer of recordings just removed from `recordings` whose files
    /// haven't been deleted yet. Lets the UI offer a brief "undo"
    /// snackbar without losing data permanently the moment a user
    /// confirms a delete.
    ///
    /// Only one pending batch is held at a time; queuing a new soft
    /// delete commits any prior batch first (collapsing undo windows).
    private var pendingSoftDeletes: [UUID: Recording] = [:]

    /// Removes recordings from the visible list but defers file deletion
    /// so the caller can offer an undo affordance. Call
    /// `commitPendingSoftDeletes()` to make the deletion permanent, or
    /// `undoLastSoftDelete()` to restore.
    func softDeleteRecordings(ids: Set<UUID>) {
        // Commit any previous pending batch — only one undo window at
        // a time. Stacking would let an old undo restore a recording
        // whose files have already been removed by a newer delete.
        commitPendingSoftDeletes()

        let toDelete = recordings.filter { ids.contains($0.id) }
        for recording in toDelete {
            pendingSoftDeletes[recording.id] = recording
        }
        recordings.removeAll { ids.contains($0.id) }
        saveRecordings()
    }

    /// Restores the most recent soft-deleted batch. No-op if there is
    /// nothing pending.
    func undoLastSoftDelete() {
        guard !pendingSoftDeletes.isEmpty else { return }
        let restored = Array(pendingSoftDeletes.values)
        pendingSoftDeletes.removeAll()
        recordings.append(contentsOf: restored)
        recordings.sort { $0.startDate > $1.startDate }
        saveRecordings()
    }

    /// Commits the pending soft-deleted batch. Idempotent.
    func commitPendingSoftDeletes() {
        guard !pendingSoftDeletes.isEmpty else { return }
        for recording in pendingSoftDeletes.values {
            removeFiles(for: recording)
        }
        pendingSoftDeletes.removeAll()
    }

    /// Whether there is a pending soft-deleted batch that can still be
    /// restored. Callers use this to keep undo affordances live across
    /// view-recreation cycles.
    var hasPendingSoftDelete: Bool {
        !pendingSoftDeletes.isEmpty
    }

    /// In-place rename. Whitespace-only names are rejected silently.
    func renameRecording(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        guard recordings[index].name != trimmed else { return }
        recordings[index].name = trimmed
        saveRecordings()
    }

    /// Creates a copy of an existing recording with new file backing.
    /// Audio, measurement data, and photos are physically copied so the
    /// duplicate can be edited or deleted independently.
    func duplicateRecording(_ source: Recording) {
        let newID = UUID()
        let audioExt = (source.audioFileName as NSString).pathExtension
        let newAudioFileName = audioExt.isEmpty
            ? "\(newID.uuidString)"
            : "\(newID.uuidString).\(audioExt)"

        let srcAudioURL = url(for: source)
        let dstAudioURL = recordingsDirectory.appendingPathComponent(newAudioFileName)
        guard (try? fileManager.copyItem(at: srcAudioURL, to: dstAudioURL)) != nil else {
            print("[RecordingManager] Duplicate failed: could not copy audio file")
            return
        }

        var newMeasurementFileName: String? = nil
        if let srcMeasurementURL = measurementURL(for: source) {
            let measurementName = "\(newID.uuidString).spekto"
            let dstMeasurementURL = recordingsDirectory.appendingPathComponent(measurementName)
            if (try? fileManager.copyItem(at: srcMeasurementURL, to: dstMeasurementURL)) != nil {
                newMeasurementFileName = measurementName
            }
        }

        var newPhotoFileNames: [String] = []
        newPhotoFileNames.reserveCapacity(source.photoFileNames.count)
        for photoName in source.photoFileNames {
            let srcURL = recordingsDirectory.appendingPathComponent(photoName)
            let dstName = "\(newID.uuidString)-\(UUID().uuidString).jpg"
            let dstURL = recordingsDirectory.appendingPathComponent(dstName)
            if (try? fileManager.copyItem(at: srcURL, to: dstURL)) != nil {
                newPhotoFileNames.append(dstName)
            }
        }

        let duplicate = Recording(
            id: newID,
            name: source.name + " (Kopie)",
            description: source.description,
            startDate: source.startDate,
            duration: source.duration,
            audioFileName: newAudioFileName,
            measurementDataFileName: newMeasurementFileName,
            sampleRate: source.sampleRate,
            channelCount: source.channelCount,
            laeqFast: source.laeqFast,
            peakLevel: source.peakLevel,
            minLevel: source.minLevel,
            location: source.location,
            photoFileNames: newPhotoFileNames,
            tags: source.tags,
            timeWeighting: source.timeWeighting,
            frequencyWeighting: source.frequencyWeighting,
            widgetConfigurations: source.widgetConfigurations,
            markers: source.markers,
            calibrationOffset: source.calibrationOffset,
            fftBlockSize: source.fftBlockSize
        )
        recordings.insert(duplicate, at: 0)
        saveRecordings()
    }

    /// Exposes a forced reload from disk — used by pull-to-refresh in
    /// the list view and by external workflows that touch the
    /// metadata file directly.
    func reloadRecordings() {
        loadRecordings()
    }

    private func removeFiles(for recording: Recording) {
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

    func url(for recording: Recording) -> URL {
        if recording.audioFileName.contains("/") {
            return URL(fileURLWithPath: recording.audioFileName)
        }
        return recordingsDirectory.appendingPathComponent(recording.audioFileName)
    }

    func getPhotoURL(fileName: String) -> URL {
        recordingsDirectory.appendingPathComponent(fileName)
    }

    func savePhoto(_ imageData: Data, recordingID: UUID) throws -> String {
        let fileName = "\(recordingID.uuidString)-\(UUID().uuidString).jpg"
        try imageData.write(to: recordingsDirectory.appendingPathComponent(fileName))
        return fileName
    }

    func deletePhoto(fileName: String) {
        try? fileManager.removeItem(at: recordingsDirectory.appendingPathComponent(fileName))
    }

    func measurementURL(for recording: Recording) -> URL? {
        guard let fileName = recording.measurementDataFileName else { return nil }
        if fileName.contains("/") {
            return URL(fileURLWithPath: fileName)
        }
        return recordingsDirectory.appendingPathComponent(fileName)
    }

    private func createPlaceholderRecordingFile() -> URL? {
        let url = recordingsDirectory.appendingPathComponent("recording_\(UUID().uuidString).caf")
        guard !fileManager.fileExists(atPath: url.path) else { return url }
        return fileManager.createFile(atPath: url.path, contents: Data()) ? url : nil
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
