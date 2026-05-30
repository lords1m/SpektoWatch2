import Foundation
import Combine
import os

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

    /// Catalog ordered newest-first. Loaded from disk on init.
    @Published private(set) var recordings: [WatchRecordingMetadata] = []

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

    /// Removes a recording and its files from disk.
    func delete(_ recording: WatchRecordingMetadata) {
        try? fileManager.removeItem(at: audioURL(for: recording))
        try? fileManager.removeItem(at: measurementURL(for: recording))
        recordings.removeAll { $0.id == recording.id }
        saveCatalog()
    }

    // MARK: - Persistence

    private func loadCatalog() {
        guard let data = try? Data(contentsOf: catalogURL) else { return }
        do {
            let decoded = try JSONDecoder().decode([WatchRecordingMetadata].self, from: data)
            // Drop catalog entries whose audio file vanished (e.g. partial write
            // before a crash) so the UI never references missing files.
            recordings = decoded
                .filter { fileManager.fileExists(atPath: directory.appendingPathComponent($0.audioFileName).path) }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            log.error("catalog decode failed: \(String(describing: error), privacy: .public)")
        }
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
