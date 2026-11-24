import Combine
import Foundation
import OSLog
import SwiftUI

// Persistent store for saved masking profiles.
// Profiles are written as JSON to Documents/Masking/profiles.json.
//
// DL-9: a decode failure must never lead to the file being overwritten by
// the (empty) in-memory list. On failure the file is backed up, `loadFailed`
// is set and `persist()` refuses to write until the user explicitly calls
// `resetAfterLoadFailure()`. Write errors are logged and published.
@MainActor
final class MaskingProfileManager: ObservableObject {
    @Published private(set) var profiles: [MaskingProfile] = []
    /// `true` when `profiles.json` exists but could not be read/decoded.
    @Published private(set) var loadFailed = false
    /// Last persistence error (load or write), for UI surfacing.
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private static let log = Logger(subsystem: "com.spektowatch", category: "masking.profiles")

    init(directory: URL? = nil) {
        let dir: URL
        if let directory {
            dir = directory
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            dir = docs.appendingPathComponent("Masking", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("profiles.json")
        load()
    }

    func save(_ profile: MaskingProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.insert(profile, at: 0)
        }
        persist()
    }

    func delete(offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        persist()
    }

    /// Explicit user action after a load failure: the unreadable file has
    /// already been backed up, so saving the current list is allowed again.
    func resetAfterLoadFailure() {
        loadFailed = false
        persistenceError = nil
        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            profiles = try JSONDecoder().decode([MaskingProfile].self, from: data)
            loadFailed = false
        } catch {
            loadFailed = true
            persistenceError = error.localizedDescription
            Self.log.error("Masking profiles load failed: \(error.localizedDescription, privacy: .public)")
            backupUnreadableFile()
        }
    }

    private func backupUnreadableFile() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("profiles.corrupt-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: fileURL, to: backup)
            Self.log.error("Backed up unreadable masking profiles to \(backup.lastPathComponent, privacy: .public)")
        } catch {
            Self.log.error("Masking profiles backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() {
        guard !loadFailed else {
            Self.log.error("Refusing to overwrite masking profiles after load failure")
            return
        }
        do {
            let data = try JSONEncoder().encode(profiles)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            Self.log.error("Masking profiles save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
