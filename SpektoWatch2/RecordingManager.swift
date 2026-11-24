import Foundation
import SwiftUI
import AVFoundation
import Combine
import OSLog

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var currentRecordingDuration: TimeInterval = 0
    @Published var recordings: [Recording] = []
    @Published var liveActivityError: String? = nil
    @Published var persistenceError: String? = nil

    /// Wall-clock start of the active phone recording session.
    var recordingStartDate: Date? { recordingStartTime }

    private var timer: Timer?
    private var recordingStartTime: Date?
    private var pendingAudioURL: URL?
    private weak var liveActivityAudioEngine: AudioEngine?
    private let fileManager = FileManager.default
    private let baseDirectory: URL?
    private var metadataLoadFailed = false

    private var recordingsDirectory: URL {
        let root = baseDirectory
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = root.appendingPathComponent("Recordings", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var metadataURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_metadata_v2.json")
    }

    /// Sidecar file used by the soft-delete machinery so a process death
    /// during the 5-second undo window can't orphan audio files. Written
    /// inside `softDeleteRecordings` (BEFORE the metadata save, so a
    /// crash between the two leaves the recordings recoverable on the
    /// next launch). Removed by `commitPendingSoftDeletes` and
    /// `undoLastSoftDelete`.
    private var pendingSoftDeleteSidecarURL: URL {
        recordingsDirectory.appendingPathComponent("recordings_pending_soft_delete.json")
    }

    /// - Parameter interruptedRecordingsDirectory: directory scanned on
    ///   launch for writer temp files left behind by a crash/kill during a
    ///   recording (DL-4). Defaults to the system temp directory for the
    ///   production store only, so tests with a custom `baseDirectory` never
    ///   pick up unrelated temp files.
    init(baseDirectory: URL? = nil, interruptedRecordingsDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
        super.init()
        loadRecordings()
        restorePendingSoftDeletesFromSidecarIfNeeded()
        let recoveryDirectory = interruptedRecordingsDirectory
            ?? (baseDirectory == nil ? fileManager.temporaryDirectory : nil)
        if let recoveryDirectory {
            recoverInterruptedRecordings(in: recoveryDirectory)
        }
    }

    // MARK: - Crash recovery (DL-4)

    /// Re-catalogs `recording_<ts>.caf` (+ matching `measurement_<ts>.spekto`)
    /// writer temp files that a previous process never handed to
    /// `addRecording` because it died mid-recording. Must only run at launch
    /// (no writer of this process is open yet).
    func recoverInterruptedRecordings(in directory: URL) {
        guard !metadataLoadFailed else { return }
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        func timestamp(_ url: URL, prefix: String, ext: String) -> TimeInterval? {
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), url.pathExtension.lowercased() == ext else { return nil }
            let core = name.dropFirst(prefix.count).dropLast(ext.count + 1)
            return TimeInterval(core)
        }

        let audioFiles = entries.compactMap { url -> (URL, TimeInterval)? in
            timestamp(url, prefix: "recording_", ext: "caf").map { (url, $0) }
        }
        var measurementFiles = entries.compactMap { url -> (URL, TimeInterval)? in
            timestamp(url, prefix: "measurement_", ext: "spekto").map { (url, $0) }
        }
        guard !audioFiles.isEmpty else { return }

        var recovered = 0
        for (audioURL, ts) in audioFiles.sorted(by: { $0.1 < $1.1 }) {
            let size = (try? audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // Pair with the measurement file opened within 5 s of the audio file.
            var measurementURL: URL?
            if let match = measurementFiles.enumerated().min(by: { abs($0.element.1 - ts) < abs($1.element.1 - ts) }),
               abs(match.element.1 - ts) < 5 {
                measurementURL = match.element.0
                measurementFiles.remove(at: match.offset)
            }
            guard size > 4096 else {
                // Header-only / empty file: nothing worth recovering.
                try? fileManager.removeItem(at: audioURL)
                if let measurementURL { try? fileManager.removeItem(at: measurementURL) }
                continue
            }

            let startDate = Date(timeIntervalSince1970: ts)
            let duration = Self.resolvedRecordingDuration(
                audioURL: audioURL,
                measurementURL: measurementURL,
                fallback: 0
            )
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let recording = Recording(
                name: "Wiederhergestellt \(formatter.string(from: startDate))",
                description: "Nach einem unerwarteten Beenden der App wiederhergestellt.",
                startDate: startDate,
                duration: duration,
                audioFileName: audioURL.path,
                measurementDataFileName: measurementURL?.path,
                tags: ["wiederhergestellt"],
                calibrationOffset: CalibrationProvider.resolveStartupOffset()
            )
            if addRecording(recording) {
                recovered += 1
            }
        }
        if recovered > 0 {
            Logger.recording.warning("Recovered \(recovered) interrupted recording(s) from temp files")
        }
    }

    func startRecording(audioEngine: AudioEngine) -> Bool {
        guard !isRecording else { return false }
        isRecording = true
        recordingStartTime = Date()
        currentRecordingDuration = 0
        pendingAudioURL = createPlaceholderRecordingFile()

        #if canImport(ActivityKit)
        liveActivityAudioEngine = audioEngine
        liveActivityError = MeasurementLiveActivityController.shared.start(
            sessionTitle: "Messung",
            weighting: audioEngine.frequencyWeighting.rawValue,
            startedAt: recordingStartTime ?? Date()
        )
        #endif

        let startTime = recordingStartTime
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = startTime else { return }
            Task { @MainActor in
                self.currentRecordingDuration = Date().timeIntervalSince(start)
                #if canImport(ActivityKit)
                if let audioEngine = self.liveActivityAudioEngine {
                    MeasurementLiveActivityController.shared.update(
                        currentLevel: Double(audioEngine.live.currentLevel),
                        peakLevel: Double(audioEngine.live.currentPeakLevel),
                        weighting: audioEngine.frequencyWeighting.rawValue,
                        isPaused: false
                    )
                }
                #endif
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

        #if canImport(ActivityKit)
        MeasurementLiveActivityController.shared.end()
        liveActivityAudioEngine = nil
        #endif

        let engineURL = audioEngine.lastRecordingURL
        let url = engineURL ?? pendingAudioURL
        if engineURL != nil, let pendingAudioURL {
            try? fileManager.removeItem(at: pendingAudioURL)
        }
        pendingAudioURL = nil
        completion(url)
    }

    /// Persists a finished recording: moves its files into the recordings
    /// directory and writes the catalog. Returns `false` (and leaves the
    /// in-memory list unchanged) when the audio file could not be moved or
    /// the metadata could not be written — callers that acknowledge a
    /// transfer (watch sync) must only do so on `true` (DL-3).
    @discardableResult
    func addRecording(_ recording: Recording) -> Bool {
        guard !metadataLoadFailed else {
            Logger.recording.error("addRecording refused: metadata failed to load")
            return false
        }
        var stored = recording
        if stored.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stored.name = "Messung \(recordings.count + 1)"
        }

        if let movedAudio = persistRecordingFile(pathOrName: stored.audioFileName, id: stored.id) {
            stored.audioFileName = movedAudio.lastPathComponent
        } else if !fileManager.fileExists(atPath: url(for: stored).path) {
            Logger.recording.error("addRecording failed: audio file \(stored.audioFileName, privacy: .public) missing")
            return false
        }

        if let measurementName = stored.measurementDataFileName,
           let movedMeasurement = persistMeasurementFile(pathOrName: measurementName, id: stored.id) {
            stored.measurementDataFileName = movedMeasurement.lastPathComponent
        }

        stored.spectralDataAvailable = probeSpectralAvailability(for: stored)

        recordings.insert(stored, at: 0)
        guard saveRecordings() else {
            // Roll back the in-memory insert so the UI never shows a
            // recording that is not in the on-disk catalog. The files stay
            // in place and are re-cataloged by the next successful save.
            recordings.removeAll { $0.id == stored.id }
            return false
        }
        removeOrphanedRecordingFiles()
        return true
    }

    /// Ingests a standalone watch recording transferred via WatchConnectivity
    /// ([[task-5-sync-back]]). Idempotent by id: if a recording with the same id
    /// is already present, this is a no-op that still reports success so the
    /// watch ack flips its catalog entry to `.synced`. Returns true when the
    /// recording is in the store (added now or already present).
    @discardableResult
    func ingestWatchRecording(_ recording: Recording) -> Bool {
        if recordings.contains(where: { $0.id == recording.id }) {
            return true
        }
        return addRecording(recording)
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
        removeOrphanedRecordingFiles()
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
        guard !toDelete.isEmpty else { return }

        for recording in toDelete {
            pendingSoftDeletes[recording.id] = recording
        }
        // Write the sidecar BEFORE removing entries from the metadata file.
        // If the app dies between the two writes, the sidecar still
        // references recordings that are also present in the metadata —
        // restoration on next launch is idempotent.
        writePendingSoftDeleteSidecar(toDelete)
        recordings.removeAll { ids.contains($0.id) }
        saveRecordings()
    }

    /// Restores the most recent soft-deleted batch. No-op if there is
    /// nothing pending.
    func undoLastSoftDelete() {
        guard !pendingSoftDeletes.isEmpty else { return }
        let restored = Array(pendingSoftDeletes.values)
        pendingSoftDeletes.removeAll()
        clearPendingSoftDeleteSidecar()
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
        clearPendingSoftDeleteSidecar()
        removeOrphanedRecordingFiles()
    }

    // MARK: - Soft-delete sidecar persistence

    /// On-disk envelope for the soft-delete sidecar. The timestamp is
    /// recorded for future use (e.g. age-based auto-commit) but the
    /// current recovery policy is conservative: any sidecar found on
    /// launch restores its contents unconditionally. The user can re-
    /// initiate the deletion if that's still what they want.
    private struct PendingSoftDeleteSidecar: Codable {
        let timestamp: Date
        let recordings: [Recording]
    }

    private func writePendingSoftDeleteSidecar(_ entries: [Recording]) {
        guard !entries.isEmpty else {
            clearPendingSoftDeleteSidecar()
            return
        }
        let sidecar = PendingSoftDeleteSidecar(timestamp: Date(), recordings: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(sidecar)
            try data.write(to: pendingSoftDeleteSidecarURL, options: .atomic)
        } catch {
            Logger.recording.error("Failed to write pending-soft-delete sidecar: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearPendingSoftDeleteSidecar() {
        let url = pendingSoftDeleteSidecarURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            Logger.recording.error("Failed to clear pending-soft-delete sidecar: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Called from `init` after `loadRecordings`. If a sidecar exists,
    /// the previous session was killed during a soft-delete undo
    /// window — restore the entries into the visible list and clear
    /// the sidecar. Files were never removed (the timer that would
    /// have called `removeFiles(for:)` never fired), so the
    /// restoration is complete: no audio / measurement / photo
    /// hand-cleanup needed.
    private func restorePendingSoftDeletesFromSidecarIfNeeded() {
        let url = pendingSoftDeleteSidecarURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let sidecar = try decoder.decode(PendingSoftDeleteSidecar.self, from: data)

            // Dedupe by id — sidecar and metadata can overlap if the
            // crash happened between the two writes inside
            // `softDeleteRecordings`.
            let existingIDs = Set(recordings.map { $0.id })
            let toRestore = sidecar.recordings.filter { !existingIDs.contains($0.id) }
            if !toRestore.isEmpty {
                recordings.append(contentsOf: toRestore)
                recordings.sort { $0.startDate > $1.startDate }
                saveRecordings()
            }
            try fileManager.removeItem(at: url)
            Logger.recording.info("Restored \(toRestore.count) soft-deleted recording(s) from sidecar")
        } catch {
            // Corrupt sidecar — log and drop so it doesn't block future
            // loads. The recordings it referenced (if any) are already
            // gone from the metadata; the audio files on disk become
            // orphaned, but the manager remains in a consistent state.
            Logger.recording.error("Discarding corrupt pending-soft-delete sidecar: \(error.localizedDescription, privacy: .public)")
            try? fileManager.removeItem(at: url)
        }
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
            fftBlockSize: source.fftBlockSize,
            spectralDataAvailable: newMeasurementFileName != nil ? source.spectralDataAvailable : false
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
                Logger.recording.error("Failed to copy recording file \(sourceURL.lastPathComponent, privacy: .public) to \(targetURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    @discardableResult
    private func saveRecordings() -> Bool {
        guard !metadataLoadFailed else {
            Logger.recording.error("Refusing to overwrite metadata after load failure")
            return false
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recordings)
            try data.write(to: metadataURL, options: .atomic)
            persistenceError = nil
            return true
        } catch {
            persistenceError = error.localizedDescription
            Logger.recording.error("Metadata save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated static func resolvedRecordingDuration(
        audioURL: URL,
        measurementURL: URL?,
        fallback: TimeInterval
    ) -> TimeInterval {
        RecordingDurationResolver.resolved(
            audioURL: audioURL,
            measurementURL: measurementURL,
            fallback: fallback
        )
    }

    private func loadRecordings() {
        metadataLoadFailed = false
        guard fileManager.fileExists(atPath: metadataURL.path) else { return }
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            // Per-row tolerant decode: a single corrupt entry (e.g. a
            // missing `id` field after the strict-decode change in
            // `Recording.init(from:)`) used to abort the entire load.
            // The wrapper isolates each entry so neighbours still
            // parse.
            let entries = try decoder.decode([FailableRecording].self, from: data)
            let loaded = entries.compactMap { $0.value }
            let dropped = entries.count - loaded.count
            recordings = loaded
            persistenceError = nil
            if dropped > 0 {
                Logger.recording.warning("Skipped \(dropped) malformed recording metadata entr\(dropped == 1 ? "y" : "ies")")
            }
            backfillSpectralFlagsIfNeeded()
            removeOrphanedRecordingFiles()
        } catch {
            metadataLoadFailed = true
            persistenceError = error.localizedDescription
            Logger.recording.error("Metadata load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func probeSpectralAvailability(for recording: Recording) -> Bool? {
        guard let url = measurementURL(for: recording) else { return nil }
        return MeasurementSpectralAvailability.hasUsableSpectralData(fileURL: url)
    }

    private func backfillSpectralFlagsIfNeeded() {
        var changed = false
        for index in recordings.indices where recordings[index].spectralDataAvailable == nil {
            recordings[index].spectralDataAvailable = probeSpectralAvailability(for: recordings[index])
            changed = true
        }
        if changed {
            saveRecordings()
        }
    }

    private func referencedRecordingFileNames() -> Set<String> {
        var names: Set<String> = []
        func add(_ pathOrName: String) {
            let trimmed = pathOrName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if trimmed.contains("/") {
                names.insert(URL(fileURLWithPath: trimmed).lastPathComponent)
            } else {
                names.insert(trimmed)
            }
        }

        for recording in recordings {
            add(recording.audioFileName)
            if let measurement = recording.measurementDataFileName {
                add(measurement)
            }
            for photo in recording.photoFileNames {
                add(photo)
            }
        }
        for recording in pendingSoftDeletes.values {
            add(recording.audioFileName)
            if let measurement = recording.measurementDataFileName {
                add(measurement)
            }
            for photo in recording.photoFileNames {
                add(photo)
            }
        }
        // DL-2: recordings parked in the soft-delete sidecar by a previous
        // session are still recoverable — their files must survive the
        // orphan sweep that `loadRecordings()` runs before the sidecar is
        // restored. Reading the sidecar here keeps this robust to any
        // future reordering of init.
        for recording in sidecarRecordings() {
            add(recording.audioFileName)
            if let measurement = recording.measurementDataFileName {
                add(measurement)
            }
            for photo in recording.photoFileNames {
                add(photo)
            }
        }
        if let pendingAudioURL {
            add(pendingAudioURL.path)
        }
        return names
    }

    /// Recordings referenced by the on-disk soft-delete sidecar, or `[]`.
    private func sidecarRecordings() -> [Recording] {
        let url = pendingSoftDeleteSidecarURL
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PendingSoftDeleteSidecar.self, from: data))?.recordings ?? []
    }

    @discardableResult
    private func removeOrphanedRecordingFiles() -> Int {
        guard !metadataLoadFailed else { return 0 }
        return RecordingOrphanCleanup.removeOrphans(
            in: recordingsDirectory,
            referencedFileNames: referencedRecordingFileNames(),
            fileManager: fileManager
        )
    }
}

/// Decodable wrapper that swallows per-row decode failures so
/// `RecordingManager.loadRecordings` can recover the maximum number
/// of valid entries from a partially-corrupt metadata file.
private struct FailableRecording: Decodable {
    let value: Recording?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Recording.self)
    }
}
