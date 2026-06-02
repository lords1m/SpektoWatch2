import Foundation
import OSLog

/// Removes recording-directory files that are not referenced by catalog metadata.
enum RecordingOrphanCleanup {
    private static let removableExtensions: Set<String> = [
        "caf", "m4a", "wav", "aiff", "spekto", "swr", "jpg", "jpeg", "png",
    ]

    private static let protectedFileNames: Set<String> = [
        "recordings_metadata_v2.json",
        "recordings_pending_soft_delete.json",
    ]

    /// Returns the number of files removed.
    static func removeOrphans(
        in directory: URL,
        referencedFileNames: Set<String>,
        fileManager: FileManager = .default
    ) -> Int {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var removed = 0
        for url in entries {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }

            let name = url.lastPathComponent
            if protectedFileNames.contains(name) || referencedFileNames.contains(name) {
                continue
            }

            let ext = url.pathExtension.lowercased()
            let isPlaceholderAudio = name.hasPrefix("recording_") && ext == "caf"
            guard removableExtensions.contains(ext) || isPlaceholderAudio else {
                continue
            }

            do {
                try fileManager.removeItem(at: url)
                removed += 1
                Logger.recording.info("Removed orphan recording file: \(name, privacy: .public)")
            } catch {
                Logger.recording.error(
                    "Failed to remove orphan \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return removed
    }
}
