import Foundation
import Combine
import AVFoundation
import os
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Durable catalog of standalone watch recordings. The on-disk catalog (a JSON
/// sidecar next to the audio + `.swr` files in the app container) is the source
/// of truth for the recordings UI ([[task-4-recordings-ui]]) and sync-back
/// ([[task-5-sync-back]]). Recordings live under Application Support — NOT
/// `temporaryDirectory` — so they survive force-quit and relaunch.
/// Mutations (`register`/`update`/`setSyncState`/`delete`) drive `@Published`
/// state and must be called on the main thread (they are — from `stopRecording`
/// and the recordings UI). `directory` is an immutable `let`, so reading it from
/// the audio/permission thread to construct a `WatchRecordingSession` is safe.
final class WatchRecordingStore: ObservableObject {
    static let shared = WatchRecordingStore()

    /// Catalog ordered newest-first. Loaded from disk on init. Includes the
    /// provisional entry of a recording in progress (WL-2).
    @Published private(set) var recordings: [WatchRecordingMetadata] = []

    /// Finished recordings only (what the recordings UI lists).
    var finishedRecordings: [WatchRecordingMetadata] {
        recordings.filter { $0.isInProgress != true }
    }

    private let fileManager = FileManager.default
    private let log = Logger(subsystem: "com.spektowatch.watch", category: "RecordingStore")

    /// Stable per-recording container. Application Support is excluded from the
    /// user's view and persists across launches (unlike temporaryDirectory).
    let directory: URL

    private var catalogURL: URL {
        directory.appendingPathComponent("watch_recordings_catalog.json")
    }

    init(baseDirectory: URL? = nil) {
        let root = baseDirectory
            ?? (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = root.appendingPathComponent("WatchRecordings", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        self.directory = dir
        loadCatalog()
    }

    // MARK: - Per-recording URLs

    func audioURL(for recording: WatchRecordingMetadata) -> URL {
        directory.appendingPathComponent(recording.audioFileName)
    }

    func measurementURL(for recording: WatchRecordingMetadata) -> URL {
        directory.appendingPathComponent(recording.measurementFileName)
    }

    // MARK: - Mutation

    /// Inserts (or replaces, by id) a finished recording and persists the catalog.
    func register(_ recording: WatchRecordingMetadata) {
        recordings.removeAll { $0.id == recording.id }
        recordings.insert(recording, at: 0)
        saveCatalog()
    }

    /// WL-2: writes the provisional (`isInProgress`) entry before capture.
    func beginRecording(_ provisional: WatchRecordingMetadata) {
        var entry = provisional
        entry.isInProgress = true
        register(entry)
    }

    /// Removes a provisional entry whose capture never started.
    func discardInProgressRecording(id: UUID) {
        guard let rec = recordings.first(where: { $0.id == id && $0.isInProgress == true }) else { return }
        delete(rec)
    }

    func update(_ recording: WatchRecordingMetadata) {
        guard let idx = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[idx] = recording
        saveCatalog()
    }

    func setSyncState(_ state: WatchRecordingSyncState, for id: UUID) {
        guard let idx = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[idx].syncState = state
        saveCatalog()
    }

    /// Removes a recording and its files from disk. WC-4: queued/in-flight
    /// `transferFile`s for it are cancelled first so the phone never receives
    /// a `.caf` whose `.swr` was deleted mid-transfer.
    func delete(_ recording: WatchRecordingMetadata) {
        cancelOutstandingTransfers(for: recording.id)
        try? fileManager.removeItem(at: audioURL(for: recording))
        try? fileManager.removeItem(at: measurementURL(for: recording))
        recordings.removeAll { $0.id == recording.id }
        saveCatalog()
    }

    private func cancelOutstandingTransfers(for id: UUID) {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        for transfer in WCSession.default.outstandingFileTransfers
        where WatchConnectivityProtocol.recordingId(fromTransfer: transfer.file.metadata ?? [:]) == id {
            transfer.cancel()
        }
        #endif
    }

    // MARK: - Persistence

    private func loadCatalog() {
        var decoded: [WatchRecordingMetadata] = []
        var catalogReadable = true
        if let data = try? Data(contentsOf: catalogURL) {
            do {
                decoded = try JSONDecoder().decode([WatchRecordingMetadata].self, from: data)
            } catch {
                catalogReadable = false
                log.error("catalog decode failed: \(String(describing: error), privacy: .public)")
                let backup = directory.appendingPathComponent("watch_recordings_catalog.corrupt-\(Int(Date().timeIntervalSince1970)).json")
                try? data.write(to: backup, options: .atomic)
            }
        }
        // Drop catalog entries whose audio file vanished so the UI never
        // references missing files. WL-2: entries still marked in-progress
        // belong to a recording interrupted by a crash — finalize them.
        var changed = false
        var surviving: [WatchRecordingMetadata] = []
        for entry in decoded {
            guard fileManager.fileExists(atPath: directory.appendingPathComponent(entry.audioFileName).path) else {
                changed = true
                continue
            }
            if entry.isInProgress == true {
                surviving.append(recover(entry))
                changed = true
            } else {
                surviving.append(entry)
            }
        }
        recordings = surviving.sorted { $0.createdAt > $1.createdAt }
        // Never sweep files when the catalog itself was unreadable: they may
        // all be valid recordings (re-catalogued below instead).
        if recoverUncataloguedFiles() { changed = true }
        if changed || !catalogReadable {
            saveCatalog()
        }
    }

    /// WL-2: finalizes metadata for a recording whose process died while
    /// capturing. Duration comes from the audio file; metrics from the last
    /// `.swr` frame (the reader recovers unfinalized frame counts, DL-4).
    func recover(_ entry: WatchRecordingMetadata) -> WatchRecordingMetadata {
        var result = entry
        result.isInProgress = nil
        result.syncState = .local
        let audioURL = directory.appendingPathComponent(entry.audioFileName)
        if let file = try? AVAudioFile(forReading: audioURL), file.fileFormat.sampleRate > 0 {
            result.duration = Double(file.length) / file.fileFormat.sampleRate
            result.sampleRate = file.fileFormat.sampleRate
        }
        let measurementURL = directory.appendingPathComponent(entry.measurementFileName)
        if let reader = try? MeasurementDataReader(fileURL: measurementURL), reader.frameCount > 0,
           let last = try? reader.readFrameSummary(at: reader.frameCount - 1) {
            let keys = reader.header.metricKeys
            func metric(_ key: String) -> Float? {
                keys.firstIndex(of: key).flatMap { $0 < last.metrics.count ? last.metrics[$0] : nil }
            }
            result.laeq = metric("LAeq")
            result.lcPeak = metric("LCpeak")
            if result.duration <= 0 { result.duration = TimeInterval(last.timestamp) }
        }
        if !result.title.contains("wiederhergestellt") {
            result.title += " (wiederhergestellt)"
        }
        log.notice("recovered interrupted watch recording \(entry.id.uuidString, privacy: .public)")
        return result
    }

    /// WL-2: `.caf` files not referenced by the catalog are re-catalogued if
    /// readable (the catalog write may have been lost); only files that are
    /// both uncatalogued and unreadable are deleted. Returns `true` when the
    /// catalog changed.
    @discardableResult
    private func recoverUncataloguedFiles() -> Bool {
        var referenced = Set<String>()
        for rec in recordings {
            referenced.insert(rec.audioFileName)
            referenced.insert(rec.measurementFileName)
        }
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }
        var changed = false
        for url in contents where url.pathExtension.lowercased() == "caf" {
            let name = url.lastPathComponent
            guard !referenced.contains(name) else { continue }
            let base = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: base),
                  let file = try? AVAudioFile(forReading: url), file.length > 0 else {
                try? fileManager.removeItem(at: url)
                continue
            }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            let provisional = WatchRecordingMetadata(
                id: id,
                title: "Aufnahme",
                createdAt: created,
                sampleRate: file.fileFormat.sampleRate,
                weighting: "A",
                audioFileName: name,
                measurementFileName: "\(base).swr",
                isInProgress: true
            )
            recordings.append(recover(provisional))
            referenced.insert(name)
            referenced.insert("\(base).swr")
            changed = true
        }
        // `.swr` without any audio partner cannot be played back or synced.
        for url in contents where url.pathExtension.lowercased() == "swr" {
            if !referenced.contains(url.lastPathComponent) {
                try? fileManager.removeItem(at: url)
            }
        }
        if changed {
            recordings.sort { $0.createdAt > $1.createdAt }
        }
        return changed
    }

    private func saveCatalog() {
        do {
            let data = try JSONEncoder().encode(recordings)
            try data.write(to: catalogURL, options: .atomic)
        } catch {
            log.error("catalog save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
